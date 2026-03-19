public with sharing class ConferenceTournamentService {

    private static final String ESPN_SCOREBOARD_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard';
    private static final String ESPN_CONF_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/conferences';
    private static final Integer HTTP_OK = 200;
    private static final Integer TIMEOUT_MS = 30000;

    private static final Map<String, String> ROUND_MAP = new Map<String, String>{
        'final' => 'Conference Final',
        'championship' => 'Conference Final',
        'semifinal' => 'Conference Semifinal',
        'semifinals' => 'Conference Semifinal',
        'quarterfinal' => 'Conference Quarterfinal',
        'quarterfinals' => 'Conference Quarterfinal',
        'second round' => 'Conference Second Round',
        'first round' => 'Conference First Round'
    };

    private static final Map<String, String> MAJOR_CONFERENCES = new Map<String, String>{
        '2' => 'ACC',
        '4' => 'Big 12',
        '3' => 'Big East',
        '7' => 'Big Ten',
        '8' => 'SEC',
        '62' => 'American Athletic',
        '44' => 'Mountain West',
        '26' => 'West Coast',
        '15' => 'Atlantic 10',
        '18' => 'Missouri Valley',
        '10' => 'Conference USA',
        '46' => 'Sun Belt',
        '1' => 'America East',
        '5' => 'Colonial Athletic',
        '49' => 'Horizon League',
        '16' => 'Big Sky',
        '20' => 'Ohio Valley',
        '21' => 'Pac-12',
        '24' => 'Southland',
        '27' => 'West Athletic',
        '29' => 'Mid-Eastern Athletic',
        '30' => 'Southwestern Athletic',
        '45' => 'Ivy League',
        '47' => 'MAAC',
        '48' => 'Big West',
        '6' => 'Mid-American',
        '9' => 'Patriot League',
        '11' => 'Southern',
        '13' => 'Atlantic Sun',
        '14' => 'Northeast',
        '17' => 'Big South',
        '19' => 'Summit League'
    };

    @InvocableMethod(label='Load Conference Tournaments' description='Creates conference tournament records and loads games from ESPN')
    public static List<String> loadConferenceTournaments(List<Id> parentTournamentIds) {
        List<String> results = new List<String>();
        for (Id parentId : parentTournamentIds) {
            Integer count = createConferenceTournaments(parentId);
            results.add('Created/updated ' + count + ' conference tournaments.');
        }
        return results;
    }

    public static Integer createConferenceTournaments(Id parentTournamentId) {
        Tournament__c parent = [
            SELECT Id, Year__c FROM Tournament__c WHERE Id = :parentTournamentId LIMIT 1
        ];

        Map<String, Tournament__c> existingConfs = new Map<String, Tournament__c>();
        for (Tournament__c t : [
            SELECT Id, ESPN_Conference_Id__c, Conference_Name__c
            FROM Tournament__c
            WHERE Parent_Tournament__c = :parentTournamentId AND Type__c = 'Conference'
        ]) {
            existingConfs.put(t.ESPN_Conference_Id__c, t);
        }

        List<Tournament__c> toUpsert = new List<Tournament__c>();

        for (String confId : MAJOR_CONFERENCES.keySet()) {
            String confName = MAJOR_CONFERENCES.get(confId);
            Tournament__c conf;

            if (existingConfs.containsKey(confId)) {
                conf = existingConfs.get(confId);
            } else {
                conf = new Tournament__c();
                conf.Parent_Tournament__c = parentTournamentId;
                conf.Type__c = 'Conference';
                conf.ESPN_Conference_Id__c = confId;
            }

            conf.Name = confName + ' Tournament ' + String.valueOf(parent.Year__c?.intValue());
            conf.Conference_Name__c = confName;
            conf.Year__c = parent.Year__c;
            conf.Status__c = 'Active';

            toUpsert.add(conf);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        return toUpsert.size();
    }

    public static Integer loadGamesForConference(Id conferenceTournamentId) {
        Tournament__c conf = [
            SELECT Id, ESPN_Conference_Id__c, Conference_Name__c, Year__c
            FROM Tournament__c
            WHERE Id = :conferenceTournamentId
            LIMIT 1
        ];

        if (String.isBlank(conf.ESPN_Conference_Id__c)) {
            return 0;
        }

        String url = ESPN_SCOREBOARD_URL + '?groups=' + conf.ESPN_Conference_Id__c
            + '&limit=50&dates=' + getTournamentDateRange();

        String responseJson = callESPN(url);
        if (responseJson == null) {
            return 0;
        }

        return parseAndUpsertGames(responseJson, conferenceTournamentId, conf.Conference_Name__c);
    }

    public static void loadAllConferenceGames(Id parentTournamentId) {
        List<Tournament__c> confTournaments = [
            SELECT Id, ESPN_Conference_Id__c, Conference_Name__c
            FROM Tournament__c
            WHERE Parent_Tournament__c = :parentTournamentId
              AND Type__c = 'Conference'
        ];

        for (Tournament__c conf : confTournaments) {
            try {
                Integer gamesLoaded = loadGamesForConference(conf.Id);
                System.debug('Loaded ' + gamesLoaded + ' games for ' + conf.Conference_Name__c);
            } catch (System.CalloutException e) {
                System.debug(LoggingLevel.WARN,
                    'Callout limit reached after loading games for ' + conf.Conference_Name__c);
                break;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'Error loading ' + conf.Conference_Name__c + ': ' + e.getMessage());
            }
        }
    }

    public static void refreshScores(Id parentTournamentId) {
        List<Tournament__c> activeConfs = [
            SELECT Id, ESPN_Conference_Id__c, Conference_Name__c
            FROM Tournament__c
            WHERE Parent_Tournament__c = :parentTournamentId
              AND Type__c = 'Conference'
              AND Status__c = 'Active'
        ];

        for (Tournament__c conf : activeConfs) {
            try {
                loadGamesForConference(conf.Id);
            } catch (System.CalloutException e) {
                break;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Refresh error for ' + conf.Conference_Name__c + ': ' + e.getMessage());
            }
        }
    }

    private static Integer parseAndUpsertGames(String jsonBody, Id tournamentId, String confName) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> events = (List<Object>) parsed.get('events');
        if (events == null || events.isEmpty()) {
            return 0;
        }

        Map<String, Game__c> existingGames = new Map<String, Game__c>();
        for (Game__c g : [
            SELECT Id, ESPN_Game_Id__c FROM Game__c
            WHERE Tournament__c = :tournamentId AND ESPN_Game_Id__c != null
        ]) {
            existingGames.put(g.ESPN_Game_Id__c, g);
        }

        Map<String, Team__c> teamsByName = new Map<String, Team__c>();
        for (Team__c t : [SELECT Id, Name FROM Team__c]) {
            teamsByName.put(t.Name.toLowerCase(), t);
        }

        List<Game__c> toUpsert = new List<Game__c>();
        Integer position = 0;

        for (Object eventObj : events) {
            Map<String, Object> event = (Map<String, Object>) eventObj;
            String espnId = (String) event.get('id');
            String gameName = (String) event.get('shortName');
            String eventDate = (String) event.get('date');

            String roundName = 'Conference First Round';

            List<Object> competitions = (List<Object>) event.get('competitions');
            if (competitions == null || competitions.isEmpty()) continue;

            Map<String, Object> comp = (Map<String, Object>) competitions[0];
            List<Object> competitors = (List<Object>) comp.get('competitors');
            if (competitors == null || competitors.size() < 2) continue;

            Map<String, Object> compInfo1 = (Map<String, Object>) competitors[0];
            Map<String, Object> compInfo2 = (Map<String, Object>) competitors[1];

            Map<String, Object> teamObj1 = (Map<String, Object>) compInfo1.get('team');
            Map<String, Object> teamObj2 = (Map<String, Object>) compInfo2.get('team');

            String teamName1 = (String) teamObj1.get('displayName');
            String teamName2 = (String) teamObj2.get('displayName');

            String score1 = (String) compInfo1.get('score');
            String score2 = (String) compInfo2.get('score');

            Boolean homeAway1 = 'home'.equalsIgnoreCase((String) compInfo1.get('homeAway'));

            Map<String, Object> statusObj = (Map<String, Object>) comp.get('status');
            Map<String, Object> statusType = (statusObj != null) ?
                (Map<String, Object>) statusObj.get('type') : null;
            String statusName = (statusType != null) ? (String) statusType.get('name') : 'STATUS_SCHEDULED';
            Boolean isCompleted = 'STATUS_FINAL'.equalsIgnoreCase(statusName);
            Boolean isInProgress = 'STATUS_IN_PROGRESS'.equalsIgnoreCase(statusName);

            List<Object> notesList = (List<Object>) event.get('notes');
            if (notesList != null && !notesList.isEmpty()) {
                Map<String, Object> note = (Map<String, Object>) notesList[0];
                String headline = (String) note.get('headline');
                if (String.isNotBlank(headline)) {
                    roundName = mapRound(headline);
                }
            } else {
                roundName = 'Conference First Round';
            }

            Map<String, Object> venue = (Map<String, Object>) comp.get('venue');
            String venueName = '';
            if (venue != null) {
                venueName = (String) venue.get('fullName');
            }

            Game__c game;
            String gameKey = espnId;
            if (existingGames.containsKey(gameKey)) {
                game = existingGames.get(gameKey);
            } else {
                game = new Game__c();
                game.Tournament__c = tournamentId;
                game.ESPN_Game_Id__c = gameKey;
            }

            game.Round__c = roundName;
            game.Bracket_Position__c = position++;

            if (String.isNotBlank(eventDate)) {
                try {
                    game.Game_Date__c = Date.valueOf(eventDate.substring(0, 10));
                } catch (Exception e) {
                    // date parse failure is non-critical
                }
            }

            if (isCompleted) {
                game.Status__c = 'Final';
            } else if (isInProgress) {
                game.Status__c = 'In Progress';
            } else {
                game.Status__c = 'Scheduled';
            }

            Team__c sfTeam1 = findTeam(teamName1, teamsByName);
            Team__c sfTeam2 = findTeam(teamName2, teamsByName);

            if (homeAway1) {
                if (sfTeam1 != null) game.Team_1__c = sfTeam1.Id;
                if (sfTeam2 != null) game.Team_2__c = sfTeam2.Id;
                game.Team_1_Score__c = parseScore(score1);
                game.Team_2_Score__c = parseScore(score2);
            } else {
                if (sfTeam2 != null) game.Team_1__c = sfTeam2.Id;
                if (sfTeam1 != null) game.Team_2__c = sfTeam1.Id;
                game.Team_1_Score__c = parseScore(score2);
                game.Team_2_Score__c = parseScore(score1);
            }

            if (isCompleted && game.Team_1_Score__c != null && game.Team_2_Score__c != null) {
                if (game.Team_1_Score__c > game.Team_2_Score__c) {
                    game.Winner__c = game.Team_1__c;
                } else {
                    game.Winner__c = game.Team_2__c;
                }
            }

            toUpsert.add(game);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        return toUpsert.size();
    }

    private static String mapRound(String espnRoundText) {
        if (String.isBlank(espnRoundText)) return 'Conference First Round';
        String lower = espnRoundText.toLowerCase();
        for (String key : ROUND_MAP.keySet()) {
            if (lower.contains(key)) {
                return ROUND_MAP.get(key);
            }
        }
        return 'Conference First Round';
    }

    private static Team__c findTeam(String espnName, Map<String, Team__c> teamsByName) {
        if (String.isBlank(espnName)) return null;
        String lower = espnName.toLowerCase();
        if (teamsByName.containsKey(lower)) {
            return teamsByName.get(lower);
        }
        for (String key : teamsByName.keySet()) {
            if (key.contains(lower) || lower.contains(key)) {
                return teamsByName.get(key);
            }
        }
        return null;
    }

    private static Decimal parseScore(String score) {
        if (String.isBlank(score)) return null;
        try {
            return Decimal.valueOf(score.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String getTournamentDateRange() {
        Date today = Date.today();
        Date weekAgo = today.addDays(-7);
        Date weekAhead = today.addDays(7);
        return weekAgo.year()
            + String.valueOf(weekAgo.month()).leftPad(2, '0')
            + String.valueOf(weekAgo.day()).leftPad(2, '0')
            + '-'
            + weekAhead.year()
            + String.valueOf(weekAhead.month()).leftPad(2, '0')
            + String.valueOf(weekAhead.day()).leftPad(2, '0');
    }

    private static String callESPN(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == HTTP_OK) {
                return res.getBody();
            }
            System.debug(LoggingLevel.ERROR,
                'ESPN API HTTP ' + res.getStatusCode() + ': ' + res.getBody().left(500));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ESPN API callout failed: ' + e.getMessage());
        }
        return null;
    }

    public static Map<String, Object> getConferenceTournamentSummary(Id parentTournamentId) {
        Map<String, Object> summary = new Map<String, Object>();

        List<Tournament__c> confs = [
            SELECT Id, Name, Conference_Name__c, Status__c, Champion__c, Logo_URL__c,
                   ESPN_Conference_Id__c,
                   (SELECT Id, Status__c, Team_1__r.Name, Team_1__r.Seed__c,
                           Team_2__r.Name, Team_2__r.Seed__c,
                           Team_1_Score__c, Team_2_Score__c, Winner__r.Name,
                           Game_Date__c, Round__c
                    FROM Games__r
                    ORDER BY Game_Date__c DESC, Bracket_Position__c ASC
                    LIMIT 20)
            FROM Tournament__c
            WHERE Parent_Tournament__c = :parentTournamentId
              AND Type__c = 'Conference'
            ORDER BY Conference_Name__c ASC
        ];

        summary.put('totalConferences', confs.size());
        summary.put('conferences', confs);

        Integer completed = 0;
        Integer active = 0;
        for (Tournament__c c : confs) {
            if (c.Status__c == 'Complete') completed++;
            if (c.Status__c == 'Active') active++;
        }
        summary.put('completedCount', completed);
        summary.put('activeCount', active);

        return summary;
    }
}
