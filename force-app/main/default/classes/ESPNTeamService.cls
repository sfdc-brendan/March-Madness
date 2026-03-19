public with sharing class ESPNTeamService {

    private static final String TEAMS_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams';
    private static final Integer HTTP_OK = 200;
    private static final Integer TIMEOUT_MS = 15000;

    public class TeamPerformance {
        @AuraEnabled public String teamName;
        @AuraEnabled public String teamLogo;
        @AuraEnabled public String conference;
        @AuraEnabled public String overallRecord;
        @AuraEnabled public String confRecord;
        @AuraEnabled public String homeRecord;
        @AuraEnabled public String awayRecord;
        @AuraEnabled public String standingSummary;
        @AuraEnabled public Integer espnRank;
        @AuraEnabled public List<GameResult> games;
        @AuraEnabled public Integer currentStreak;
        @AuraEnabled public String streakType;
    }

    public class GameResult {
        @AuraEnabled public String gameDate;
        @AuraEnabled public String opponent;
        @AuraEnabled public String opponentLogo;
        @AuraEnabled public Integer opponentRank;
        @AuraEnabled public Boolean isHome;
        @AuraEnabled public Integer teamScore;
        @AuraEnabled public Integer oppScore;
        @AuraEnabled public Boolean isWin;
        @AuraEnabled public Integer margin;
        @AuraEnabled public String note;
        @AuraEnabled public Boolean isConfTourney;
        @AuraEnabled public String status;
    }

    public static TeamPerformance fetchTeamPerformance(String teamName, Integer gameCount) {
        String espnId = findEspnTeamId(teamName);
        if (espnId == null) return null;

        String scheduleUrl = TEAMS_URL + '/' + espnId + '/schedule?season=' + Date.today().year();
        String scheduleBody = callESPN(scheduleUrl);
        if (scheduleBody == null) return null;

        TeamPerformance perf = parseSchedule(scheduleBody, espnId, gameCount);

        String detailBody = callESPN(TEAMS_URL + '/' + espnId);
        if (detailBody != null) {
            enrichRecords(perf, detailBody);
        }

        return perf;
    }

    private static void enrichRecords(TeamPerformance perf, String detailBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(detailBody);
        Map<String, Object> teamObj = (Map<String, Object>) parsed.get('team');
        if (teamObj == null) return;

        Map<String, Object> record = (Map<String, Object>) teamObj.get('record');
        if (record == null) return;

        List<Object> items = (List<Object>) record.get('items');
        if (items == null) return;

        for (Object item : items) {
            Map<String, Object> rec = (Map<String, Object>) item;
            String recType = (String) rec.get('type');
            String summary = (String) rec.get('summary');
            if (recType == 'total') perf.overallRecord = summary;
            else if (recType == 'home') perf.homeRecord = summary;
            else if (recType == 'road') perf.awayRecord = summary;

            List<Object> stats = (List<Object>) rec.get('stats');
            if (stats != null && recType == 'total') {
                for (Object sObj : stats) {
                    Map<String, Object> stat = (Map<String, Object>) sObj;
                    String statName = (String) stat.get('name');
                    if (statName == 'leagueWinPercent') {
                        Decimal confWinPct = (Decimal) stat.get('value');
                        if (confWinPct != null && confWinPct > 0) {
                            perf.confRecord = String.valueOf(Math.round(confWinPct * 100)) + '% Conf';
                        }
                    }
                }
            }
        }
    }


    @TestVisible
    private static String findEspnTeamId(String teamName) {
        String body = callESPN(TEAMS_URL + '?limit=500');
        if (body == null) return null;

        String searchToken = '"displayName":"' + teamName + '"';
        Integer nameIdx = body.indexOf(searchToken);
        if (nameIdx < 0) {
            searchToken = '"displayName":"' + teamName.trim() + '"';
            nameIdx = body.indexOf(searchToken);
        }
        if (nameIdx < 0) return null;

        String preceding = body.substring(Math.max(0, nameIdx - 200), nameIdx);
        Integer idIdx = preceding.lastIndexOf('"id":"');
        if (idIdx < 0) return null;

        String afterId = preceding.substring(idIdx + 6);
        Integer endQuote = afterId.indexOf('"');
        if (endQuote < 0) return null;

        return afterId.substring(0, endQuote);
    }

    private static TeamPerformance parseSchedule(String responseBody, String espnId, Integer gameCount) {
        TeamPerformance perf = new TeamPerformance();
        perf.games = new List<GameResult>();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

        Map<String, Object> teamObj = (Map<String, Object>) parsed.get('team');
        if (teamObj != null) {
            perf.teamName = (String) teamObj.get('displayName');
            perf.teamLogo = (String) teamObj.get('logo');
            perf.standingSummary = (String) teamObj.get('standingSummary');
            perf.overallRecord = (String) teamObj.get('recordSummary');
        }

        List<Object> events = (List<Object>) parsed.get('events');
        if (events == null) return perf;

        List<GameResult> allGames = new List<GameResult>();

        for (Object evtObj : events) {
            Map<String, Object> evt = (Map<String, Object>) evtObj;
            List<Object> comps = (List<Object>) evt.get('competitions');
            if (comps == null || comps.isEmpty()) continue;

            Map<String, Object> comp = (Map<String, Object>) comps[0];

            Map<String, Object> statusObj = (Map<String, Object>) comp.get('status');
            String state = '';
            if (statusObj != null) {
                Map<String, Object> statusType = (Map<String, Object>) statusObj.get('type');
                if (statusType != null) {
                    state = (String) statusType.get('state');
                }
            }

            List<Object> competitors = (List<Object>) comp.get('competitors');
            if (competitors == null || competitors.size() < 2) continue;

            Map<String, Object> teamComp = null;
            Map<String, Object> oppComp = null;

            for (Object cObj : competitors) {
                Map<String, Object> c = (Map<String, Object>) cObj;
                Map<String, Object> t = (Map<String, Object>) c.get('team');
                if (t != null && (String) t.get('id') == espnId) {
                    teamComp = c;
                    extractRecords(perf, c);
                    Map<String, Object> rankObj = (Map<String, Object>) c.get('curatedRank');
                    if (rankObj != null) {
                        Object cur = rankObj.get('current');
                        if (cur != null) perf.espnRank = ((Decimal) cur).intValue();
                    }
                } else {
                    oppComp = c;
                }
            }

            if (teamComp == null || oppComp == null) continue;

            GameResult g = new GameResult();
            g.gameDate = (String) evt.get('date');
            g.isHome = 'home' == (String) teamComp.get('homeAway');
            g.status = state;

            Map<String, Object> oppTeam = (Map<String, Object>) oppComp.get('team');
            if (oppTeam != null) {
                g.opponent = (String) oppTeam.get('shortDisplayName');
                g.opponentLogo = (String) oppTeam.get('logo');
            }

            Map<String, Object> oppRank = (Map<String, Object>) oppComp.get('curatedRank');
            if (oppRank != null) {
                Object cur = oppRank.get('current');
                if (cur != null) {
                    Integer rank = ((Decimal) cur).intValue();
                    g.opponentRank = rank <= 25 ? rank : null;
                }
            }

            Map<String, Object> teamScoreObj = (Map<String, Object>) teamComp.get('score');
            Map<String, Object> oppScoreObj = (Map<String, Object>) oppComp.get('score');
            if (teamScoreObj != null && oppScoreObj != null) {
                Object tsVal = teamScoreObj.get('value');
                Object osVal = oppScoreObj.get('value');
                if (tsVal != null) g.teamScore = ((Decimal) tsVal).intValue();
                if (osVal != null) g.oppScore = ((Decimal) osVal).intValue();
            }

            Boolean winner = (Boolean) teamComp.get('winner');
            g.isWin = winner == true;

            if (g.teamScore != null && g.oppScore != null) {
                g.margin = g.teamScore - g.oppScore;
            }

            List<Object> notes = (List<Object>) comp.get('notes');
            if (notes != null && !notes.isEmpty()) {
                Map<String, Object> note = (Map<String, Object>) notes[0];
                g.note = (String) note.get('headline');
                g.isConfTourney = g.note != null && (g.note.containsIgnoreCase('tournament') || g.note.containsIgnoreCase('championship'));
            } else {
                g.isConfTourney = false;
            }

            allGames.add(g);
        }

        Integer startIdx = Math.max(0, allGames.size() - gameCount);
        for (Integer i = startIdx; i < allGames.size(); i++) {
            perf.games.add(allGames[i]);
        }

        calculateStreak(perf);
        return perf;
    }

    private static void extractRecords(TeamPerformance perf, Map<String, Object> competitor) {
        List<Object> records = (List<Object>) competitor.get('records');
        if (records == null) return;

        for (Object rObj : records) {
            Map<String, Object> rec = (Map<String, Object>) rObj;
            String recType = (String) rec.get('type');
            String summary = (String) rec.get('summary');
            if (recType == 'total') perf.overallRecord = summary;
            else if (recType == 'vsconf') perf.confRecord = summary;
            else if (recType == 'home') perf.homeRecord = summary;
            else if (recType == 'road') perf.awayRecord = summary;
        }
    }

    private static void calculateStreak(TeamPerformance perf) {
        if (perf.games.isEmpty()) return;

        Integer streak = 0;
        String sType = '';

        for (Integer i = perf.games.size() - 1; i >= 0; i--) {
            GameResult g = perf.games[i];
            if (g.status != 'post') continue;

            if (streak == 0) {
                sType = g.isWin ? 'W' : 'L';
                streak = 1;
            } else if ((sType == 'W' && g.isWin) || (sType == 'L' && !g.isWin)) {
                streak++;
            } else {
                break;
            }
        }

        perf.currentStreak = streak;
        perf.streakType = sType;
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
            System.debug(LoggingLevel.ERROR, 'ESPNTeamService HTTP ' + res.getStatusCode() + ' for ' + url);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ESPNTeamService callout failed: ' + e.getMessage());
        }
        return null;
    }
}
