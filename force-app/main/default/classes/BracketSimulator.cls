public with sharing class BracketSimulator {

    private static final Integer DEFAULT_ITERATIONS = 1000;
    private static final List<String> ROUND_ORDER = new List<String>{
        'Round of 64', 'Round of 32', 'Sweet 16', 'Elite 8', 'Final Four', 'Championship'
    };

    public static Map<Id, Map<String, Decimal>> simulateBracket(Id tournamentId) {
        return simulateBracket(tournamentId, DEFAULT_ITERATIONS);
    }

    public static Map<Id, Map<String, Decimal>> simulateBracket(Id tournamentId, Integer iterations) {
        List<Game__c> allGames = queryTournamentGames(tournamentId);

        Set<Id> allTeamIds = new Set<Id>();
        for (Game__c g : allGames) {
            if (g.Team_1__c != null) { allTeamIds.add(g.Team_1__c); }
            if (g.Team_2__c != null) { allTeamIds.add(g.Team_2__c); }
        }

        Map<Id, Map<String, Integer>> roundCounts = initializeRoundCounts(allTeamIds);
        Map<String, List<Game__c>> gamesByRound = groupGamesByRound(allGames);
        Map<Id, Team__c> teamCache = buildTeamCache(allGames);

        for (Integer i = 0; i < iterations; i++) {
            runSingleSimulation(gamesByRound, roundCounts, teamCache);
        }

        Map<Id, Map<String, Decimal>> results = new Map<Id, Map<String, Decimal>>();
        for (Id teamId : roundCounts.keySet()) {
            results.put(teamId, new Map<String, Decimal>());
            Map<String, Integer> counts = roundCounts.get(teamId);
            for (String round : counts.keySet()) {
                results.get(teamId).put(round, Decimal.valueOf(counts.get(round)) / iterations);
            }
        }
        return results;
    }

    public static List<Map<String, Object>> getProjectedFinalFour(Id tournamentId) {
        Map<Id, Map<String, Decimal>> simResults = simulateBracket(tournamentId);

        Map<Id, Decimal> finalFourProbs = new Map<Id, Decimal>();
        for (Id teamId : simResults.keySet()) {
            Map<String, Decimal> rounds = simResults.get(teamId);
            finalFourProbs.put(teamId, rounds.containsKey('Final Four') ? rounds.get('Final Four') : 0);
        }

        List<Id> sortedIds = sortByValueDescending(finalFourProbs);
        Set<Id> topIds = new Set<Id>();
        for (Integer i = 0; i < Math.min(4, sortedIds.size()); i++) {
            topIds.add(sortedIds[i]);
        }

        Map<Id, Team__c> teams = new Map<Id, Team__c>([
            SELECT Id, Name, Seed__c, Region__c FROM Team__c WHERE Id IN :topIds
        ]);

        List<Map<String, Object>> finalFourTeams = new List<Map<String, Object>>();
        for (Integer i = 0; i < Math.min(4, sortedIds.size()); i++) {
            Id teamId = sortedIds[i];
            Team__c team = teams.get(teamId);
            finalFourTeams.add(new Map<String, Object>{
                'teamId' => teamId,
                'teamName' => team?.Name,
                'seed' => team?.Seed__c,
                'region' => team?.Region__c,
                'probability' => finalFourProbs.get(teamId)
            });
        }
        return finalFourTeams;
    }

    public static Map<String, Object> getProjectedChampion(Id tournamentId) {
        Map<Id, Map<String, Decimal>> simResults = simulateBracket(tournamentId);

        Id bestTeamId;
        Decimal bestProb = 0;
        for (Id teamId : simResults.keySet()) {
            Map<String, Decimal> rounds = simResults.get(teamId);
            Decimal prob = rounds.containsKey('Championship') ? rounds.get('Championship') : 0;
            if (prob > bestProb) {
                bestProb = prob;
                bestTeamId = teamId;
            }
        }

        Map<String, Object> result = new Map<String, Object>();
        if (bestTeamId != null) {
            Team__c team = [SELECT Id, Name, Seed__c, Region__c FROM Team__c WHERE Id = :bestTeamId LIMIT 1];
            result.put('teamId', bestTeamId);
            result.put('teamName', team.Name);
            result.put('seed', team.Seed__c);
            result.put('region', team.Region__c);
            result.put('probability', bestProb);
            result.put('allRoundProbabilities', simResults.get(bestTeamId));
        }
        return result;
    }

    public static void runAndSavePredictions(Id tournamentId) {
        List<Game__c> scheduledGames = [
            SELECT Id FROM Game__c
            WHERE Status__c = 'Scheduled'
                AND Team_1__c != null AND Team_2__c != null
                AND Tournament__c = :tournamentId
        ];

        for (Game__c game : scheduledGames) {
            PredictionEngine.predictAndSave(game.Id);
        }
    }

    private static void runSingleSimulation(Map<String, List<Game__c>> gamesByRound,
            Map<Id, Map<String, Integer>> roundCounts, Map<Id, Team__c> teamCache) {

        Map<Id, Id> gameWinners = new Map<Id, Id>();

        for (String round : ROUND_ORDER) {
            List<Game__c> roundGames = gamesByRound.get(round);
            if (roundGames == null) { continue; }

            for (Game__c game : roundGames) {
                if (game.Status__c == 'Final' && game.Winner__c != null) {
                    gameWinners.put(game.Id, game.Winner__c);
                    incrementRoundCount(roundCounts, game.Winner__c, round);
                    continue;
                }

                Id team1Id = game.Team_1__c;
                Id team2Id = game.Team_2__c;
                if (team1Id == null || team2Id == null) { continue; }

                Team__c t1 = teamCache.get(team1Id);
                Team__c t2 = teamCache.get(team2Id);
                if (t1 == null || t2 == null) { continue; }

                Decimal winProb = PredictionEngine.calculateWinProbability(t1, t2);
                Id winnerId = (Math.random() < winProb) ? team1Id : team2Id;

                gameWinners.put(game.Id, winnerId);
                incrementRoundCount(roundCounts, winnerId, round);
            }
        }
    }

    private static List<Game__c> queryTournamentGames(Id tournamentId) {
        return [
            SELECT Id, Round__c, Region__c, Game_Number__c, Status__c, Winner__c,
                Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.KenPom_Rating__c,
                Team_1__r.NET_Ranking__c, Team_1__r.Strength_of_Schedule__c,
                Team_1__r.Points_Per_Game__c, Team_1__r.Opp_Points_Per_Game__c,
                Team_1__r.Record_Wins__c, Team_1__r.Record_Losses__c,
                Team_1__r.Last_10_Record__c, Team_1__r.Overall_Power_Rating__c,
                Team_1__r.Region__c,
                Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.KenPom_Rating__c,
                Team_2__r.NET_Ranking__c, Team_2__r.Strength_of_Schedule__c,
                Team_2__r.Points_Per_Game__c, Team_2__r.Opp_Points_Per_Game__c,
                Team_2__r.Record_Wins__c, Team_2__r.Record_Losses__c,
                Team_2__r.Last_10_Record__c, Team_2__r.Overall_Power_Rating__c,
                Team_2__r.Region__c,
                Next_Game__c, Bracket_Position__c
            FROM Game__c
            WHERE Tournament__c = :tournamentId
            ORDER BY Round__c, Game_Number__c
        ];
    }

    private static Map<Id, Map<String, Integer>> initializeRoundCounts(Set<Id> teamIds) {
        Map<Id, Map<String, Integer>> roundCounts = new Map<Id, Map<String, Integer>>();
        for (Id teamId : teamIds) {
            Map<String, Integer> counts = new Map<String, Integer>();
            for (String round : ROUND_ORDER) {
                counts.put(round, 0);
            }
            roundCounts.put(teamId, counts);
        }
        return roundCounts;
    }

    private static Map<String, List<Game__c>> groupGamesByRound(List<Game__c> games) {
        Map<String, List<Game__c>> gamesByRound = new Map<String, List<Game__c>>();
        for (Game__c g : games) {
            if (!gamesByRound.containsKey(g.Round__c)) {
                gamesByRound.put(g.Round__c, new List<Game__c>());
            }
            gamesByRound.get(g.Round__c).add(g);
        }
        return gamesByRound;
    }

    private static void incrementRoundCount(Map<Id, Map<String, Integer>> roundCounts, Id teamId, String round) {
        if (!roundCounts.containsKey(teamId)) { return; }
        Map<String, Integer> counts = roundCounts.get(teamId);
        counts.put(round, (counts.containsKey(round) ? counts.get(round) : 0) + 1);
    }

    private static Map<Id, Team__c> buildTeamCache(List<Game__c> games) {
        Map<Id, Team__c> cache = new Map<Id, Team__c>();
        for (Game__c g : games) {
            if (g.Team_1__c != null && g.Team_1__r != null) {
                cache.put(g.Team_1__c, g.Team_1__r);
            }
            if (g.Team_2__c != null && g.Team_2__r != null) {
                cache.put(g.Team_2__c, g.Team_2__r);
            }
        }
        return cache;
    }

    private static List<Id> sortByValueDescending(Map<Id, Decimal> valueMap) {
        List<SortableEntry> entries = new List<SortableEntry>();
        for (Id key : valueMap.keySet()) {
            entries.add(new SortableEntry(key, valueMap.get(key)));
        }
        entries.sort();

        List<Id> sorted = new List<Id>();
        for (SortableEntry entry : entries) {
            sorted.add(entry.recordId);
        }
        return sorted;
    }

    private class SortableEntry implements Comparable {
        public Id recordId;
        public Decimal value;

        public SortableEntry(Id recordId, Decimal value) {
            this.recordId = recordId;
            this.value = value;
        }

        public Integer compareTo(Object other) {
            SortableEntry otherEntry = (SortableEntry) other;
            if (this.value > otherEntry.value) { return -1; }
            if (this.value < otherEntry.value) { return 1; }
            return 0;
        }
    }
}
