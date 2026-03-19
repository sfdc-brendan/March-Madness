public with sharing class BettingLineService {

    private static final Integer BATCH_SIZE = 10;

    @InvocableMethod(label='Refresh Betting Lines' description='Fetch latest betting lines for scheduled games')
    public static List<String> refreshBettingLines(List<Id> tournamentIds) {
        List<String> results = new List<String>();
        for (Id tournamentId : tournamentIds) {
            Integer updated = refreshLinesForTournament(tournamentId);
            results.add('Updated ' + updated + ' games with betting lines');
        }
        return results;
    }

    public static Integer refreshLinesForTournament(Id tournamentId) {
        List<Game__c> scheduledGames = [
            SELECT Id, Round__c, Game_Date__c,
                   Team_1__c, Team_1__r.Name, Team_1__r.Seed__c,
                   Team_2__c, Team_2__r.Name, Team_2__r.Seed__c
            FROM Game__c
            WHERE Tournament__c = :tournamentId
              AND Status__c = 'Scheduled'
              AND Team_1__c != null AND Team_2__c != null
            ORDER BY Game_Date__c ASC
        ];

        if (scheduledGames.isEmpty()) {
            return 0;
        }

        Integer totalUpdated = 0;
        for (Integer i = 0; i < scheduledGames.size(); i += BATCH_SIZE) {
            Integer endIndex = Math.min(i + BATCH_SIZE, scheduledGames.size());
            List<Game__c> batch = new List<Game__c>();
            for (Integer j = i; j < endIndex; j++) {
                batch.add(scheduledGames[j]);
            }
            totalUpdated += processBatch(batch);
        }
        return totalUpdated;
    }

    private static Integer processBatch(List<Game__c> games) {
        String prompt = TeamResearchPromptBuilder.buildBettingLinesPrompt(games);
        GeminiAPIService.GeminiResponse response = GeminiAPIService.generateContent(prompt);

        if (!response.success || String.isBlank(response.text)) {
            return 0;
        }

        return applyBettingLines(games, response.text);
    }

    public static Integer applyBettingLines(List<Game__c> games, String jsonResponse) {
        try {
            String cleaned = GeminiResponseParser.cleanJsonResponse(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> linesList = (List<Object>) parsed.get('games');

            if (linesList == null || linesList.isEmpty()) {
                return 0;
            }

            Map<String, Game__c> gameByMatchup = new Map<String, Game__c>();
            for (Game__c g : games) {
                String key = normalizeTeamName(g.Team_1__r.Name) + ' vs ' + normalizeTeamName(g.Team_2__r.Name);
                gameByMatchup.put(key, g);
            }

            List<Game__c> toUpdate = new List<Game__c>();
            for (Object lineObj : linesList) {
                Map<String, Object> line = (Map<String, Object>) lineObj;
                String t1 = normalizeTeamName((String) line.get('team1Name'));
                String t2 = normalizeTeamName((String) line.get('team2Name'));
                String matchupKey = t1 + ' vs ' + t2;

                Game__c game = gameByMatchup.get(matchupKey);
                if (game == null) {
                    game = findClosestMatch(gameByMatchup, t1, t2);
                }

                if (game != null) {
                    game.Spread__c = toDecimal(line.get('spread'));
                    game.Over_Under__c = toDecimal(line.get('overUnder'));
                    game.Team_1_Moneyline__c = toDecimal(line.get('team1Moneyline'));
                    game.Team_2_Moneyline__c = toDecimal(line.get('team2Moneyline'));
                    game.Betting_Line_Source__c = (String) line.get('source');
                    game.Betting_Line_Updated__c = DateTime.now();
                    toUpdate.add(game);
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
            return toUpdate.size();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BettingLineService.applyBettingLines error: ' + e.getMessage());
            return 0;
        }
    }

    private static Game__c findClosestMatch(Map<String, Game__c> gameByMatchup, String t1, String t2) {
        for (String key : gameByMatchup.keySet()) {
            if (key.containsIgnoreCase(t1) || key.containsIgnoreCase(t2)) {
                return gameByMatchup.get(key);
            }
        }
        return null;
    }

    private static String normalizeTeamName(String name) {
        if (String.isBlank(name)) return '';
        return name.trim().toLowerCase();
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}
