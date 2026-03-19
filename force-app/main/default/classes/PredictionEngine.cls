public with sharing class PredictionEngine {

    public static final Decimal WEIGHT_SEED = 0.15;
    public static final Decimal WEIGHT_RATING = 0.20;
    public static final Decimal WEIGHT_RECORD = 0.10;
    public static final Decimal WEIGHT_EFFICIENCY = 0.10;
    public static final Decimal WEIGHT_MOMENTUM = 0.08;
    public static final Decimal WEIGHT_INJURIES = 0.05;
    public static final Decimal WEIGHT_SENTIMENT = 0.05;
    public static final Decimal WEIGHT_HISTORICAL = 0.05;
    public static final Decimal WEIGHT_BETTING_LINES = 0.22;

    private static final String MODEL_VERSION = 'v1.0';
    public static final String MODEL_TYPE = 'Statistical';
    private static final Decimal MAX_SEED_DIFF = 15.0;
    private static final Decimal MAX_RATING_DIFF = 40.0;
    private static final Decimal MAX_NET_DIFF = 200.0;
    private static final Decimal MAX_PPG_DIFF = 30.0;

    public static Prediction__c predictGame(Id gameId) {
        Game__c game = [
            SELECT Id, Round__c, Region__c,
                Spread__c, Over_Under__c, Team_1_Moneyline__c, Team_2_Moneyline__c,
                Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.Region__c,
                Team_1__r.KenPom_Rating__c, Team_1__r.NET_Ranking__c,
                Team_1__r.Strength_of_Schedule__c, Team_1__r.Points_Per_Game__c,
                Team_1__r.Opp_Points_Per_Game__c, Team_1__r.Record_Wins__c,
                Team_1__r.Record_Losses__c, Team_1__r.Last_10_Record__c,
                Team_1__r.Overall_Power_Rating__c,
                Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.Region__c,
                Team_2__r.KenPom_Rating__c, Team_2__r.NET_Ranking__c,
                Team_2__r.Strength_of_Schedule__c, Team_2__r.Points_Per_Game__c,
                Team_2__r.Opp_Points_Per_Game__c, Team_2__r.Record_Wins__c,
                Team_2__r.Record_Losses__c, Team_2__r.Last_10_Record__c,
                Team_2__r.Overall_Power_Rating__c
            FROM Game__c
            WHERE Id = :gameId
            LIMIT 1
        ];

        Team__c team1 = game.Team_1__r;
        Team__c team2 = game.Team_2__r;

        Map<String, Decimal> factors = buildFactorMap(team1, team2, game);
        Decimal winProbability = calculateWinProbability(team1, team2, game);
        Team__c predictedWinner = winProbability >= 0.5 ? team1 : team2;
        Decimal confidence = (Math.abs(winProbability - 0.5) * 200).setScale(1);

        Prediction__c prediction = new Prediction__c();
        prediction.Game__c = gameId;
        prediction.Predicted_Winner__c = predictedWinner.Id;
        prediction.Team_1_Win_Probability__c = (winProbability * 100).setScale(1);
        prediction.Team_2_Win_Probability__c = ((1 - winProbability) * 100).setScale(1);
        prediction.Confidence_Score__c = confidence;
        prediction.Prediction_Rationale__c = generateRationale(team1, team2, factors, predictedWinner, confidence);
        prediction.Model_Version__c = MODEL_VERSION;
        prediction.Model_Type__c = MODEL_TYPE;
        prediction.Prediction_Date__c = DateTime.now();
        prediction.Is_Current__c = true;

        return prediction;
    }

    public static List<Prediction__c> predictAllGames(String round) {
        List<Game__c> games = [
            SELECT Id FROM Game__c
            WHERE Round__c = :round AND Status__c = 'Scheduled'
        ];

        List<Prediction__c> predictions = new List<Prediction__c>();
        for (Game__c game : games) {
            predictions.add(predictGame(game.Id));
        }
        return predictions;
    }

    public static void predictAndSave(Id gameId) {
        List<Prediction__c> existing = [
            SELECT Id FROM Prediction__c
            WHERE Game__c = :gameId AND Is_Current__c = true
              AND (Model_Type__c = :MODEL_TYPE OR Model_Type__c = null)
        ];

        for (Prediction__c p : existing) {
            p.Is_Current__c = false;
        }
        if (!existing.isEmpty()) {
            update existing;
        }

        Prediction__c prediction = predictGame(gameId);
        insert prediction;
    }

    public static Decimal calculateTeamStrength(Team__c team) {
        Decimal strength = 0;

        if (team.Seed__c != null) {
            strength += (17 - team.Seed__c) / 16.0 * 25;
        }
        if (team.KenPom_Rating__c != null) {
            strength += Math.min(25, Math.max(0, (team.KenPom_Rating__c + 10) / 50.0 * 25));
        }
        if (team.Record_Wins__c != null && team.Record_Losses__c != null) {
            Decimal totalGames = team.Record_Wins__c + team.Record_Losses__c;
            if (totalGames > 0) {
                strength += (team.Record_Wins__c / totalGames) * 25;
            }
        }
        if (team.Points_Per_Game__c != null && team.Opp_Points_Per_Game__c != null) {
            Decimal margin = team.Points_Per_Game__c - team.Opp_Points_Per_Game__c;
            strength += Math.min(25, Math.max(0, (margin + 15) / 30.0 * 25));
        }

        return Math.min(100, Math.max(0, strength)).setScale(1);
    }

    public static Decimal calculateWinProbability(Team__c team1, Team__c team2) {
        return calculateWinProbability(team1, team2, new Game__c());
    }

    public static Decimal calculateWinProbability(Team__c team1, Team__c team2, Game__c game) {
        Decimal seedFactor = calculateSeedFactor(team1, team2);
        Decimal ratingFactor = calculateRatingFactor(team1, team2);
        Decimal recordFactor = calculateRecordFactor(team1, team2);
        Decimal efficiencyFactor = calculateEfficiencyFactor(team1, team2);
        Decimal momentumFactor = calculateMomentumFactor(team1, team2);
        Decimal sentimentFactor = calculateSentimentFactor(team1, team2);
        Decimal historicalFactor = calculateHistoricalFactor(team1, team2);
        Decimal bettingFactor = calculateBettingLineFactor(game);

        Decimal bettingWeight = (bettingFactor != null) ? WEIGHT_BETTING_LINES : 0;
        Decimal redistributedWeight = 1.0 - bettingWeight;

        Decimal baseTotal = WEIGHT_SEED + WEIGHT_RATING + WEIGHT_RECORD +
            WEIGHT_EFFICIENCY + WEIGHT_MOMENTUM + WEIGHT_INJURIES +
            WEIGHT_SENTIMENT + WEIGHT_HISTORICAL;

        Decimal scale = redistributedWeight / baseTotal;

        Decimal weighted =
            (seedFactor * WEIGHT_SEED * scale) +
            (ratingFactor * WEIGHT_RATING * scale) +
            (recordFactor * WEIGHT_RECORD * scale) +
            (efficiencyFactor * WEIGHT_EFFICIENCY * scale) +
            (momentumFactor * WEIGHT_MOMENTUM * scale) +
            (sentimentFactor * (WEIGHT_INJURIES + WEIGHT_SENTIMENT) * scale) +
            (historicalFactor * WEIGHT_HISTORICAL * scale);

        if (bettingFactor != null) {
            weighted += bettingFactor * bettingWeight;
        }

        return Math.min(0.95, Math.max(0.05, weighted)).setScale(3);
    }

    @TestVisible
    private static Decimal calculateBettingLineFactor(Game__c game) {
        if (game.Spread__c != null) {
            Decimal spread = game.Spread__c;
            return clampFactor(0.5 - (spread / 40.0));
        }

        if (game.Team_1_Moneyline__c != null && game.Team_2_Moneyline__c != null) {
            Decimal impliedProb1 = moneylineToImpliedProbability(game.Team_1_Moneyline__c);
            Decimal impliedProb2 = moneylineToImpliedProbability(game.Team_2_Moneyline__c);
            Decimal total = impliedProb1 + impliedProb2;
            if (total > 0) {
                return clampFactor(impliedProb1 / total);
            }
        }

        return null;
    }

    private static Decimal moneylineToImpliedProbability(Decimal moneyline) {
        if (moneyline < 0) {
            return Math.abs(moneyline) / (Math.abs(moneyline) + 100);
        } else if (moneyline > 0) {
            return 100 / (moneyline + 100);
        }
        return 0.5;
    }

    private static Decimal calculateSeedFactor(Team__c team1, Team__c team2) {
        if (team1.Seed__c == null || team2.Seed__c == null) {
            return 0.5;
        }
        Decimal diff = team2.Seed__c - team1.Seed__c;
        return clampFactor(0.5 + (diff / (MAX_SEED_DIFF * 2)));
    }

    private static Decimal calculateRatingFactor(Team__c team1, Team__c team2) {
        Decimal factor = 0.5;
        Integer components = 0;

        if (team1.KenPom_Rating__c != null && team2.KenPom_Rating__c != null) {
            Decimal kenpomDiff = team1.KenPom_Rating__c - team2.KenPom_Rating__c;
            factor = 0.5 + (kenpomDiff / (MAX_RATING_DIFF * 2));
            components++;
        }

        if (team1.NET_Ranking__c != null && team2.NET_Ranking__c != null) {
            Decimal netDiff = team2.NET_Ranking__c - team1.NET_Ranking__c;
            Decimal netFactor = 0.5 + (netDiff / (MAX_NET_DIFF * 2));
            factor = (components > 0) ? (factor + netFactor) / 2 : netFactor;
        }

        return clampFactor(factor);
    }

    private static Decimal calculateRecordFactor(Team__c team1, Team__c team2) {
        Decimal winPct1 = getWinPercentage(team1);
        Decimal winPct2 = getWinPercentage(team2);

        if (winPct1 == null || winPct2 == null) {
            return 0.5;
        }

        Decimal sos1 = team1.Strength_of_Schedule__c != null ? team1.Strength_of_Schedule__c : 0.5;
        Decimal sos2 = team2.Strength_of_Schedule__c != null ? team2.Strength_of_Schedule__c : 0.5;

        Decimal adjusted1 = winPct1 * (0.7 + (sos1 * 0.3));
        Decimal adjusted2 = winPct2 * (0.7 + (sos2 * 0.3));

        Decimal diff = adjusted1 - adjusted2;
        return clampFactor(0.5 + diff);
    }

    private static Decimal calculateEfficiencyFactor(Team__c team1, Team__c team2) {
        if (team1.Points_Per_Game__c == null || team2.Points_Per_Game__c == null) {
            return 0.5;
        }

        Decimal offDiff = team1.Points_Per_Game__c - team2.Points_Per_Game__c;
        Decimal defDiff = (team2.Opp_Points_Per_Game__c != null ? team2.Opp_Points_Per_Game__c : 70)
                        - (team1.Opp_Points_Per_Game__c != null ? team1.Opp_Points_Per_Game__c : 70);

        Decimal combinedDiff = (offDiff + defDiff) / 2;
        return clampFactor(0.5 + (combinedDiff / MAX_PPG_DIFF));
    }

    private static Decimal calculateMomentumFactor(Team__c team1, Team__c team2) {
        Decimal wins1 = parseLast10Wins(team1.Last_10_Record__c);
        Decimal wins2 = parseLast10Wins(team2.Last_10_Record__c);

        if (wins1 == null || wins2 == null) {
            return 0.5;
        }

        Decimal diff = wins1 - wins2;
        return clampFactor(0.5 + (diff / 20.0));
    }

    private static Decimal calculateSentimentFactor(Team__c team1, Team__c team2) {
        Map<Id, Decimal> sentimentMap = getTeamSentiments(
            new Set<Id>{ team1.Id, team2.Id }
        );

        Decimal sent1 = sentimentMap.containsKey(team1.Id) ? sentimentMap.get(team1.Id) : 0.5;
        Decimal sent2 = sentimentMap.containsKey(team2.Id) ? sentimentMap.get(team2.Id) : 0.5;

        return clampFactor(0.5 + (sent1 - sent2));
    }

    private static Decimal calculateHistoricalFactor(Team__c team1, Team__c team2) {
        if (team1.Seed__c == null || team2.Seed__c == null) {
            return 0.5;
        }
        Integer seed1 = Integer.valueOf(team1.Seed__c);
        Integer seed2 = Integer.valueOf(team2.Seed__c);
        return HistoricalSeedData.getHistoricalWinRate(seed1, seed2);
    }

    public static String generateRationale(Team__c team1, Team__c team2,
            Map<String, Decimal> factors, Team__c predictedWinner, Decimal confidence) {

        String rationale = predictedWinner.Name + ' predicted to win';
        if (confidence >= 70) {
            rationale += ' convincingly';
        } else if (confidence >= 40) {
            rationale += ' comfortably';
        } else if (confidence >= 15) {
            rationale += ' in a competitive game';
        } else {
            rationale += ' in a toss-up';
        }
        rationale += ' (Confidence: ' + confidence + '%).\n\n';

        rationale += 'Key Factors:\n';
        String strongestFactor = '';
        Decimal strongestDeviation = 0;
        for (String factorName : factors.keySet()) {
            Decimal deviation = Math.abs(factors.get(factorName) - 0.5);
            if (deviation > strongestDeviation) {
                strongestDeviation = deviation;
                strongestFactor = factorName;
            }
        }
        if (String.isNotBlank(strongestFactor)) {
            rationale += '- Strongest signal: ' + strongestFactor + '\n';
        }

        if (team1.Seed__c != null && team2.Seed__c != null) {
            Integer seed1 = Integer.valueOf(team1.Seed__c);
            Integer seed2 = Integer.valueOf(team2.Seed__c);
            rationale += '- ' + HistoricalSeedData.getSeedMatchupInsight(seed1, seed2) + '\n';
        }

        rationale += '- ' + team1.Name + ' strength: ' + calculateTeamStrength(team1) + '/100\n';
        rationale += '- ' + team2.Name + ' strength: ' + calculateTeamStrength(team2) + '/100\n';

        if (factors.containsKey('Betting Lines')) {
            Decimal linesFactor = factors.get('Betting Lines');
            String linesFavor = linesFactor >= 0.5 ? team1.Name : team2.Name;
            rationale += '- Vegas favors: ' + linesFavor;
        }

        return rationale;
    }

    private static Map<String, Decimal> buildFactorMap(Team__c team1, Team__c team2, Game__c game) {
        Map<String, Decimal> factors = new Map<String, Decimal>{
            'Seed Advantage' => calculateSeedFactor(team1, team2),
            'Rating Edge' => calculateRatingFactor(team1, team2),
            'Record Quality' => calculateRecordFactor(team1, team2),
            'Efficiency' => calculateEfficiencyFactor(team1, team2),
            'Momentum' => calculateMomentumFactor(team1, team2),
            'Sentiment' => calculateSentimentFactor(team1, team2),
            'Historical Matchup' => calculateHistoricalFactor(team1, team2)
        };
        Decimal bettingFactor = calculateBettingLineFactor(game);
        if (bettingFactor != null) {
            factors.put('Betting Lines', bettingFactor);
        }
        return factors;
    }

    private static Decimal getWinPercentage(Team__c team) {
        if (team.Record_Wins__c == null || team.Record_Losses__c == null) {
            return null;
        }
        Decimal total = team.Record_Wins__c + team.Record_Losses__c;
        return total > 0 ? team.Record_Wins__c / total : null;
    }

    private static Decimal parseLast10Wins(String last10) {
        if (String.isBlank(last10)) {
            return null;
        }
        try {
            List<String> parts = last10.split('-');
            return Decimal.valueOf(parts[0].trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<Id, Decimal> getTeamSentiments(Set<Id> teamIds) {
        Map<Id, Decimal> sentimentMap = new Map<Id, Decimal>();
        List<Team_Research__c> research = [
            SELECT Team__c, Sentiment_Score__c
            FROM Team_Research__c
            WHERE Team__c IN :teamIds AND Is_Current__c = true
            ORDER BY Research_Date__c DESC
        ];
        for (Team_Research__c r : research) {
            if (!sentimentMap.containsKey(r.Team__c) && r.Sentiment_Score__c != null) {
                sentimentMap.put(r.Team__c, r.Sentiment_Score__c);
            }
        }
        return sentimentMap;
    }

    private static Decimal clampFactor(Decimal value) {
        return Math.min(0.95, Math.max(0.05, value));
    }
}
