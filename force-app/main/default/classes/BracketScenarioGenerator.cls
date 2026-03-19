public with sharing class BracketScenarioGenerator {

    private static final List<String> ROUND_ORDER = new List<String>{
        'Round of 64', 'Round of 32', 'Sweet 16', 'Elite 8', 'Final Four', 'Championship'
    };

    private static final List<List<Integer>> R64_SEED_PAIRS = new List<List<Integer>>{
        new List<Integer>{1, 16},
        new List<Integer>{8, 9},
        new List<Integer>{5, 12},
        new List<Integer>{4, 13},
        new List<Integer>{6, 11},
        new List<Integer>{3, 14},
        new List<Integer>{7, 10},
        new List<Integer>{2, 15}
    };

    private static final List<List<Integer>> NEXT_ROUND_PAIRINGS = new List<List<Integer>>{
        new List<Integer>{0, 1},
        new List<Integer>{2, 3},
        new List<Integer>{4, 5},
        new List<Integer>{6, 7}
    };

    private static final Set<String> BLUE_BLOODS = new Set<String>{
        'Duke', 'North Carolina', 'Kansas', 'Kentucky', 'UConn', 'UCLA',
        'Villanova', 'Indiana', 'Louisville', 'Michigan State', 'Gonzaga'
    };

    private static final List<String> REGIONS = new List<String>{ 'East', 'South', 'Midwest', 'West' };

    // Final Four pairings: index 0 vs index 1, index 2 vs index 3
    private static final List<List<Integer>> FF_PAIRINGS = new List<List<Integer>>{
        new List<Integer>{0, 2},
        new List<Integer>{1, 3}
    };

    // Pre-loaded data
    private Id tournamentId;
    private Map<Id, Team__c> teamsById;
    private Map<String, Map<Integer, Team__c>> teamsByRegionSeed;
    private Map<Id, Decimal> sentimentMap;
    private Map<String, Game__c> gamesByTeamPair;

    public BracketScenarioGenerator(Id tournamentId) {
        this.tournamentId = tournamentId;
        loadData();
    }

    private void loadData() {
        List<Team__c> allTeams = [
            SELECT Id, Name, Seed__c, Region__c, Conference__c,
                   KenPom_Rating__c, NET_Ranking__c, Points_Per_Game__c,
                   Opp_Points_Per_Game__c, Record_Wins__c, Record_Losses__c,
                   Strength_of_Schedule__c, Last_10_Record__c,
                   Overall_Power_Rating__c, Logo_URL__c, Primary_Color__c, Mascot__c
            FROM Team__c
            WHERE Tournament__c = :tournamentId
              AND Region__c != null AND Seed__c != null
            ORDER BY Region__c, Seed__c
        ];

        teamsById = new Map<Id, Team__c>();
        teamsByRegionSeed = new Map<String, Map<Integer, Team__c>>();
        for (Team__c t : allTeams) {
            teamsById.put(t.Id, t);
            if (!teamsByRegionSeed.containsKey(t.Region__c)) {
                teamsByRegionSeed.put(t.Region__c, new Map<Integer, Team__c>());
            }
            teamsByRegionSeed.get(t.Region__c).put(Integer.valueOf(t.Seed__c), t);
        }

        sentimentMap = new Map<Id, Decimal>();
        Set<Id> teamIds = teamsById.keySet();
        for (Team_Research__c r : [
            SELECT Team__c, Sentiment_Score__c
            FROM Team_Research__c
            WHERE Team__c IN :teamIds AND Is_Current__c = true
            ORDER BY Research_Date__c DESC
        ]) {
            if (!sentimentMap.containsKey(r.Team__c) && r.Sentiment_Score__c != null) {
                sentimentMap.put(r.Team__c, r.Sentiment_Score__c);
            }
        }

        gamesByTeamPair = new Map<String, Game__c>();
        for (Game__c g : [
            SELECT Id, Team_1__c, Team_2__c, Winner__c, Status__c,
                   Spread__c, Team_1_Moneyline__c, Team_2_Moneyline__c
            FROM Game__c
            WHERE Tournament__c = :tournamentId
              AND Team_1__c != null AND Team_2__c != null
        ]) {
            String key = g.Team_1__c + '_' + g.Team_2__c;
            String reverseKey = g.Team_2__c + '_' + g.Team_1__c;
            // Prefer Final games over Scheduled when both exist
            if (!gamesByTeamPair.containsKey(key) || g.Status__c == 'Final') {
                gamesByTeamPair.put(key, g);
                gamesByTeamPair.put(reverseKey, g);
            }
        }
    }

    @AuraEnabled
    public static String generateAllScenarios(Id tournamentId) {
        BracketScenarioGenerator gen = new BracketScenarioGenerator(tournamentId);

        List<String> strategies = new List<String>{
            'Chalk', 'Statistical Favorite', 'Mild Upsets', 'Upset Special',
            'Cinderella Story', 'Blue Blood', 'Defense Wins', 'Hot Streak',
            'Vegas Consensus', 'Historical Trends', 'Chaos Bracket', 'Balanced Blend'
        };

        // Delete existing scenarios for this tournament
        delete [SELECT Id FROM Bracket_Scenario__c WHERE Tournament__c = :tournamentId];

        List<Bracket_Scenario__c> scenarios = new List<Bracket_Scenario__c>();
        for (String strat : strategies) {
            scenarios.add(gen.generateScenario(strat));
        }
        // 3 random probability-weighted sims
        for (Integer i = 1; i <= 3; i++) {
            Bracket_Scenario__c sim = gen.generateScenario('Random Sim');
            sim.Scenario_Name__c = 'Random Simulation #' + i;
            sim.Strategy__c = 'Random Sim #' + i;
            scenarios.add(sim);
        }

        insert scenarios;
        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'count' => scenarios.size(),
            'message' => scenarios.size() + ' bracket scenarios generated'
        });
    }

    public Bracket_Scenario__c generateScenario(String strategy) {
        Map<String, List<Map<String, Object>>> rounds = new Map<String, List<Map<String, Object>>>();
        List<Map<String, Object>> upsetsList = new List<Map<String, Object>>();

        // Pick a cinderella team if using that strategy
        String cinderellaRegion = null;
        Integer cinderellaSeed = 0;
        if (strategy == 'Cinderella Story') {
            List<String> availableRegions = new List<String>(teamsByRegionSeed.keySet());
            cinderellaRegion = availableRegions[randomInt(availableRegions.size())];
            List<Integer> cinderellaSeeds = new List<Integer>{10, 11, 12, 13, 14};
            cinderellaSeed = cinderellaSeeds[randomInt(cinderellaSeeds.size())];
        }

        // Simulate region by region through Elite 8
        Map<String, Team__c> regionalWinners = new Map<String, Team__c>();
        Decimal totalConfidence = 0;
        Integer gameCount = 0;

        for (String region : teamsByRegionSeed.keySet()) {
            Map<Integer, Team__c> seedMap = teamsByRegionSeed.get(region);
            if (seedMap == null || seedMap.size() < 2) continue;

            // Round of 64
            List<Team__c> r64Winners = new List<Team__c>();
            List<Map<String, Object>> r64Games = new List<Map<String, Object>>();

            for (List<Integer> pair : R64_SEED_PAIRS) {
                Team__c t1 = seedMap.get(pair[0]);
                Team__c t2 = seedMap.get(pair[1]);
                if (t1 == null || t2 == null) continue;

                Map<String, Object> result = simulateGame(
                    t1, t2, strategy, 'Round of 64', region,
                    cinderellaRegion, cinderellaSeed
                );
                result.put('region', region);
                r64Games.add(result);
                r64Winners.add(teamsById.get((Id) result.get('winnerId')));
                totalConfidence += (Decimal) result.get('winProbability');
                gameCount++;

                if ((Boolean) result.get('isUpset')) {
                    upsetsList.add(buildUpsetEntry(result, 'Round of 64'));
                }
            }
            addRoundGames(rounds, 'Round of 64', r64Games);

            // Round of 32
            List<Team__c> r32Winners = simulateEliminationRound(
                r64Winners, NEXT_ROUND_PAIRINGS, 'Round of 32', region, strategy,
                rounds, upsetsList, cinderellaRegion, cinderellaSeed
            );
            totalConfidence += sumRoundConfidence(rounds.get('Round of 32'), region);
            gameCount += 4;

            // Sweet 16
            List<List<Integer>> s16Pairs = new List<List<Integer>>{
                new List<Integer>{0, 1}, new List<Integer>{2, 3}
            };
            List<Team__c> s16Winners = simulateEliminationRound(
                r32Winners, s16Pairs, 'Sweet 16', region, strategy,
                rounds, upsetsList, cinderellaRegion, cinderellaSeed
            );
            totalConfidence += sumRoundConfidence(rounds.get('Sweet 16'), region);
            gameCount += 2;

            // Elite 8
            List<List<Integer>> e8Pairs = new List<List<Integer>>{
                new List<Integer>{0, 1}
            };
            List<Team__c> e8Winners = simulateEliminationRound(
                s16Winners, e8Pairs, 'Elite 8', region, strategy,
                rounds, upsetsList, cinderellaRegion, cinderellaSeed
            );
            totalConfidence += sumRoundConfidence(rounds.get('Elite 8'), region);
            gameCount += 1;

            if (!e8Winners.isEmpty()) {
                regionalWinners.put(region, e8Winners[0]);
            }
        }

        // Final Four
        List<Team__c> ffTeams = new List<Team__c>();
        for (String region : REGIONS) {
            if (regionalWinners.containsKey(region)) {
                ffTeams.add(regionalWinners.get(region));
            }
        }

        Team__c champion = null;
        Team__c runnerUp = null;

        if (ffTeams.size() >= 4) {
            List<Map<String, Object>> ffGames = new List<Map<String, Object>>();
            List<Team__c> ffWinners = new List<Team__c>();

            for (List<Integer> pair : FF_PAIRINGS) {
                Team__c t1 = ffTeams[pair[0]];
                Team__c t2 = ffTeams[pair[1]];
                Map<String, Object> result = simulateGame(
                    t1, t2, strategy, 'Final Four', 'Final Four', null, 0
                );
                result.put('region', 'Final Four');
                ffGames.add(result);
                ffWinners.add(teamsById.get((Id) result.get('winnerId')));
                totalConfidence += (Decimal) result.get('winProbability');
                gameCount++;

                if ((Boolean) result.get('isUpset')) {
                    upsetsList.add(buildUpsetEntry(result, 'Final Four'));
                }
            }
            addRoundGames(rounds, 'Final Four', ffGames);

            // Championship
            if (ffWinners.size() >= 2) {
                Map<String, Object> champResult = simulateGame(
                    ffWinners[0], ffWinners[1], strategy, 'Championship', 'Championship', null, 0
                );
                champResult.put('region', 'Championship');
                addRoundGames(rounds, 'Championship', new List<Map<String, Object>>{ champResult });
                totalConfidence += (Decimal) champResult.get('winProbability');
                gameCount++;

                champion = teamsById.get((Id) champResult.get('winnerId'));
                runnerUp = teamsById.get((Id) champResult.get('loserId'));

                if ((Boolean) champResult.get('isUpset')) {
                    upsetsList.add(buildUpsetEntry(champResult, 'Championship'));
                }
            }
        } else if (ffTeams.size() >= 2) {
            Map<String, Object> champResult = simulateGame(
                ffTeams[0], ffTeams[1], strategy, 'Championship', 'Championship', null, 0
            );
            champResult.put('region', 'Championship');
            addRoundGames(rounds, 'Championship', new List<Map<String, Object>>{ champResult });
            champion = teamsById.get((Id) champResult.get('winnerId'));
            runnerUp = teamsById.get((Id) champResult.get('loserId'));
        }

        // Sort upsets by seed differential
        String biggestUpset = '';
        Integer biggestDiff = 0;
        for (Map<String, Object> u : upsetsList) {
            Integer diff = (Integer) u.get('seedDiff');
            if (diff > biggestDiff) {
                biggestDiff = diff;
                biggestUpset = '#' + u.get('winnerSeed') + ' ' + u.get('winnerName')
                    + ' over #' + u.get('loserSeed') + ' ' + u.get('loserName')
                    + ' (' + u.get('round') + ')';
            }
        }

        // Build Final Four summary
        String ffSummary = '';
        for (Team__c t : ffTeams) {
            if (ffSummary.length() > 0) ffSummary += ' | ';
            ffSummary += '#' + Integer.valueOf(t.Seed__c) + ' ' + t.Name + ' (' + t.Region__c + ')';
        }

        // Build JSON
        Map<String, Object> bracketJson = new Map<String, Object>();
        bracketJson.put('rounds', rounds);
        bracketJson.put('champion', champion != null ? teamToMap(champion) : null);
        bracketJson.put('runnerUp', runnerUp != null ? teamToMap(runnerUp) : null);
        bracketJson.put('finalFour', buildFinalFourList(ffTeams));
        bracketJson.put('upsets', upsetsList);
        bracketJson.put('stats', new Map<String, Object>{
            'totalUpsets' => upsetsList.size(),
            'totalGames' => gameCount,
            'averageConfidence' => gameCount > 0 ? (totalConfidence / gameCount).setScale(1) : 0
        });

        Bracket_Scenario__c scenario = new Bracket_Scenario__c();
        scenario.Tournament__c = tournamentId;
        scenario.Scenario_Name__c = getStrategyDisplayName(strategy);
        scenario.Description__c = getStrategyDescription(strategy);
        scenario.Strategy__c = strategy;
        scenario.Champion__c = champion?.Id;
        scenario.Runner_Up__c = runnerUp?.Id;
        scenario.Final_Four_Summary__c = ffSummary;
        scenario.Total_Upsets__c = upsetsList.size();
        scenario.Overall_Confidence__c = gameCount > 0
            ? (totalConfidence / gameCount).setScale(1) : 0;
        scenario.Biggest_Upset__c = biggestUpset;
        scenario.Generated_Date__c = DateTime.now();
        scenario.Bracket_JSON__c = JSON.serialize(bracketJson);

        return scenario;
    }

    // --- Simulation Core ---

    private Map<String, Object> simulateGame(
        Team__c t1, Team__c t2, String strategy, String round, String region,
        String cinderellaRegion, Integer cinderellaSeed
    ) {
        // Check for actual result first
        Game__c actual = gamesByTeamPair.get(t1.Id + '_' + t2.Id);
        if (actual != null && actual.Status__c == 'Final' && actual.Winner__c != null) {
            Team__c winner = teamsById.get(actual.Winner__c);
            Team__c loser = (actual.Winner__c == t1.Id) ? t2 : t1;
            Boolean isUpset = winner.Seed__c != null && loser.Seed__c != null
                && winner.Seed__c > loser.Seed__c;
            return buildGameResult(t1, t2, winner, loser, 95.0, isUpset);
        }

        Decimal winProb = calculateProbability(t1, t2, strategy, round, region,
            cinderellaRegion, cinderellaSeed);

        Team__c winner;
        Team__c loser;

        if (strategy == 'Random Sim' || strategy == 'Chaos Bracket') {
            winner = (Math.random() < winProb) ? t1 : t2;
        } else {
            winner = (winProb >= 0.5) ? t1 : t2;
        }
        loser = (winner.Id == t1.Id) ? t2 : t1;

        Decimal displayProb = (winner.Id == t1.Id) ? winProb * 100 : (1 - winProb) * 100;
        Boolean isUpset = winner.Seed__c != null && loser.Seed__c != null
            && winner.Seed__c > loser.Seed__c;

        return buildGameResult(t1, t2, winner, loser, displayProb.setScale(1), isUpset);
    }

    private Decimal calculateProbability(
        Team__c t1, Team__c t2, String strategy, String round, String region,
        String cinderellaRegion, Integer cinderellaSeed
    ) {
        Decimal baseSeed = seedFactor(t1, t2);
        Decimal baseRating = ratingFactor(t1, t2);
        Decimal baseRecord = recordFactor(t1, t2);
        Decimal baseEfficiency = efficiencyFactor(t1, t2);
        Decimal baseMomentum = momentumFactor(t1, t2);
        Decimal baseHistorical = historicalFactor(t1, t2);

        Decimal prob;

        if (strategy == 'Chalk') {
            // Pure seed-based
            prob = baseSeed * 0.8 + baseRating * 0.2;

        } else if (strategy == 'Statistical Favorite') {
            prob = baseSeed * 0.15 + baseRating * 0.25 + baseRecord * 0.15
                + baseEfficiency * 0.15 + baseMomentum * 0.10 + baseHistorical * 0.20;

        } else if (strategy == 'Mild Upsets') {
            prob = baseSeed * 0.15 + baseRating * 0.25 + baseRecord * 0.15
                + baseEfficiency * 0.15 + baseMomentum * 0.10 + baseHistorical * 0.20;
            // Nudge toward upsets in early rounds
            if ((round == 'Round of 64' || round == 'Round of 32') && prob > 0.55) {
                prob = prob - 0.12;
            }

        } else if (strategy == 'Upset Special') {
            prob = baseSeed * 0.05 + baseRating * 0.15 + baseRecord * 0.10
                + baseEfficiency * 0.10 + baseMomentum * 0.25 + baseHistorical * 0.10;
            // Strong upset bias in early rounds
            if (round == 'Round of 64' || round == 'Round of 32') {
                prob = prob - 0.20;
            } else if (round == 'Sweet 16') {
                prob = prob - 0.10;
            }

        } else if (strategy == 'Cinderella Story') {
            prob = baseSeed * 0.15 + baseRating * 0.25 + baseRecord * 0.15
                + baseEfficiency * 0.15 + baseMomentum * 0.10 + baseHistorical * 0.20;
            // Force cinderella team to win
            if (region == cinderellaRegion) {
                Boolean t1IsCinderella = t1.Seed__c != null
                    && Integer.valueOf(t1.Seed__c) == cinderellaSeed;
                Boolean t2IsCinderella = t2.Seed__c != null
                    && Integer.valueOf(t2.Seed__c) == cinderellaSeed;
                if (t1IsCinderella) prob = 0.75;
                else if (t2IsCinderella) prob = 0.25;
            }

        } else if (strategy == 'Blue Blood') {
            prob = baseSeed * 0.15 + baseRating * 0.20 + baseRecord * 0.10
                + baseEfficiency * 0.10 + baseMomentum * 0.05 + baseHistorical * 0.15;
            Decimal blueBloodBonus = blueBloodFactor(t1, t2);
            prob = prob * 0.75 + blueBloodBonus * 0.25;

        } else if (strategy == 'Defense Wins') {
            Decimal defenseFactor = defenseWinsFactor(t1, t2);
            prob = baseSeed * 0.10 + baseRating * 0.10 + defenseFactor * 0.45
                + baseRecord * 0.10 + baseHistorical * 0.10 + baseMomentum * 0.15;

        } else if (strategy == 'Hot Streak') {
            prob = baseSeed * 0.05 + baseRating * 0.10 + baseRecord * 0.10
                + baseEfficiency * 0.10 + baseMomentum * 0.50 + baseHistorical * 0.15;

        } else if (strategy == 'Vegas Consensus') {
            Decimal vegasFactor = vegasLineFactor(t1, t2);
            if (vegasFactor != null) {
                prob = baseSeed * 0.05 + baseRating * 0.10 + vegasFactor * 0.55
                    + baseRecord * 0.10 + baseHistorical * 0.10 + baseMomentum * 0.10;
            } else {
                prob = baseSeed * 0.15 + baseRating * 0.30 + baseRecord * 0.15
                    + baseEfficiency * 0.15 + baseMomentum * 0.10 + baseHistorical * 0.15;
            }

        } else if (strategy == 'Historical Trends') {
            prob = baseSeed * 0.10 + baseRating * 0.10 + baseHistorical * 0.55
                + baseRecord * 0.10 + baseEfficiency * 0.05 + baseMomentum * 0.10;

        } else if (strategy == 'Chaos Bracket') {
            prob = baseSeed * 0.10 + baseRating * 0.15 + baseRecord * 0.10
                + baseEfficiency * 0.10 + baseMomentum * 0.15 + baseHistorical * 0.10;
            // Add large random noise
            prob = prob + (Math.random() - 0.5) * 0.4;

        } else if (strategy == 'Balanced Blend') {
            Decimal weight = 1.0 / 6.0;
            prob = baseSeed * weight + baseRating * weight + baseRecord * weight
                + baseEfficiency * weight + baseMomentum * weight + baseHistorical * weight;

        } else {
            // Random Sim - full statistical with coin flip
            prob = baseSeed * 0.15 + baseRating * 0.25 + baseRecord * 0.15
                + baseEfficiency * 0.15 + baseMomentum * 0.10 + baseHistorical * 0.20;
        }

        return Math.min(0.95, Math.max(0.05, prob));
    }

    // --- Factor Calculators (no SOQL) ---

    private Decimal seedFactor(Team__c t1, Team__c t2) {
        if (t1.Seed__c == null || t2.Seed__c == null) return 0.5;
        Decimal diff = t2.Seed__c - t1.Seed__c;
        return clamp(0.5 + (diff / 30.0));
    }

    private Decimal ratingFactor(Team__c t1, Team__c t2) {
        Decimal factor = 0.5;
        Integer components = 0;

        if (t1.KenPom_Rating__c != null && t2.KenPom_Rating__c != null) {
            factor = 0.5 + (t1.KenPom_Rating__c - t2.KenPom_Rating__c) / 80.0;
            components++;
        }
        if (t1.NET_Ranking__c != null && t2.NET_Ranking__c != null) {
            Decimal netFactor = 0.5 + (t2.NET_Ranking__c - t1.NET_Ranking__c) / 400.0;
            factor = components > 0 ? (factor + netFactor) / 2 : netFactor;
            components++;
        }
        if (t1.Overall_Power_Rating__c != null && t2.Overall_Power_Rating__c != null) {
            Decimal pwrFactor = 0.5 + (t1.Overall_Power_Rating__c - t2.Overall_Power_Rating__c) / 200.0;
            factor = components > 0 ? (factor + pwrFactor) / 2 : pwrFactor;
        }
        return clamp(factor);
    }

    private Decimal recordFactor(Team__c t1, Team__c t2) {
        Decimal pct1 = winPct(t1);
        Decimal pct2 = winPct(t2);
        if (pct1 == null || pct2 == null) return 0.5;
        return clamp(0.5 + (pct1 - pct2));
    }

    private Decimal efficiencyFactor(Team__c t1, Team__c t2) {
        if (t1.Points_Per_Game__c == null || t2.Points_Per_Game__c == null) return 0.5;
        Decimal offDiff = t1.Points_Per_Game__c - t2.Points_Per_Game__c;
        Decimal defDiff = (t2.Opp_Points_Per_Game__c ?? 70) - (t1.Opp_Points_Per_Game__c ?? 70);
        return clamp(0.5 + ((offDiff + defDiff) / 2) / 30.0);
    }

    private Decimal momentumFactor(Team__c t1, Team__c t2) {
        Decimal w1 = parseLast10(t1.Last_10_Record__c);
        Decimal w2 = parseLast10(t2.Last_10_Record__c);
        if (w1 == null || w2 == null) return 0.5;
        return clamp(0.5 + (w1 - w2) / 20.0);
    }

    private Decimal historicalFactor(Team__c t1, Team__c t2) {
        if (t1.Seed__c == null || t2.Seed__c == null) return 0.5;
        return HistoricalSeedData.getHistoricalWinRate(
            Integer.valueOf(t1.Seed__c), Integer.valueOf(t2.Seed__c)
        );
    }

    private Decimal blueBloodFactor(Team__c t1, Team__c t2) {
        Boolean bb1 = isBlueBlood(t1.Name);
        Boolean bb2 = isBlueBlood(t2.Name);
        if (bb1 && !bb2) return 0.65;
        if (!bb1 && bb2) return 0.35;
        return 0.5;
    }

    private Decimal defenseWinsFactor(Team__c t1, Team__c t2) {
        Decimal oppPpg1 = t1.Opp_Points_Per_Game__c ?? 70;
        Decimal oppPpg2 = t2.Opp_Points_Per_Game__c ?? 70;
        // Lower opponent PPG = better defense
        Decimal diff = oppPpg2 - oppPpg1;
        return clamp(0.5 + diff / 30.0);
    }

    private Decimal vegasLineFactor(Team__c t1, Team__c t2) {
        Game__c game = gamesByTeamPair.get(t1.Id + '_' + t2.Id);
        if (game == null || game.Spread__c == null) return null;

        Decimal spread = game.Spread__c;
        if (game.Team_1__c == t1.Id) {
            return clamp(0.5 - (spread / 40.0));
        } else {
            return clamp(0.5 + (spread / 40.0));
        }
    }

    // --- Helpers ---

    private Boolean isBlueBlood(String teamName) {
        for (String bb : BLUE_BLOODS) {
            if (teamName.containsIgnoreCase(bb)) return true;
        }
        return false;
    }

    private Decimal winPct(Team__c t) {
        if (t.Record_Wins__c == null || t.Record_Losses__c == null) return null;
        Decimal total = t.Record_Wins__c + t.Record_Losses__c;
        return total > 0 ? t.Record_Wins__c / total : null;
    }

    private Decimal parseLast10(String last10) {
        if (String.isBlank(last10)) return null;
        try {
            return Decimal.valueOf(last10.split('-')[0].trim());
        } catch (Exception e) {
            return null;
        }
    }

    private Decimal clamp(Decimal val) {
        return Math.min(0.95, Math.max(0.05, val));
    }

    private Integer randomInt(Integer max) {
        return Integer.valueOf(Math.floor(Math.random() * max));
    }

    private List<Team__c> simulateEliminationRound(
        List<Team__c> prevWinners, List<List<Integer>> pairings,
        String round, String region, String strategy,
        Map<String, List<Map<String, Object>>> rounds,
        List<Map<String, Object>> upsetsList,
        String cinderellaRegion, Integer cinderellaSeed
    ) {
        List<Team__c> winners = new List<Team__c>();
        List<Map<String, Object>> roundGames = new List<Map<String, Object>>();

        for (List<Integer> pair : pairings) {
            if (pair[0] >= prevWinners.size() || pair[1] >= prevWinners.size()) continue;
            Team__c t1 = prevWinners[pair[0]];
            Team__c t2 = prevWinners[pair[1]];

            Map<String, Object> result = simulateGame(
                t1, t2, strategy, round, region, cinderellaRegion, cinderellaSeed
            );
            result.put('region', region);
            roundGames.add(result);
            winners.add(teamsById.get((Id) result.get('winnerId')));

            if ((Boolean) result.get('isUpset')) {
                upsetsList.add(buildUpsetEntry(result, round));
            }
        }

        addRoundGames(rounds, round, roundGames);
        return winners;
    }

    private void addRoundGames(
        Map<String, List<Map<String, Object>>> rounds,
        String round, List<Map<String, Object>> games
    ) {
        if (!rounds.containsKey(round)) {
            rounds.put(round, new List<Map<String, Object>>());
        }
        rounds.get(round).addAll(games);
    }

    private Decimal sumRoundConfidence(List<Map<String, Object>> roundGames, String region) {
        Decimal total = 0;
        if (roundGames == null) return 0;
        for (Map<String, Object> g : roundGames) {
            if (g.get('region') == region) {
                total += (Decimal) g.get('winProbability');
            }
        }
        return total;
    }

    private Map<String, Object> buildGameResult(
        Team__c t1, Team__c t2, Team__c winner, Team__c loser,
        Decimal winProbability, Boolean isUpset
    ) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('team1', teamToMap(t1));
        result.put('team2', teamToMap(t2));
        result.put('winner', teamToMap(winner));
        result.put('loser', teamToMap(loser));
        result.put('winnerId', winner.Id);
        result.put('loserId', loser.Id);
        result.put('winProbability', winProbability);
        result.put('isUpset', isUpset);
        if (isUpset) {
            result.put('seedDiff', Integer.valueOf(
                Math.abs((winner.Seed__c ?? 0) - (loser.Seed__c ?? 0))
            ));
        }
        return result;
    }

    private Map<String, Object> buildUpsetEntry(Map<String, Object> gameResult, String round) {
        Map<String, Object> winner = (Map<String, Object>) gameResult.get('winner');
        Map<String, Object> loser = (Map<String, Object>) gameResult.get('loser');
        return new Map<String, Object>{
            'round' => round,
            'winnerName' => winner.get('name'),
            'winnerSeed' => winner.get('seed'),
            'loserName' => loser.get('name'),
            'loserSeed' => loser.get('seed'),
            'seedDiff' => gameResult.get('seedDiff'),
            'confidence' => gameResult.get('winProbability')
        };
    }

    private Map<String, Object> teamToMap(Team__c t) {
        return new Map<String, Object>{
            'id' => t.Id,
            'name' => t.Name,
            'seed' => t.Seed__c,
            'region' => t.Region__c,
            'conference' => t.Conference__c,
            'logo' => t.Logo_URL__c,
            'color' => t.Primary_Color__c
        };
    }

    private List<Map<String, Object>> buildFinalFourList(List<Team__c> ffTeams) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Team__c t : ffTeams) {
            result.add(teamToMap(t));
        }
        return result;
    }

    private String getStrategyDisplayName(String strategy) {
        Map<String, String> names = new Map<String, String>{
            'Chalk' => 'Pure Chalk',
            'Statistical Favorite' => 'Statistical Favorite',
            'Mild Upsets' => 'Mild Upset Mix',
            'Upset Special' => 'Upset Special',
            'Cinderella Story' => 'Cinderella Story',
            'Blue Blood' => 'Blue Blood Dominance',
            'Defense Wins' => 'Defense Wins Championships',
            'Hot Streak' => 'Hot Streak',
            'Vegas Consensus' => 'Vegas Knows Best',
            'Historical Trends' => 'Historical Trends',
            'Chaos Bracket' => 'March Madness Chaos',
            'Balanced Blend' => 'Balanced Blend',
            'Random Sim' => 'Random Simulation'
        };
        return names.containsKey(strategy) ? names.get(strategy) : strategy;
    }

    private String getStrategyDescription(String strategy) {
        Map<String, String> descriptions = new Map<String, String>{
            'Chalk' => 'Higher seed wins every game. The safest, most predictable bracket.',
            'Statistical Favorite' => 'Full statistical model weighing KenPom, NET, efficiency, record, and momentum to pick the most likely winner.',
            'Mild Upsets' => 'Mostly favorites but with 4-6 early-round upsets matching historical upset frequency.',
            'Upset Special' => 'Aggressively favors underdogs with 8+ first-weekend upsets and deep runs by lower seeds.',
            'Cinderella Story' => 'Features a double-digit seed making a deep tournament run to the Elite 8 or beyond.',
            'Blue Blood' => 'Boosts historically elite programs like Duke, UNC, Kansas, and Kentucky.',
            'Defense Wins' => 'Heavily weights defensive efficiency - teams that limit opponent scoring advance.',
            'Hot Streak' => 'Emphasizes recent momentum and last-10-games performance over season-long stats.',
            'Vegas Consensus' => 'Betting lines and spreads drive predictions where available, with statistical fallback.',
            'Historical Trends' => 'Leans heavily on how often each seed historically advances in each round.',
            'Chaos Bracket' => 'Maximum randomness with probability-weighted coin flips. Expect the unexpected.',
            'Balanced Blend' => 'Equal weight across all factors: seeds, ratings, record, efficiency, momentum, history.',
            'Random Sim' => 'Probability-weighted random simulation. Each generation produces a unique bracket.'
        };
        return descriptions.containsKey(strategy) ? descriptions.get(strategy) : '';
    }
}
