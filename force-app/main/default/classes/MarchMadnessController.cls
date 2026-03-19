public with sharing class MarchMadnessController {

    @AuraEnabled(cacheable=true)
    public static Tournament__c getActiveTournament() {
        List<Tournament__c> tournaments = [
            SELECT Id, Name, Year__c, Status__c, Start_Date__c, End_Date__c
            FROM Tournament__c
            WHERE Status__c IN ('Active', 'Upcoming')
            WITH USER_MODE
            ORDER BY Status__c ASC, Year__c DESC
            LIMIT 1
        ];
        return tournaments.isEmpty() ? null : tournaments[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Team__c> getTopTeams(Id tournamentId, Integer limitCount) {
        Integer queryLimit = (limitCount != null && limitCount > 0) ? limitCount : 10;
        return [
            SELECT Id, Name, Seed__c, Region__c, Conference__c,
                   Record_Wins__c, Record_Losses__c, Logo_URL__c, Primary_Color__c,
                   Overall_Power_Rating__c, KenPom_Rating__c, NET_Ranking__c,
                   Tournament_Likelihood__c, Conference_Tournament_Status__c
            FROM Team__c
            WHERE Tournament__c = :tournamentId
            WITH USER_MODE
            ORDER BY Seed__c ASC NULLS LAST, Overall_Power_Rating__c DESC NULLS LAST
            LIMIT :queryLimit
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Game__c> getGamesByRound(String round) {
        return [
            SELECT Id, Name, Round__c, Game_Date__c, Bracket_Position__c,
                   Region__c, Status__c, Team_1_Score__c, Team_2_Score__c,
                   Spread__c, Over_Under__c, Team_1_Moneyline__c, Team_2_Moneyline__c,
                   Betting_Line_Source__c, Betting_Line_Updated__c,
                   Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.Logo_URL__c,
                   Team_1__r.Primary_Color__c,
                   Team_1__r.Record_Wins__c, Team_1__r.Record_Losses__c, Team_1__r.Region__c,
                   Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.Logo_URL__c,
                   Team_2__r.Primary_Color__c,
                   Team_2__r.Record_Wins__c, Team_2__r.Record_Losses__c, Team_2__r.Region__c,
                   Winner__c, Winner__r.Name
            FROM Game__c
            WHERE Round__c = :round
            WITH USER_MODE
            ORDER BY Region__c, Bracket_Position__c
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Game__c> getAllGames(Id tournamentId) {
        return [
            SELECT Id, Name, Round__c, Game_Date__c, Bracket_Position__c,
                   Region__c, Status__c, Team_1_Score__c, Team_2_Score__c,
                   Spread__c, Over_Under__c, Team_1_Moneyline__c, Team_2_Moneyline__c,
                   Betting_Line_Source__c, Betting_Line_Updated__c,
                   Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.Logo_URL__c,
                   Team_1__r.Primary_Color__c,
                   Team_1__r.Record_Wins__c, Team_1__r.Record_Losses__c,
                   Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.Logo_URL__c,
                   Team_2__r.Primary_Color__c,
                   Team_2__r.Record_Wins__c, Team_2__r.Record_Losses__c,
                   Winner__c, Winner__r.Name, Tournament__c
            FROM Game__c
            WHERE Tournament__c = :tournamentId
            WITH USER_MODE
            ORDER BY Round__c, Bracket_Position__c
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Prediction__c> getCurrentPredictions(Id tournamentId) {
        return [
            SELECT Id, Game__c, Predicted_Winner__c, Predicted_Winner__r.Name,
                   Confidence_Score__c, Team_1_Win_Probability__c, Team_2_Win_Probability__c,
                   Prediction_Rationale__c, Model_Version__c,
                   Model_Type__c, Prediction_Date__c, Game__r.Winner__c
            FROM Prediction__c
            WHERE Game__r.Tournament__c = :tournamentId AND Is_Current__c = true
            WITH USER_MODE
            ORDER BY Game__r.Round__c, Confidence_Score__c DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Team__c getTeamDetail(Id teamId) {
        List<Team__c> teams = [
            SELECT Id, Name, Seed__c, Region__c, Conference__c,
                   Record_Wins__c, Record_Losses__c,
                   Logo_URL__c, Overall_Power_Rating__c, KenPom_Rating__c,
                   NET_Ranking__c, Points_Per_Game__c, Opp_Points_Per_Game__c,
                   Strength_of_Schedule__c, Last_10_Record__c,
                   Tournament_Likelihood__c, Conference_Tournament_Status__c,
                   (SELECT Id, Name, Summary__c, Key_Factors__c, Sentiment_Score__c,
                           Research_Date__c, Source_Type__c, Confidence_Level__c, Is_Current__c
                    FROM Research_Records__r
                    ORDER BY Research_Date__c DESC
                    LIMIT 5),
                   (SELECT Id, Name, Factor_Name__c, Factor_Value__c, Weight__c, Category__c
                    FROM Statistical_Factors__r
                    ORDER BY Category__c, Factor_Name__c)
            FROM Team__c
            WHERE Id = :teamId
            WITH USER_MODE
            LIMIT 1
        ];
        return teams.isEmpty() ? null : teams[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<News_Article__c> getLatestNews(Integer limitCount) {
        Integer queryLimit = (limitCount != null && limitCount > 0) ? limitCount : 20;
        return [
            SELECT Id, Name, Summary__c, Article_Date__c,
                   Sentiment_Score__c, Category__c, Relevance_Score__c,
                   Source__c, Source_URL__c, Is_Featured__c, Tags__c,
                   Is_Verified__c, Source_Type__c, Grounding_Sources__c, Image_URL__c,
                   Team__c, Team__r.Name, Team__r.Logo_URL__c, Team__r.Seed__c
            FROM News_Article__c
            WITH USER_MODE
            ORDER BY Is_Verified__c DESC, Article_Date__c DESC
            LIMIT :queryLimit
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<News_Article__c> getNewsForTeam(Id teamId) {
        return [
            SELECT Id, Name, Summary__c, Article_Date__c,
                   Sentiment_Score__c, Category__c, Relevance_Score__c,
                   Source__c, Source_URL__c, Is_Featured__c, Tags__c,
                   Is_Verified__c, Source_Type__c, Grounding_Sources__c, Image_URL__c,
                   Team__c, Team__r.Name, Team__r.Logo_URL__c, Team__r.Seed__c
            FROM News_Article__c
            WHERE Team__c = :teamId
            WITH USER_MODE
            ORDER BY Is_Verified__c DESC, Article_Date__c DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Prediction__c> getPredictionsForRound(String round) {
        return [
            SELECT Id, Name, Predicted_Winner__c, Predicted_Winner__r.Name,
                   Predicted_Winner__r.Seed__c, Confidence_Score__c, Prediction_Rationale__c,
                   Prediction_Date__c, Is_Current__c,
                   Game__c, Game__r.Name, Game__r.Round__c, Game__r.Game_Date__c,
                   Game__r.Status__c, Game__r.Region__c,
                   Game__r.Team_1__c, Game__r.Team_1__r.Name, Game__r.Team_1__r.Seed__c,
                   Game__r.Team_2__c, Game__r.Team_2__r.Name, Game__r.Team_2__r.Seed__c,
                   Game__r.Winner__c, Game__r.Winner__r.Name
            FROM Prediction__c
            WHERE Game__r.Round__c = :round AND Is_Current__c = true
            WITH USER_MODE
            ORDER BY Game__r.Game_Date__c, Confidence_Score__c DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardStats(Id tournamentId) {
        Map<String, Object> stats = new Map<String, Object>();

        AggregateResult[] predCounts = [
            SELECT COUNT(Id) total,
                   AVG(Confidence_Score__c) avgConfidence
            FROM Prediction__c
            WHERE Game__r.Tournament__c = :tournamentId AND Is_Current__c = true
            WITH USER_MODE
        ];

        Integer totalPredictions = 0;
        Decimal avgConfidence = 0;
        if (!predCounts.isEmpty()) {
            totalPredictions = (Integer) predCounts[0].get('total');
            avgConfidence = (Decimal) predCounts[0].get('avgConfidence');
        }
        stats.put('totalPredictions', totalPredictions);
        stats.put('avgConfidence', avgConfidence != null ? avgConfidence.setScale(1) : 0);

        List<Prediction__c> predsWithResult = [
            SELECT Id, Game__r.Winner__c, Predicted_Winner__c
            FROM Prediction__c
            WHERE Game__r.Tournament__c = :tournamentId
              AND Is_Current__c = true AND Game__r.Status__c = 'Final'
            WITH USER_MODE
        ];
        Integer correctCount = 0;
        for (Prediction__c p : predsWithResult) {
            if (p.Game__r != null && p.Game__r.Winner__c != null && p.Predicted_Winner__c != null
                    && p.Game__r.Winner__c == p.Predicted_Winner__c) {
                correctCount++;
            }
        }

        Integer completedGames = [
            SELECT COUNT()
            FROM Prediction__c
            WHERE Game__r.Tournament__c = :tournamentId
              AND Is_Current__c = true AND Game__r.Status__c = 'Final'
            WITH USER_MODE
        ];

        Decimal accuracy = (completedGames > 0)
            ? ((Decimal) correctCount / completedGames * 100).setScale(1)
            : 0;
        stats.put('predictionAccuracy', accuracy);
        stats.put('correctPredictions', correctCount);
        stats.put('completedGames', completedGames);

        Integer upcomingGames = [
            SELECT COUNT()
            FROM Game__c
            WHERE Tournament__c = :tournamentId
              AND Status__c = 'Scheduled'
            WITH USER_MODE
        ];
        stats.put('upcomingGames', upcomingGames);

        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<Team__c> getTeamsByTournament(Id tournamentId) {
        return [
            SELECT Id, Name, Seed__c, Region__c, Conference__c,
                   Record_Wins__c, Record_Losses__c,
                   Logo_URL__c, Overall_Power_Rating__c, KenPom_Rating__c,
                   NET_Ranking__c, Points_Per_Game__c, Opp_Points_Per_Game__c
            FROM Team__c
            WHERE Tournament__c = :tournamentId
            WITH USER_MODE
            ORDER BY Seed__c, Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Tournament__c> getConferenceTournaments(Id parentTournamentId) {
        return [
            SELECT Id, Name, Conference_Name__c, Status__c, Champion__c,
                   Logo_URL__c, ESPN_Conference_Id__c, Venue__c
            FROM Tournament__c
            WHERE Parent_Tournament__c = :parentTournamentId
              AND Type__c = 'Conference'
            WITH USER_MODE
            ORDER BY Conference_Name__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Game__c> getConferenceGames(Id conferenceTournamentId) {
        return [
            SELECT Id, Name, Round__c, Game_Date__c, Status__c, Region__c,
                   Team_1_Score__c, Team_2_Score__c, Bracket_Position__c,
                   Team_1__c, Team_1__r.Name, Team_1__r.Seed__c,
                   Team_1__r.Logo_URL__c, Team_1__r.Primary_Color__c,
                   Team_2__c, Team_2__r.Name, Team_2__r.Seed__c,
                   Team_2__r.Logo_URL__c, Team_2__r.Primary_Color__c,
                   Winner__c, Winner__r.Name
            FROM Game__c
            WHERE Tournament__c = :conferenceTournamentId
            WITH USER_MODE
            ORDER BY Game_Date__c DESC, Bracket_Position__c ASC
        ];
    }

    @AuraEnabled
    public static String refreshConferenceScores(Id parentTournamentId) {
        try {
            ConferenceTournamentService.refreshScores(parentTournamentId);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Conference scores refreshed'
            });
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Team__c> searchTeams(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Team__c>();
        }
        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, Seed__c, Region__c, Conference__c,
                   Record_Wins__c, Record_Losses__c, Logo_URL__c
            FROM Team__c
            WHERE Name LIKE :searchPattern
            WITH USER_MODE
            ORDER BY Name
            LIMIT 20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Game__c> getTodayGames(Id tournamentId) {
        return [
            SELECT Id, Name, Round__c, Game_Date__c, Status__c,
                   Team_1_Score__c, Team_2_Score__c,
                   Team_1__c, Team_1__r.Name, Team_1__r.Seed__c,
                   Team_1__r.Logo_URL__c, Team_1__r.Primary_Color__c,
                   Team_1__r.Record_Wins__c, Team_1__r.Record_Losses__c,
                   Team_2__c, Team_2__r.Name, Team_2__r.Seed__c,
                   Team_2__r.Logo_URL__c, Team_2__r.Primary_Color__c,
                   Team_2__r.Record_Wins__c, Team_2__r.Record_Losses__c,
                   Winner__c, Winner__r.Name,
                   Tournament__c, Tournament__r.Conference_Name__c,
                   Tournament__r.Logo_URL__c, Tournament__r.Type__c
            FROM Game__c
            WHERE Game_Date__c = TODAY
              AND (Tournament__r.Parent_Tournament__c = :tournamentId
                   OR Tournament__c = :tournamentId)
            WITH USER_MODE
            ORDER BY Status__c ASC, Tournament__r.Conference_Name__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCommandCenterStats(Id tournamentId) {
        Map<String, Object> stats = new Map<String, Object>();

        Integer totalTeams = [SELECT COUNT() FROM Team__c WHERE Tournament__c = :tournamentId WITH USER_MODE];
        stats.put('totalTeams', totalTeams);

        Integer totalGames = [
            SELECT COUNT() FROM Game__c
            WHERE Tournament__c = :tournamentId
               OR Tournament__r.Parent_Tournament__c = :tournamentId
            WITH USER_MODE
        ];
        stats.put('totalGames', totalGames);

        Integer todayGames = [
            SELECT COUNT() FROM Game__c
            WHERE Game_Date__c = TODAY
              AND (Tournament__c = :tournamentId
                   OR Tournament__r.Parent_Tournament__c = :tournamentId)
            WITH USER_MODE
        ];
        stats.put('todayGames', todayGames);

        Integer liveGames = [
            SELECT COUNT() FROM Game__c
            WHERE Status__c = 'In Progress'
              AND (Tournament__c = :tournamentId
                   OR Tournament__r.Parent_Tournament__c = :tournamentId)
            WITH USER_MODE
        ];
        stats.put('liveGames', liveGames);

        Integer completedGames = [
            SELECT COUNT() FROM Game__c
            WHERE Status__c = 'Final'
              AND (Tournament__c = :tournamentId
                   OR Tournament__r.Parent_Tournament__c = :tournamentId)
            WITH USER_MODE
        ];
        stats.put('completedGames', completedGames);

        Integer confTournaments = [
            SELECT COUNT() FROM Tournament__c
            WHERE Parent_Tournament__c = :tournamentId AND Type__c = 'Conference'
            WITH USER_MODE
        ];
        stats.put('conferences', confTournaments);

        Integer newsCount = [SELECT COUNT() FROM News_Article__c WITH USER_MODE];
        stats.put('newsArticles', newsCount);

        Integer verifiedNews = [SELECT COUNT() FROM News_Article__c WHERE Is_Verified__c = true WITH USER_MODE];
        stats.put('verifiedNews', verifiedNews);

        return stats;
    }

    @AuraEnabled
    public static String runPrediction(Id gameId) {
        return runPredictionForModel(gameId, 'Statistical');
    }

    @AuraEnabled
    public static String runPredictionForModel(Id gameId, String modelType) {
        try {
            if (modelType == 'Mascot Battle') {
                MascotPredictionEngine.predictAndSave(gameId);
            } else if (modelType == 'AI Research') {
                AIPredictionEngine.predictAndSave(gameId);
            } else {
                PredictionEngine.predictAndSave(gameId);
            }

            Prediction__c pred = [
                SELECT Id, Predicted_Winner__c, Predicted_Winner__r.Name,
                       Confidence_Score__c, Prediction_Rationale__c, Model_Type__c
                FROM Prediction__c
                WHERE Game__c = :gameId AND Is_Current__c = true
                  AND Model_Type__c = :modelType
                WITH USER_MODE
                ORDER BY Prediction_Date__c DESC
                LIMIT 1
            ];
            return JSON.serialize(new Map<String, Object>{
                'predictionId' => pred.Id,
                'predictedWinner' => pred.Predicted_Winner__r.Name,
                'confidence' => pred.Confidence_Score__c,
                'rationale' => pred.Prediction_Rationale__c,
                'modelType' => pred.Model_Type__c
            });
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String runAllPredictionModels(Id gameId) {
        try {
            PredictionEngine.predictAndSave(gameId);

            System.enqueueJob(
                new PredictionModelQueueable(gameId, 'Mascot Battle', 'AI Research')
            );

            return JSON.serialize(new Map<String, Object>{
                'statistical' => 'completed',
                'mascotBattle' => 'queued',
                'aiResearch' => 'queued',
                'message' => 'Statistical prediction complete. Mascot Battle and AI Research predictions are processing in the background.'
            });
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPredictionDetail(Id predictionId) {
        Prediction__c pred = [
            SELECT Id, Name, Confidence_Score__c, Team_1_Win_Probability__c,
                   Team_2_Win_Probability__c, Model_Type__c, Model_Version__c,
                   Prediction_Date__c, Prediction_Rationale__c, Is_Current__c,
                   Predicted_Winner__c, Predicted_Winner__r.Name,
                   Game__c, Game__r.Name, Game__r.Round__c, Game__r.Region__c,
                   Game__r.Status__c, Game__r.Team_1_Score__c, Game__r.Team_2_Score__c,
                   Game__r.Team_1__c, Game__r.Team_2__c,
                   Game__r.Winner__c, Game__r.Winner__r.Name
            FROM Prediction__c
            WHERE Id = :predictionId
            WITH USER_MODE
            LIMIT 1
        ];

        Map<String, Object> result = new Map<String, Object>();
        result.put('predictionName', pred.Name);
        result.put('confidence', pred.Confidence_Score__c);
        result.put('team1Prob', pred.Team_1_Win_Probability__c);
        result.put('team2Prob', pred.Team_2_Win_Probability__c);
        result.put('modelType', pred.Model_Type__c);
        result.put('modelVersion', pred.Model_Version__c);
        result.put('predictionDate', pred.Prediction_Date__c);
        result.put('rationale', pred.Prediction_Rationale__c);
        result.put('isCurrent', pred.Is_Current__c);
        result.put('predictedWinner', pred.Predicted_Winner__r?.Name);
        result.put('round', pred.Game__r?.Round__c);
        result.put('region', pred.Game__r?.Region__c);
        result.put('gameStatus', pred.Game__r?.Status__c);
        result.put('team1Score', pred.Game__r?.Team_1_Score__c);
        result.put('team2Score', pred.Game__r?.Team_2_Score__c);
        result.put('actualWinner', pred.Game__r?.Winner__r?.Name);

        Boolean wasCorrect = false;
        if (pred.Game__r?.Winner__c != null && pred.Predicted_Winner__c != null) {
            wasCorrect = (pred.Game__r.Winner__c == pred.Predicted_Winner__c);
        }
        result.put('wasCorrect', wasCorrect);

        if (pred.Game__r?.Team_1__c != null) {
            Team__c t1 = [
                SELECT Name, Seed__c, Logo_URL__c, Primary_Color__c
                FROM Team__c WHERE Id = :pred.Game__r.Team_1__c
                WITH USER_MODE LIMIT 1
            ];
            result.put('team1Name', t1.Name);
            result.put('team1Seed', t1.Seed__c);
            result.put('team1Logo', t1.Logo_URL__c);
            result.put('team1Color', t1.Primary_Color__c);
        }
        if (pred.Game__r?.Team_2__c != null) {
            Team__c t2 = [
                SELECT Name, Seed__c, Logo_URL__c, Primary_Color__c
                FROM Team__c WHERE Id = :pred.Game__r.Team_2__c
                WITH USER_MODE LIMIT 1
            ];
            result.put('team2Name', t2.Name);
            result.put('team2Seed', t2.Seed__c);
            result.put('team2Logo', t2.Logo_URL__c);
            result.put('team2Color', t2.Primary_Color__c);
        }

        return result;
    }

    @AuraEnabled
    public static ESPNScoreboardService.ConferenceTournamentResult getConferenceTournamentSchedule() {
        try {
            return ESPNScoreboardService.fetchConferenceTournamentWeek();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ESPNScoreboardService.ScoreboardResult getLiveScoreboard() {
        try {
            String today = Datetime.now().format('yyyyMMdd');
            return ESPNScoreboardService.fetchScoreboardForDate(today);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ESPNScoreboardService.ScoreboardResult getMultiDayScoreboard() {
        try {
            Datetime now = Datetime.now();
            List<String> dates = new List<String>();
            dates.add(now.addDays(-1).format('yyyyMMdd'));
            dates.add(now.format('yyyyMMdd'));
            dates.add(now.addDays(1).format('yyyyMMdd'));
            return ESPNScoreboardService.fetchMultiDayScoreboard(dates);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ESPNTeamService.TeamPerformance getTeamPerformance(Id teamId) {
        try {
            Team__c team = [SELECT Name FROM Team__c WHERE Id = :teamId LIMIT 1];
            return ESPNTeamService.fetchTeamPerformance(team.Name, 15);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String loadBracketFromESPN(Id tournamentId) {
        try {
            BracketDataService.loadFullBracket(tournamentId);
            return 'Bracket loaded successfully';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String refreshBracketResults(Id tournamentId) {
        try {
            BracketDataService.updateGameResults(tournamentId);
            return 'Game results updated';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Bracket_Scenario__c> getBracketScenarios(Id tournamentId) {
        return [
            SELECT Id, Name, Scenario_Name__c, Description__c, Strategy__c,
                   Champion__c, Champion__r.Name, Champion__r.Seed__c, Champion__r.Logo_URL__c,
                   Champion__r.Primary_Color__c, Champion__r.Region__c,
                   Runner_Up__c, Runner_Up__r.Name, Runner_Up__r.Seed__c, Runner_Up__r.Logo_URL__c,
                   Runner_Up__r.Primary_Color__c,
                   Final_Four_Summary__c, Total_Upsets__c, Overall_Confidence__c,
                   Biggest_Upset__c, Generated_Date__c, Bracket_JSON__c
            FROM Bracket_Scenario__c
            WHERE Tournament__c = :tournamentId
            WITH USER_MODE
            ORDER BY Strategy__c ASC
        ];
    }

    @AuraEnabled
    public static String generateBracketScenarios(Id tournamentId) {
        try {
            return BracketScenarioGenerator.generateAllScenarios(tournamentId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String refreshTeamResearch(Id teamId) {
        try {
            NewsIngestionService.ingestNewsForTeam(teamId);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Research refresh initiated for team ' + teamId
            });
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
