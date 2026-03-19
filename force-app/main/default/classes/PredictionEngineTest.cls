@isTest
private class PredictionEngineTest {

    @TestSetup
    static void setupData() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();
        List<Team__c> teams = MarchMadnessTestDataFactory.createTeamPair(tournament.Id, 'East');
        MarchMadnessTestDataFactory.createGame(tournament.Id, teams[0].Id, teams[1].Id, 'Round of 64', 'East');
    }

    @isTest
    static void testPredictGame() {
        Game__c game = [SELECT Id FROM Game__c LIMIT 1];

        Test.startTest();
        Prediction__c prediction = PredictionEngine.predictGame(game.Id);
        Test.stopTest();

        System.assertNotEquals(null, prediction, 'Prediction should not be null');
        System.assertNotEquals(null, prediction.Predicted_Winner__c, 'Predicted winner should be set');
        System.assert(prediction.Team_1_Win_Probability__c >= 0 && prediction.Team_1_Win_Probability__c <= 100,
            'Team 1 win probability should be 0-100, got: ' + prediction.Team_1_Win_Probability__c);
        System.assert(prediction.Team_2_Win_Probability__c >= 0 && prediction.Team_2_Win_Probability__c <= 100,
            'Team 2 win probability should be 0-100, got: ' + prediction.Team_2_Win_Probability__c);
        System.assertNotEquals(null, prediction.Prediction_Rationale__c, 'Rationale should be populated');
        System.assertEquals('v1.0', prediction.Model_Version__c, 'Model version should be v1.0');
        System.assertEquals(true, prediction.Is_Current__c, 'Prediction should be marked current');
    }

    @isTest
    static void testPredictAllGames() {
        Tournament__c tournament = [SELECT Id FROM Tournament__c LIMIT 1];
        List<Team__c> teams = [SELECT Id FROM Team__c ORDER BY Seed__c LIMIT 2];
        MarchMadnessTestDataFactory.createGame(tournament.Id, teams[0].Id, teams[1].Id, 'Round of 64', 'East');

        Integer scheduledCount = [SELECT COUNT() FROM Game__c WHERE Round__c = 'Round of 64' AND Status__c = 'Scheduled'];

        Test.startTest();
        List<Prediction__c> predictions = PredictionEngine.predictAllGames('Round of 64');
        Test.stopTest();

        System.assertEquals(scheduledCount, predictions.size(),
            'Should return one prediction per scheduled game in the round');
    }

    @isTest
    static void testPredictAndSave() {
        Game__c game = [SELECT Id FROM Game__c LIMIT 1];
        List<Team__c> teams = [SELECT Id FROM Team__c ORDER BY Seed__c LIMIT 2];
        MarchMadnessTestDataFactory.createPrediction(game.Id, teams[0].Id, 75.0);

        Test.startTest();
        PredictionEngine.predictAndSave(game.Id);
        Test.stopTest();

        List<Prediction__c> currentPreds = [
            SELECT Id FROM Prediction__c
            WHERE Game__c = :game.Id AND Is_Current__c = true
        ];
        System.assertEquals(1, currentPreds.size(),
            'Should have exactly one current prediction after predictAndSave');

        List<Prediction__c> oldPreds = [
            SELECT Id FROM Prediction__c
            WHERE Game__c = :game.Id AND Is_Current__c = false
        ];
        System.assertEquals(1, oldPreds.size(),
            'Old prediction should be marked as not current');
    }

    @isTest
    static void testCalculateTeamStrength() {
        Team__c team = [
            SELECT Id, Seed__c, KenPom_Rating__c, Record_Wins__c, Record_Losses__c,
                   Points_Per_Game__c, Opp_Points_Per_Game__c
            FROM Team__c
            WHERE Seed__c = 1
            LIMIT 1
        ];

        Test.startTest();
        Decimal strength = PredictionEngine.calculateTeamStrength(team);
        Test.stopTest();

        System.assert(strength >= 0 && strength <= 100,
            'Team strength should be between 0 and 100, got: ' + strength);
        System.assert(strength > 50,
            'A 1-seed with strong stats should have strength above 50, got: ' + strength);
    }

    @isTest
    static void testCalculateWinProbability() {
        List<Team__c> teams = [
            SELECT Id, Name, Seed__c, KenPom_Rating__c, NET_Ranking__c,
                   Strength_of_Schedule__c, Points_Per_Game__c, Opp_Points_Per_Game__c,
                   Record_Wins__c, Record_Losses__c, Last_10_Record__c,
                   Overall_Power_Rating__c
            FROM Team__c
            ORDER BY Seed__c
            LIMIT 2
        ];

        Test.startTest();
        Decimal winProb = PredictionEngine.calculateWinProbability(teams[0], teams[1]);
        Test.stopTest();

        System.assert(winProb >= 0 && winProb <= 1,
            'Win probability should be between 0 and 1, got: ' + winProb);
        System.assert(winProb > 0.5,
            'Higher-rated team should have >50% win probability, got: ' + winProb);
    }

    @isTest
    static void testCalculateWinProbability_NullStats() {
        Tournament__c tournament = [SELECT Id FROM Tournament__c LIMIT 1];

        Team__c nullTeam1 = new Team__c(
            Name = 'Null Stats Team A',
            Tournament__c = tournament.Id,
            Region__c = 'West'
        );
        Team__c nullTeam2 = new Team__c(
            Name = 'Null Stats Team B',
            Tournament__c = tournament.Id,
            Region__c = 'West'
        );
        insert new List<Team__c>{ nullTeam1, nullTeam2 };

        List<Team__c> teams = [
            SELECT Id, Name, Seed__c, KenPom_Rating__c, NET_Ranking__c,
                   Strength_of_Schedule__c, Points_Per_Game__c, Opp_Points_Per_Game__c,
                   Record_Wins__c, Record_Losses__c, Last_10_Record__c,
                   Overall_Power_Rating__c
            FROM Team__c
            WHERE Id IN (:nullTeam1.Id, :nullTeam2.Id)
        ];

        Test.startTest();
        Decimal winProb = PredictionEngine.calculateWinProbability(teams[0], teams[1]);
        Test.stopTest();

        System.assert(winProb >= 0.4 && winProb <= 0.6,
            'Null-stats teams should produce ~0.5 probability, got: ' + winProb);
    }
}
