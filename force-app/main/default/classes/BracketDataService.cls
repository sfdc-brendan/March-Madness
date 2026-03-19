public with sharing class BracketDataService {

    private static final String ESPN_SCOREBOARD_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard';
    private static final String ESPN_TEAMS_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams';
    private static final String ESPN_RANKINGS_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/rankings';
    private static final Integer HTTP_OK = 200;
    private static final Integer TIMEOUT_MS = 30000;

    public class BracketLoadRequest {
        @InvocableVariable(required=true)
        public Id tournamentId;
    }

    @InvocableMethod(label='Load Bracket Data' description='Loads NCAA tournament bracket data from ESPN')
    public static List<String> loadBracketData(List<BracketLoadRequest> requests) {
        List<String> results = new List<String>();
        for (BracketLoadRequest req : requests) {
            try {
                loadFullBracket(req.tournamentId);
                results.add('Success: Bracket data loaded for tournament ' + req.tournamentId);
            } catch (Exception e) {
                results.add('Error: ' + e.getMessage());
            }
        }
        return results;
    }

    public static void loadFullBracket(Id tournamentId) {
        List<String> dates = buildTournamentDateRange();
        String dateRange = String.join(dates, ',');

        String scoreboardJson = callESPN(
            ESPN_SCOREBOARD_URL + '?groups=100&limit=200&dates=' + dates[0] + '-' + dates[dates.size() - 1]
        );

        if (scoreboardJson == null) return;

        Map<String, Team__c> teamsByName = loadTeamMap(tournamentId);
        List<Game__c> existingGames = loadExistingGames(tournamentId);
        Map<String, Game__c> existingByEspnId = new Map<String, Game__c>();
        Set<String> existingTeamPairs = new Set<String>();

        for (Game__c g : existingGames) {
            if (String.isNotBlank(g.ESPN_Game_Id__c)) {
                existingByEspnId.put(g.ESPN_Game_Id__c, g);
            }
            if (g.Team_1__c != null && g.Team_2__c != null) {
                existingTeamPairs.add(String.valueOf(g.Team_1__c) + '_' + String.valueOf(g.Team_2__c));
                existingTeamPairs.add(String.valueOf(g.Team_2__c) + '_' + String.valueOf(g.Team_1__c));
            }
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(scoreboardJson);
        List<Object> events = (List<Object>) parsed.get('events');
        if (events == null) return;

        List<Game__c> gamesToUpsert = new List<Game__c>();
        Map<String, Team__c> teamsToUpdate = new Map<String, Team__c>();
        Integer gameNumber = existingGames.size() + 1;

        for (Object eventObj : events) {
            Map<String, Object> event = (Map<String, Object>) eventObj;
            List<Object> comps = (List<Object>) event.get('competitions');
            if (comps == null || comps.isEmpty()) continue;

            Map<String, Object> comp = (Map<String, Object>) comps[0];
            String espnGameId = (String) comp.get('id');
            List<Object> competitors = (List<Object>) comp.get('competitors');
            if (competitors == null || competitors.size() < 2) continue;

            Map<String, Object> c1 = (Map<String, Object>) competitors[0];
            Map<String, Object> c2 = (Map<String, Object>) competitors[1];
            Map<String, Object> t1Data = (Map<String, Object>) c1.get('team');
            Map<String, Object> t2Data = (Map<String, Object>) c2.get('team');

            String t1Name = (String) t1Data.get('displayName');
            String t2Name = (String) t2Data.get('displayName');

            if (t1Name == 'TBD' || t2Name == 'TBD') {
                processPlaceholderGame(event, comp, espnGameId, existingByEspnId,
                    gamesToUpsert, tournamentId, gameNumber++);
                continue;
            }

            Team__c team1 = teamsByName.get(t1Name);
            Team__c team2 = teamsByName.get(t2Name);
            if (team1 == null || team2 == null) continue;

            String region = extractRegion(comp);
            String round = extractRoundFromNotes(comp);

            Decimal seed1 = extractSeed(c1);
            Decimal seed2 = extractSeed(c2);

            if (seed1 != null && seed1 >= 1 && seed1 <= 16 && team1.Seed__c != seed1) {
                team1.Seed__c = seed1;
                team1.Region__c = region;
                teamsToUpdate.put(team1.Id, team1);
            }
            if (seed2 != null && seed2 >= 1 && seed2 <= 16 && team2.Seed__c != seed2) {
                team2.Seed__c = seed2;
                team2.Region__c = region;
                teamsToUpdate.put(team2.Id, team2);
            }

            Game__c game;
            if (existingByEspnId.containsKey(espnGameId)) {
                game = existingByEspnId.get(espnGameId);
            } else {
                String pairKey = String.valueOf(team1.Id) + '_' + String.valueOf(team2.Id);
                if (existingTeamPairs.contains(pairKey)) continue;

                game = new Game__c();
                game.Tournament__c = tournamentId;
                game.ESPN_Game_Id__c = espnGameId;
                game.Game_Number__c = gameNumber++;
            }

            game.Team_1__c = team1.Id;
            game.Team_2__c = team2.Id;
            game.Region__c = region;
            game.Round__c = round;

            String dateStr = (String) event.get('date');
            if (dateStr != null && dateStr.length() >= 10) {
                game.Game_Date__c = Date.valueOf(dateStr.substring(0, 10));
            }

            populateGameStatus(game, comp, c1, c2, team1.Id, team2.Id);
            populateVenueAndBroadcast(game, comp);

            gamesToUpsert.add(game);
        }

        if (!teamsToUpdate.isEmpty()) {
            update teamsToUpdate.values();
            System.debug('Updated seeds/regions for ' + teamsToUpdate.size() + ' teams');
        }

        if (!gamesToUpsert.isEmpty()) {
            upsert gamesToUpsert;
            System.debug('Upserted ' + gamesToUpsert.size() + ' tournament games');
        }
    }

    private static void processPlaceholderGame(
        Map<String, Object> event, Map<String, Object> comp,
        String espnGameId, Map<String, Game__c> existingByEspnId,
        List<Game__c> gamesToUpsert, Id tournamentId, Integer gameNumber
    ) {
        String region = extractRegion(comp);
        String round = extractRoundFromNotes(comp);

        Game__c game;
        if (existingByEspnId.containsKey(espnGameId)) {
            game = existingByEspnId.get(espnGameId);
        } else {
            game = new Game__c();
            game.Tournament__c = tournamentId;
            game.ESPN_Game_Id__c = espnGameId;
            game.Game_Number__c = gameNumber;
        }

        game.Region__c = region;
        game.Round__c = round;
        game.Status__c = 'Scheduled';

        String dateStr = (String) event.get('date');
        if (dateStr != null && dateStr.length() >= 10) {
            game.Game_Date__c = Date.valueOf(dateStr.substring(0, 10));
        }

        gamesToUpsert.add(game);
    }

    private static void populateGameStatus(
        Game__c game, Map<String, Object> comp,
        Map<String, Object> c1, Map<String, Object> c2,
        Id team1Id, Id team2Id
    ) {
        Map<String, Object> statusObj = (Map<String, Object>) comp.get('status');
        if (statusObj == null) {
            game.Status__c = 'Scheduled';
            return;
        }

        Map<String, Object> statusType = (Map<String, Object>) statusObj.get('type');
        String state = statusType != null ? (String) statusType.get('state') : '';
        Boolean completed = statusType != null ? (Boolean) statusType.get('completed') : false;

        if (completed == true) {
            game.Status__c = 'Final';

            Map<String, Object> score1 = (Map<String, Object>) c1.get('score');
            Map<String, Object> score2 = (Map<String, Object>) c2.get('score');
            if (score1 != null) {
                Object sv = score1.get('value');
                if (sv != null) game.Team_1_Score__c = ((Decimal) sv).intValue();
            }
            if (score2 != null) {
                Object sv = score2.get('value');
                if (sv != null) game.Team_2_Score__c = ((Decimal) sv).intValue();
            }

            Boolean winner1 = (Boolean) c1.get('winner');
            game.Winner__c = (winner1 == true) ? team1Id : team2Id;
        } else if (state == 'in') {
            game.Status__c = 'In Progress';
        } else {
            game.Status__c = 'Scheduled';
        }
    }

    private static void populateVenueAndBroadcast(Game__c game, Map<String, Object> comp) {
        Map<String, Object> venue = (Map<String, Object>) comp.get('venue');
        if (venue != null) {
            String venueName = (String) venue.get('fullName');
            Map<String, Object> addr = (Map<String, Object>) venue.get('address');
            if (addr != null) {
                String city = (String) addr.get('city');
                String st = (String) addr.get('state');
                if (city != null) venueName = (venueName ?? '') + ' - ' + city + (st != null ? ', ' + st : '');
            }
            game.Venue__c = venueName != null && venueName.length() > 255
                ? venueName.substring(0, 255) : venueName;
        }

        List<Object> broadcasts = (List<Object>) comp.get('broadcasts');
        if (broadcasts != null && !broadcasts.isEmpty()) {
            Map<String, Object> bc = (Map<String, Object>) broadcasts[0];
            List<Object> names = (List<Object>) bc.get('names');
            if (names != null && !names.isEmpty()) {
                game.TV_Network__c = (String) names[0];
            }
        }
    }

    public static void updateGameResults(Id tournamentId) {
        List<Game__c> activeGames = [
            SELECT Id, Game_Date__c
            FROM Game__c
            WHERE Status__c IN ('Scheduled', 'In Progress')
                AND Tournament__c = :tournamentId
                AND Round__c NOT IN ('Conference Quarterfinal', 'Conference Semifinal',
                    'Conference Final', 'Conference First Round', 'Conference Second Round')
        ];
        if (activeGames.isEmpty()) return;

        Set<String> datesToCheck = new Set<String>();
        for (Game__c g : activeGames) {
            if (g.Game_Date__c != null) {
                datesToCheck.add(String.valueOf(g.Game_Date__c).replace('-', ''));
            }
        }

        for (String dateStr : datesToCheck) {
            String responseJson = callESPN(ESPN_SCOREBOARD_URL + '?dates=' + dateStr + '&groups=100&limit=100');
            if (responseJson != null) {
                updateGamesFromScoreboard(responseJson, tournamentId);
            }
        }
    }

    public static void loadTeamStats(Id tournamentId) {
        String rankingsJson = callESPN(ESPN_RANKINGS_URL);
        if (rankingsJson == null) return;

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rankingsJson);
        List<Object> rankings = (List<Object>) parsed.get('rankings');
        if (rankings == null || rankings.isEmpty()) return;

        Map<String, Object> firstPoll = (Map<String, Object>) rankings[0];
        List<Object> ranks = (List<Object>) firstPoll.get('ranks');
        if (ranks == null) return;

        Map<String, Decimal> teamRankings = new Map<String, Decimal>();
        for (Object rankObj : ranks) {
            Map<String, Object> rank = (Map<String, Object>) rankObj;
            Decimal current = (Decimal) rank.get('current');
            Map<String, Object> team = (Map<String, Object>) rank.get('team');
            String teamName = (String) team.get('displayName');
            teamRankings.put(teamName, current);
        }

        List<Team__c> teams = [
            SELECT Id, Name, NET_Ranking__c
            FROM Team__c WHERE Tournament__c = :tournamentId
        ];

        List<Team__c> toUpdate = new List<Team__c>();
        for (Team__c t : teams) {
            if (teamRankings.containsKey(t.Name)) {
                t.NET_Ranking__c = teamRankings.get(t.Name);
                toUpdate.add(t);
            }
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    public static void populateLogos(Id tournamentId) {
        String teamsJson = callESPN(ESPN_TEAMS_URL + '?limit=400&groups=50');
        if (teamsJson == null) return;

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(teamsJson);
        List<Object> sports = (List<Object>) parsed.get('sports');
        if (sports == null || sports.isEmpty()) return;
        Map<String, Object> sport = (Map<String, Object>) sports[0];
        List<Object> leagues = (List<Object>) sport.get('leagues');
        if (leagues == null || leagues.isEmpty()) return;
        Map<String, Object> league = (Map<String, Object>) leagues[0];
        List<Object> espnTeams = (List<Object>) league.get('teams');
        if (espnTeams == null) return;

        Map<String, Map<String, String>> espnData = new Map<String, Map<String, String>>();
        for (Object teamWrapper : espnTeams) {
            Map<String, Object> wrapper = (Map<String, Object>) teamWrapper;
            Map<String, Object> team = (Map<String, Object>) wrapper.get('team');
            if (team == null) continue;
            String name = (String) team.get('displayName');
            String logo = extractLogoUrl(team);
            String color = (String) team.get('color');
            if (name != null) {
                espnData.put(name.toLowerCase(), new Map<String, String>{ 'logo' => logo, 'color' => color });
            }
        }

        List<Team__c> teams = [
            SELECT Id, Name, Logo_URL__c, Primary_Color__c
            FROM Team__c WHERE Tournament__c = :tournamentId
        ];

        List<Team__c> toUpdate = new List<Team__c>();
        for (Team__c t : teams) {
            Map<String, String> data = espnData.get(t.Name.toLowerCase());
            if (data == null) continue;
            Boolean changed = false;
            if (String.isBlank(t.Logo_URL__c) && String.isNotBlank(data.get('logo'))) {
                t.Logo_URL__c = data.get('logo');
                changed = true;
            }
            if (String.isBlank(t.Primary_Color__c) && String.isNotBlank(data.get('color'))) {
                t.Primary_Color__c = data.get('color');
                changed = true;
            }
            if (changed) toUpdate.add(t);
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        System.debug('Populated logos for ' + toUpdate.size() + ' teams');
    }

    // --- Helpers ---

    private static List<String> buildTournamentDateRange() {
        Integer year = Date.today().year();
        List<String> dates = new List<String>();
        Date startDate = Date.newInstance(year, 3, 17);
        Date endDate = Date.newInstance(year, 4, 8);
        Date d = startDate;
        while (d <= endDate) {
            dates.add(String.valueOf(d).replace('-', ''));
            d = d.addDays(1);
        }
        return dates;
    }

    private static Map<String, Team__c> loadTeamMap(Id tournamentId) {
        Map<String, Team__c> teamsByName = new Map<String, Team__c>();
        for (Team__c t : [
            SELECT Id, Name, Seed__c, Region__c
            FROM Team__c WHERE Tournament__c = :tournamentId
        ]) {
            teamsByName.put(t.Name, t);
        }
        return teamsByName;
    }

    private static List<Game__c> loadExistingGames(Id tournamentId) {
        return [
            SELECT Id, ESPN_Game_Id__c, Team_1__c, Team_2__c, Round__c, Region__c
            FROM Game__c
            WHERE Tournament__c = :tournamentId
                AND Round__c IN ('First Four', 'Round of 64', 'Round of 32', 'Sweet 16',
                    'Elite 8', 'Final Four', 'Championship')
        ];
    }

    private static String extractRegion(Map<String, Object> comp) {
        List<Object> notes = (List<Object>) comp.get('notes');
        if (notes == null || notes.isEmpty()) return null;

        for (Object noteObj : notes) {
            Map<String, Object> note = (Map<String, Object>) noteObj;
            String headline = (String) note.get('headline');
            if (String.isBlank(headline)) continue;

            for (String region : new List<String>{ 'East', 'Midwest', 'South', 'West' }) {
                if (headline.containsIgnoreCase(region + ' Region')) return region;
            }
        }
        return 'Final Four';
    }

    private static String extractRoundFromNotes(Map<String, Object> comp) {
        List<Object> notes = (List<Object>) comp.get('notes');
        if (notes == null || notes.isEmpty()) return 'Round of 64';

        for (Object noteObj : notes) {
            Map<String, Object> note = (Map<String, Object>) noteObj;
            String headline = (String) note.get('headline');
            if (String.isBlank(headline)) continue;

            if (headline.containsIgnoreCase('First Four')) return 'First Four';
            if (headline.containsIgnoreCase('1st Round')) return 'Round of 64';
            if (headline.containsIgnoreCase('2nd Round')) return 'Round of 32';
            if (headline.containsIgnoreCase('Sweet 16') || headline.containsIgnoreCase('Regional Semifinal'))
                return 'Sweet 16';
            if (headline.containsIgnoreCase('Elite Eight') || headline.containsIgnoreCase('Regional Final'))
                return 'Elite 8';
            if (headline.containsIgnoreCase('Final Four') || headline.containsIgnoreCase('National Semifinal'))
                return 'Final Four';
            if (headline.containsIgnoreCase('Championship') || headline.containsIgnoreCase('National Championship'))
                return 'Championship';
        }
        return 'Round of 64';
    }

    private static Decimal extractSeed(Map<String, Object> competitor) {
        Map<String, Object> rank = (Map<String, Object>) competitor.get('curatedRank');
        if (rank == null) return null;
        Object current = rank.get('current');
        if (current == null) return null;
        Decimal val = ((Decimal) current);
        return (val >= 1 && val <= 16) ? val : null;
    }

    private static String extractLogoUrl(Map<String, Object> team) {
        List<Object> logos = (List<Object>) team.get('logos');
        if (logos == null || logos.isEmpty()) return null;
        Map<String, Object> firstLogo = (Map<String, Object>) logos[0];
        return (String) firstLogo.get('href');
    }

    private static void updateGamesFromScoreboard(String jsonBody, Id tournamentId) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> events = (List<Object>) parsed.get('events');
        if (events == null) return;

        Map<String, Team__c> teamsByName = new Map<String, Team__c>();
        for (Team__c t : [SELECT Id, Name FROM Team__c WHERE Tournament__c = :tournamentId]) {
            teamsByName.put(t.Name, t);
        }

        Map<String, Game__c> gamesByEspnId = new Map<String, Game__c>();
        Map<String, Game__c> gamesByTeamPair = new Map<String, Game__c>();
        for (Game__c g : [
            SELECT Id, ESPN_Game_Id__c, Team_1__c, Team_2__c, Status__c
            FROM Game__c
            WHERE Status__c != 'Final' AND Tournament__c = :tournamentId
        ]) {
            if (String.isNotBlank(g.ESPN_Game_Id__c)) {
                gamesByEspnId.put(g.ESPN_Game_Id__c, g);
            }
            if (g.Team_1__c != null && g.Team_2__c != null) {
                gamesByTeamPair.put(String.valueOf(g.Team_1__c) + '_' + String.valueOf(g.Team_2__c), g);
                gamesByTeamPair.put(String.valueOf(g.Team_2__c) + '_' + String.valueOf(g.Team_1__c), g);
            }
        }

        List<Game__c> gamesToUpdate = new List<Game__c>();

        for (Object eventObj : events) {
            Map<String, Object> event = (Map<String, Object>) eventObj;
            List<Object> comps = (List<Object>) event.get('competitions');
            if (comps == null || comps.isEmpty()) continue;

            Map<String, Object> comp = (Map<String, Object>) comps[0];
            String compId = (String) comp.get('id');

            Map<String, Object> statusObj = (Map<String, Object>) comp.get('status');
            Map<String, Object> statusType = (Map<String, Object>) statusObj.get('type');
            Boolean completed = (Boolean) statusType.get('completed');
            if (!completed) continue;

            List<Object> competitors = (List<Object>) comp.get('competitors');
            if (competitors == null || competitors.size() < 2) continue;

            Map<String, Object> c1 = (Map<String, Object>) competitors[0];
            Map<String, Object> c2 = (Map<String, Object>) competitors[1];

            Game__c matchingGame = gamesByEspnId.get(compId);
            if (matchingGame == null) {
                Map<String, Object> t1d = (Map<String, Object>) c1.get('team');
                Map<String, Object> t2d = (Map<String, Object>) c2.get('team');
                Team__c team1 = teamsByName.get((String) t1d.get('displayName'));
                Team__c team2 = teamsByName.get((String) t2d.get('displayName'));
                if (team1 != null && team2 != null) {
                    String pairKey = String.valueOf(team1.Id) + '_' + String.valueOf(team2.Id);
                    matchingGame = gamesByTeamPair.get(pairKey);
                }
            }
            if (matchingGame == null) continue;

            Map<String, Object> score1 = (Map<String, Object>) c1.get('score');
            Map<String, Object> score2 = (Map<String, Object>) c2.get('score');
            if (score1 != null) {
                Object sv = score1.get('value');
                if (sv != null) matchingGame.Team_1_Score__c = ((Decimal) sv).intValue();
            }
            if (score2 != null) {
                Object sv = score2.get('value');
                if (sv != null) matchingGame.Team_2_Score__c = ((Decimal) sv).intValue();
            }

            matchingGame.Status__c = 'Final';
            Boolean winner1 = (Boolean) c1.get('winner');

            Map<String, Object> t1d = (Map<String, Object>) c1.get('team');
            Map<String, Object> t2d = (Map<String, Object>) c2.get('team');
            Team__c team1 = teamsByName.get((String) t1d.get('displayName'));
            Team__c team2 = teamsByName.get((String) t2d.get('displayName'));
            if (team1 != null && team2 != null) {
                matchingGame.Winner__c = (winner1 == true) ? team1.Id : team2.Id;
            }

            gamesToUpdate.add(matchingGame);
        }

        if (!gamesToUpdate.isEmpty()) {
            update gamesToUpdate;
            System.debug('Updated results for ' + gamesToUpdate.size() + ' games');
        }
    }

    private static String callESPN(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == HTTP_OK) {
                return res.getBody();
            }
            System.debug(LoggingLevel.ERROR, 'ESPN API HTTP ' + res.getStatusCode() + ': ' + url);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ESPN API callout failed: ' + e.getMessage());
        }
        return null;
    }
}
