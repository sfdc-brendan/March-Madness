public with sharing class AIPredictionEngine {

    public static final String MODEL_TYPE = 'AI Research';
    private static final String MODEL_VERSION = 'ai-v1.0';

    public static Prediction__c predictGame(Id gameId) {
        Game__c game = [
            SELECT Id, Round__c, Region__c, Game_Date__c, Venue__c,
                Spread__c, Over_Under__c, Team_1_Moneyline__c, Team_2_Moneyline__c,
                Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.Region__c,
                Team_1__r.Conference__c, Team_1__r.Record_Wins__c, Team_1__r.Record_Losses__c,
                Team_1__r.KenPom_Rating__c, Team_1__r.NET_Ranking__c,
                Team_1__r.Points_Per_Game__c, Team_1__r.Opp_Points_Per_Game__c,
                Team_1__r.Strength_of_Schedule__c, Team_1__r.Last_10_Record__c,
                Team_1__r.Overall_Power_Rating__c,
                Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.Region__c,
                Team_2__r.Conference__c, Team_2__r.Record_Wins__c, Team_2__r.Record_Losses__c,
                Team_2__r.KenPom_Rating__c, Team_2__r.NET_Ranking__c,
                Team_2__r.Points_Per_Game__c, Team_2__r.Opp_Points_Per_Game__c,
                Team_2__r.Strength_of_Schedule__c, Team_2__r.Last_10_Record__c,
                Team_2__r.Overall_Power_Rating__c
            FROM Game__c
            WHERE Id = :gameId
            LIMIT 1
        ];

        if (game.Team_1__c == null || game.Team_2__c == null) {
            throw new AIPredictionException('Both teams must be set before running AI predictions');
        }

        String researchContext = gatherResearchContext(game.Team_1__c, game.Team_2__c);
        String newsContext = gatherNewsContext(game.Team_1__c, game.Team_2__c);

        String prompt = buildPrompt(game, researchContext, newsContext);
        String schema = buildResponseSchema();

        GeminiAPIService.GeminiResponse response = GeminiAPIService.generateStructuredContent(prompt, schema);

        if (!response.success) {
            throw new AIPredictionException('Gemini API call failed: ' + response.errorMessage);
        }

        return parsePrediction(response.text, game);
    }

    public static void predictAndSave(Id gameId) {
        Prediction__c prediction = predictGame(gameId);

        List<Prediction__c> existing = [
            SELECT Id FROM Prediction__c
            WHERE Game__c = :gameId AND Is_Current__c = true AND Model_Type__c = :MODEL_TYPE
        ];
        for (Prediction__c p : existing) {
            p.Is_Current__c = false;
        }
        if (!existing.isEmpty()) {
            update existing;
        }

        insert prediction;
    }

    private static String gatherResearchContext(Id team1Id, Id team2Id) {
        List<Team_Research__c> research = [
            SELECT Team__c, Team__r.Name, Summary__c, Key_Factors__c,
                   Sentiment_Score__c, Confidence_Level__c
            FROM Team_Research__c
            WHERE Team__c IN (:team1Id, :team2Id) AND Is_Current__c = true
            ORDER BY Research_Date__c DESC
            LIMIT 4
        ];

        if (research.isEmpty()) return 'No team research available.';

        String ctx = '';
        for (Team_Research__c r : research) {
            ctx += '\n--- ' + r.Team__r.Name + ' Research ---\n';
            if (String.isNotBlank(r.Summary__c)) ctx += 'Summary: ' + r.Summary__c.left(500) + '\n';
            if (String.isNotBlank(r.Key_Factors__c)) ctx += 'Key Factors: ' + r.Key_Factors__c.left(500) + '\n';
            if (r.Sentiment_Score__c != null) ctx += 'Sentiment: ' + r.Sentiment_Score__c + '\n';
        }
        return ctx;
    }

    private static String gatherNewsContext(Id team1Id, Id team2Id) {
        List<News_Article__c> articles = [
            SELECT Team__r.Name, Name, Summary__c, Sentiment_Score__c, Article_Date__c
            FROM News_Article__c
            WHERE Team__c IN (:team1Id, :team2Id) AND Is_Verified__c = true
            ORDER BY Article_Date__c DESC
            LIMIT 6
        ];

        if (articles.isEmpty()) return 'No recent verified news.';

        String ctx = '';
        for (News_Article__c a : articles) {
            ctx += '\n[' + a.Team__r.Name + '] ' + a.Name;
            if (String.isNotBlank(a.Summary__c)) ctx += ' - ' + a.Summary__c.left(200);
            ctx += '\n';
        }
        return ctx;
    }

    private static String buildPrompt(Game__c game, String researchCtx, String newsCtx) {
        String t1 = game.Team_1__r.Name;
        String t2 = game.Team_2__r.Name;

        String prompt = 'You are an elite NCAA basketball analyst with deep expertise in March Madness predictions.\n'
            + 'Today\'s date is ' + Date.today().format() + '. Analyze this matchup using ALL available data.\n\n'
            + '=== MATCHUP ===\n'
            + t1 + ' (#' + formatSeed(game.Team_1__r.Seed__c) + ' seed, ' + game.Team_1__r.Conference__c + ')\n'
            + '  Record: ' + formatRecord(game.Team_1__r.Record_Wins__c, game.Team_1__r.Record_Losses__c) + '\n'
            + '  Last 10: ' + nullSafe(game.Team_1__r.Last_10_Record__c) + '\n'
            + '  KenPom: ' + nullSafe(game.Team_1__r.KenPom_Rating__c) + '\n'
            + '  NET: ' + nullSafe(game.Team_1__r.NET_Ranking__c) + '\n'
            + '  PPG: ' + nullSafe(game.Team_1__r.Points_Per_Game__c) + ' | Opp PPG: ' + nullSafe(game.Team_1__r.Opp_Points_Per_Game__c) + '\n'
            + '  SOS: ' + nullSafe(game.Team_1__r.Strength_of_Schedule__c) + '\n'
            + 'VS\n'
            + t2 + ' (#' + formatSeed(game.Team_2__r.Seed__c) + ' seed, ' + game.Team_2__r.Conference__c + ')\n'
            + '  Record: ' + formatRecord(game.Team_2__r.Record_Wins__c, game.Team_2__r.Record_Losses__c) + '\n'
            + '  Last 10: ' + nullSafe(game.Team_2__r.Last_10_Record__c) + '\n'
            + '  KenPom: ' + nullSafe(game.Team_2__r.KenPom_Rating__c) + '\n'
            + '  NET: ' + nullSafe(game.Team_2__r.NET_Ranking__c) + '\n'
            + '  PPG: ' + nullSafe(game.Team_2__r.Points_Per_Game__c) + ' | Opp PPG: ' + nullSafe(game.Team_2__r.Opp_Points_Per_Game__c) + '\n'
            + '  SOS: ' + nullSafe(game.Team_2__r.Strength_of_Schedule__c) + '\n\n'
            + 'Round: ' + nullSafe(game.Round__c) + '\n'
            + 'Region: ' + nullSafe(game.Region__c) + '\n';

        if (game.Venue__c != null) prompt += 'Venue: ' + game.Venue__c + '\n';

        if (game.Spread__c != null) {
            prompt += '\n=== BETTING LINES ===\n'
                + 'Spread: ' + game.Spread__c + '\n';
            if (game.Over_Under__c != null) prompt += 'Over/Under: ' + game.Over_Under__c + '\n';
            if (game.Team_1_Moneyline__c != null) prompt += t1 + ' Moneyline: ' + game.Team_1_Moneyline__c + '\n';
            if (game.Team_2_Moneyline__c != null) prompt += t2 + ' Moneyline: ' + game.Team_2_Moneyline__c + '\n';
        }

        prompt += '\n=== RESEARCH INTEL ===\n' + researchCtx;
        prompt += '\n\n=== RECENT NEWS ===\n' + newsCtx;

        prompt += '\n\n=== YOUR TASK ===\n'
            + 'Analyze this matchup comprehensively. Consider:\n'
            + '1. Statistical advantages (efficiency, defense, tempo)\n'
            + '2. Historical tournament performance and seed matchup history\n'
            + '3. Coaching experience in March Madness\n'
            + '4. Momentum and recent form\n'
            + '5. Matchup-specific advantages (style of play conflicts)\n'
            + '6. Intangibles: injuries, team chemistry, pressure handling\n\n'
            + 'Provide your expert prediction. The winner field must exactly match one of: "'
            + t1 + '" or "' + t2 + '"\n'
            + 'IMPORTANT: Return valid JSON matching the schema exactly.';

        return prompt;
    }

    private static String buildResponseSchema() {
        Map<String, Object> schema = new Map<String, Object>{
            'type' => 'object',
            'properties' => new Map<String, Object>{
                'winner' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Exact name of the predicted winning team'
                },
                'winProbability' => new Map<String, Object>{
                    'type' => 'number',
                    'description' => 'Win probability for the predicted winner (50-95)'
                },
                'predictedScore' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Predicted final score (e.g. 78-72)'
                },
                'analysis' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Detailed 4-6 sentence expert analysis covering the key factors driving the prediction'
                },
                'keyMatchup' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'The most important matchup factor that tips the scales'
                },
                'upsetPotential' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Low, Medium, or High - chance of an upset'
                },
                'confidenceLevel' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Lock, Strong, Lean, or Toss-up'
                }
            },
            'required' => new List<String>{
                'winner', 'winProbability', 'predictedScore', 'analysis',
                'keyMatchup', 'upsetPotential', 'confidenceLevel'
            }
        };
        return JSON.serialize(schema);
    }

    private static Prediction__c parsePrediction(String jsonText, Game__c game) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(jsonText);

        String winner = (String) result.get('winner');
        Decimal winProb = toDecimal(result.get('winProbability'));
        String score = (String) result.get('predictedScore');
        String analysis = (String) result.get('analysis');
        String keyMatchup = (String) result.get('keyMatchup');
        String upsetPotential = (String) result.get('upsetPotential');
        String confidenceLevel = (String) result.get('confidenceLevel');

        Id winnerId;
        if (winner != null && winner.equalsIgnoreCase(game.Team_1__r.Name)) {
            winnerId = game.Team_1__c;
        } else if (winner != null && winner.equalsIgnoreCase(game.Team_2__r.Name)) {
            winnerId = game.Team_2__c;
        } else if (winner != null && winner.containsIgnoreCase(game.Team_1__r.Name)) {
            winnerId = game.Team_1__c;
        } else {
            winnerId = game.Team_2__c;
        }

        Boolean team1Wins = winnerId == game.Team_1__c;
        Decimal t1Prob = team1Wins ? winProb : (100 - winProb);
        Decimal t2Prob = 100 - t1Prob;
        Decimal confidence = Math.abs(t1Prob - 50) * 2;

        String rationale = buildRationale(
            game.Team_1__r.Name, game.Team_2__r.Name,
            analysis, score, keyMatchup, upsetPotential, confidenceLevel,
            team1Wins ? game.Team_1__r.Name : game.Team_2__r.Name
        );

        Prediction__c pred = new Prediction__c();
        pred.Game__c = game.Id;
        pred.Predicted_Winner__c = winnerId;
        pred.Team_1_Win_Probability__c = t1Prob.setScale(1);
        pred.Team_2_Win_Probability__c = t2Prob.setScale(1);
        pred.Confidence_Score__c = confidence.setScale(1);
        pred.Prediction_Rationale__c = rationale;
        pred.Model_Version__c = MODEL_VERSION;
        pred.Model_Type__c = MODEL_TYPE;
        pred.Prediction_Date__c = DateTime.now();
        pred.Is_Current__c = true;
        return pred;
    }

    private static String buildRationale(String team1, String team2,
                                          String analysis, String score,
                                          String keyMatchup, String upsetPotential,
                                          String confidenceLevel, String winnerName) {
        String r = '<div class="ai-research-rationale">';
        r += '<h3>🤖 AI Expert Analysis</h3>';
        r += '<p><strong>Pick: ' + winnerName + '</strong>';
        if (String.isNotBlank(score)) r += ' | Predicted Score: ' + score;
        r += '</p>';
        r += '<div class="analysis-body">' + analysis + '</div>';
        r += '<div class="analysis-factors">';
        r += '<p><strong>Key Matchup:</strong> ' + keyMatchup + '</p>';
        r += '<p><strong>Upset Potential:</strong> ' + upsetPotential + '</p>';
        r += '<p><strong>Confidence:</strong> ' + confidenceLevel + '</p>';
        r += '</div>';
        r += '</div>';
        return r;
    }

    private static String formatSeed(Decimal seed) {
        return seed != null ? String.valueOf(Integer.valueOf(seed)) : '?';
    }

    private static String formatRecord(Decimal wins, Decimal losses) {
        if (wins == null || losses == null) return 'N/A';
        return Integer.valueOf(wins) + '-' + Integer.valueOf(losses);
    }

    private static String nullSafe(Object val) {
        return val != null ? String.valueOf(val) : 'N/A';
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return 50;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        if (val instanceof Double) return Decimal.valueOf((Double) val);
        try { return Decimal.valueOf(String.valueOf(val)); } catch (Exception e) { return 50; }
    }

    public class AIPredictionException extends Exception {}
}
