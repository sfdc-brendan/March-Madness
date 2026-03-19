public with sharing class ESPNScoreboardService {

    private static final String SCOREBOARD_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard';
    private static final Integer HTTP_OK = 200;
    private static final Integer TIMEOUT_MS = 15000;

    public class ScoreboardResult {
        @AuraEnabled public List<ScoreboardGame> games;
        @AuraEnabled public Integer totalGames;
        @AuraEnabled public Integer liveGames;
        @AuraEnabled public Integer completedGames;
        @AuraEnabled public Integer scheduledGames;
        @AuraEnabled public String asOfTime;
    }

    public class ScoreboardGame {
        @AuraEnabled public String espnId;
        @AuraEnabled public String shortName;
        @AuraEnabled public String gameDate;

        @AuraEnabled public String homeTeam;
        @AuraEnabled public String homeAbbr;
        @AuraEnabled public String homeLogo;
        @AuraEnabled public String homeColor;
        @AuraEnabled public String homeScore;
        @AuraEnabled public String homeRecord;
        @AuraEnabled public Integer homeRank;
        @AuraEnabled public Boolean homeWinner;

        @AuraEnabled public String awayTeam;
        @AuraEnabled public String awayAbbr;
        @AuraEnabled public String awayLogo;
        @AuraEnabled public String awayColor;
        @AuraEnabled public String awayScore;
        @AuraEnabled public String awayRecord;
        @AuraEnabled public Integer awayRank;
        @AuraEnabled public Boolean awayWinner;

        @AuraEnabled public String state;
        @AuraEnabled public String statusDetail;
        @AuraEnabled public String statusShortDetail;
        @AuraEnabled public String displayClock;
        @AuraEnabled public Integer period;
        @AuraEnabled public Boolean isCompleted;

        @AuraEnabled public String note;
        @AuraEnabled public String broadcast;
        @AuraEnabled public String spreadDetail;
        @AuraEnabled public Decimal overUnder;
        @AuraEnabled public String venue;
    }

    public static ScoreboardResult fetchScoreboard() {
        return fetchScoreboardForDate(null);
    }

    public static ScoreboardResult fetchScoreboardForDate(String dateStr) {
        String url = SCOREBOARD_URL + '?groups=50&limit=200';
        if (String.isNotBlank(dateStr)) {
            url += '&dates=' + dateStr;
        }

        String responseJson = callESPN(url);
        if (responseJson == null) {
            return emptyResult();
        }

        return parseScoreboard(responseJson);
    }

    public static ScoreboardResult fetchMultiDayScoreboard(List<String> dates) {
        ScoreboardResult combined = new ScoreboardResult();
        combined.games = new List<ScoreboardGame>();
        combined.liveGames = 0;
        combined.completedGames = 0;
        combined.scheduledGames = 0;
        combined.asOfTime = Datetime.now().format('h:mm a z');

        Set<String> seenIds = new Set<String>();

        for (String dateStr : dates) {
            ScoreboardResult dayResult = fetchScoreboardForDate(dateStr);
            if (dayResult?.games != null) {
                for (ScoreboardGame g : dayResult.games) {
                    if (!seenIds.contains(g.espnId)) {
                        seenIds.add(g.espnId);
                        combined.games.add(g);
                        if (g.state == 'in') combined.liveGames++;
                        else if (g.isCompleted) combined.completedGames++;
                        else combined.scheduledGames++;
                    }
                }
            }
        }

        combined.totalGames = combined.games.size();
        return combined;
    }

    private static ScoreboardResult parseScoreboard(String responseBody) {
        ScoreboardResult result = new ScoreboardResult();
        result.games = new List<ScoreboardGame>();
        result.liveGames = 0;
        result.completedGames = 0;
        result.scheduledGames = 0;
        result.asOfTime = Datetime.now().format('h:mm a z');

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> events = (List<Object>) parsed.get('events');
            if (events == null) return result;

            for (Object eventObj : events) {
                Map<String, Object> evt = (Map<String, Object>) eventObj;
                List<Object> comps = (List<Object>) evt.get('competitions');
                if (comps == null || comps.isEmpty()) continue;

                Map<String, Object> comp = (Map<String, Object>) comps[0];
                ScoreboardGame game = parseGame(evt, comp);
                if (game != null) {
                    result.games.add(game);
                    if (game.state == 'in') result.liveGames++;
                    else if (game.isCompleted) result.completedGames++;
                    else result.scheduledGames++;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Scoreboard parse error: ' + e.getMessage());
        }

        result.totalGames = result.games.size();
        return result;
    }

    private static ScoreboardGame parseGame(Map<String, Object> evt, Map<String, Object> comp) {
        ScoreboardGame game = new ScoreboardGame();
        game.espnId = (String) evt.get('id');
        game.shortName = (String) evt.get('shortName');
        game.gameDate = (String) evt.get('date');

        List<Object> competitors = (List<Object>) comp.get('competitors');
        if (competitors == null || competitors.size() < 2) return null;

        Map<String, Object> homeComp = null;
        Map<String, Object> awayComp = null;

        for (Object c : competitors) {
            Map<String, Object> competitor = (Map<String, Object>) c;
            String homeAway = (String) competitor.get('homeAway');
            if (homeAway == 'home') homeComp = competitor;
            else awayComp = competitor;
        }

        if (homeComp == null || awayComp == null) return null;

        populateTeam(game, homeComp, true);
        populateTeam(game, awayComp, false);

        Map<String, Object> statusObj = (Map<String, Object>) comp.get('status');
        if (statusObj != null) {
            game.displayClock = (String) statusObj.get('displayClock');
            Object periodObj = statusObj.get('period');
            game.period = periodObj != null ? ((Decimal) periodObj).intValue() : 0;

            Map<String, Object> statusType = (Map<String, Object>) statusObj.get('type');
            if (statusType != null) {
                game.state = (String) statusType.get('state');
                game.statusDetail = (String) statusType.get('detail');
                game.statusShortDetail = (String) statusType.get('shortDetail');
                game.isCompleted = (Boolean) statusType.get('completed');
            }
        }

        if (game.isCompleted == true) {
            Integer hScore = safeParseInt(game.homeScore);
            Integer aScore = safeParseInt(game.awayScore);
            game.homeWinner = hScore > aScore;
            game.awayWinner = aScore > hScore;
        } else {
            game.homeWinner = false;
            game.awayWinner = false;
        }

        List<Object> notes = (List<Object>) comp.get('notes');
        if (notes != null && !notes.isEmpty()) {
            Map<String, Object> firstNote = (Map<String, Object>) notes[0];
            game.note = (String) firstNote.get('headline');
        }

        List<Object> broadcasts = (List<Object>) comp.get('broadcasts');
        if (broadcasts != null && !broadcasts.isEmpty()) {
            Map<String, Object> bc = (Map<String, Object>) broadcasts[0];
            List<Object> names = (List<Object>) bc.get('names');
            if (names != null && !names.isEmpty()) {
                game.broadcast = (String) names[0];
            }
        }

        List<Object> oddsList = (List<Object>) comp.get('odds');
        if (oddsList != null && !oddsList.isEmpty()) {
            Map<String, Object> odds = (Map<String, Object>) oddsList[0];
            game.spreadDetail = (String) odds.get('details');
            Object ouObj = odds.get('overUnder');
            if (ouObj != null) {
                game.overUnder = (Decimal) ouObj;
            }
        }

        Map<String, Object> venueObj = (Map<String, Object>) comp.get('venue');
        if (venueObj != null) {
            game.venue = (String) venueObj.get('fullName');
        }

        return game;
    }

    private static void populateTeam(ScoreboardGame game, Map<String, Object> competitor, Boolean isHome) {
        Map<String, Object> team = (Map<String, Object>) competitor.get('team');
        if (team == null) return;

        String displayName = (String) team.get('shortDisplayName');
        String abbr = (String) team.get('abbreviation');
        String logo = (String) team.get('logo');
        String color = (String) team.get('color');
        String score = String.valueOf(competitor.get('score'));

        Map<String, Object> rankObj = (Map<String, Object>) competitor.get('curatedRank');
        Integer rank = 0;
        if (rankObj != null) {
            Object current = rankObj.get('current');
            if (current != null) rank = ((Decimal) current).intValue();
        }

        String overallRecord = '';
        List<Object> records = (List<Object>) competitor.get('records');
        if (records != null && !records.isEmpty()) {
            Map<String, Object> rec = (Map<String, Object>) records[0];
            overallRecord = (String) rec.get('summary');
        }

        if (isHome) {
            game.homeTeam = displayName;
            game.homeAbbr = abbr;
            game.homeLogo = logo;
            game.homeColor = color;
            game.homeScore = score;
            game.homeRank = rank;
            game.homeRecord = overallRecord;
        } else {
            game.awayTeam = displayName;
            game.awayAbbr = abbr;
            game.awayLogo = logo;
            game.awayColor = color;
            game.awayScore = score;
            game.awayRank = rank;
            game.awayRecord = overallRecord;
        }
    }

    private static Integer safeParseInt(String val) {
        if (String.isBlank(val)) return 0;
        try { return Integer.valueOf(val); } catch (Exception e) { return 0; }
    }

    private static ScoreboardResult emptyResult() {
        ScoreboardResult r = new ScoreboardResult();
        r.games = new List<ScoreboardGame>();
        r.totalGames = 0;
        r.liveGames = 0;
        r.completedGames = 0;
        r.scheduledGames = 0;
        r.asOfTime = Datetime.now().format('h:mm a z');
        return r;
    }

    public class ConferenceSchedule {
        @AuraEnabled public String conferenceName;
        @AuraEnabled public List<ScoreboardGame> games;
        @AuraEnabled public Integer totalGames;
        @AuraEnabled public Integer completedGames;
        @AuraEnabled public Integer liveGames;
        @AuraEnabled public Integer scheduledGames;
        @AuraEnabled public Boolean hasChampionshipGame;
        @AuraEnabled public String championshipStatus;
    }

    public class ConferenceTournamentResult {
        @AuraEnabled public List<ConferenceSchedule> conferences;
        @AuraEnabled public Integer totalConferences;
        @AuraEnabled public Integer totalGames;
        @AuraEnabled public String asOfTime;
    }

    public static ConferenceTournamentResult fetchConferenceTournamentWeek() {
        List<String> dates = new List<String>();
        Datetime now = Datetime.now();
        Datetime startDate = now.addDays(-3);
        for (Integer i = 0; i < 8; i++) {
            dates.add(startDate.addDays(i).format('yyyyMMdd'));
        }

        Map<String, List<ScoreboardGame>> confGamesMap = new Map<String, List<ScoreboardGame>>();
        Set<String> seenIds = new Set<String>();

        for (String dateStr : dates) {
            ScoreboardResult dayResult = fetchScoreboardForDate(dateStr);
            if (dayResult?.games == null) continue;

            for (ScoreboardGame g : dayResult.games) {
                if (seenIds.contains(g.espnId) || String.isBlank(g.note)) continue;
                seenIds.add(g.espnId);

                String confName = extractConferenceName(g.note);
                if (String.isBlank(confName)) continue;

                if (!confGamesMap.containsKey(confName)) {
                    confGamesMap.put(confName, new List<ScoreboardGame>());
                }
                confGamesMap.get(confName).add(g);
            }
        }

        ConferenceTournamentResult result = new ConferenceTournamentResult();
        result.conferences = new List<ConferenceSchedule>();
        result.totalGames = 0;
        result.asOfTime = Datetime.now().format('h:mm a z');

        List<String> sortedConfs = new List<String>(confGamesMap.keySet());
        sortedConfs.sort();

        for (String confName : sortedConfs) {
            List<ScoreboardGame> games = confGamesMap.get(confName);
            ConferenceSchedule sched = new ConferenceSchedule();
            sched.conferenceName = confName;
            sched.games = games;
            sched.totalGames = games.size();
            sched.completedGames = 0;
            sched.liveGames = 0;
            sched.scheduledGames = 0;
            sched.hasChampionshipGame = false;

            for (ScoreboardGame g : games) {
                if (g.isCompleted == true) sched.completedGames++;
                else if (g.state == 'in') sched.liveGames++;
                else sched.scheduledGames++;

                String roundLower = (g.note ?? '').toLowerCase();
                if (roundLower.contains('final') || roundLower.contains('championship')) {
                    sched.hasChampionshipGame = true;
                    if (g.isCompleted == true) sched.championshipStatus = 'Complete';
                    else if (g.state == 'in') sched.championshipStatus = 'Live';
                    else sched.championshipStatus = 'Upcoming';
                }
            }

            result.conferences.add(sched);
            result.totalGames += games.size();
        }

        result.totalConferences = result.conferences.size();
        return result;
    }

    private static String extractConferenceName(String note) {
        if (String.isBlank(note)) return null;
        Integer dash = note.indexOf(' - ');
        return dash > 0 ? note.substring(0, dash).trim() : note.trim();
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
            System.debug(LoggingLevel.ERROR, 'Scoreboard API HTTP ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Scoreboard callout failed: ' + e.getMessage());
        }
        return null;
    }
}
