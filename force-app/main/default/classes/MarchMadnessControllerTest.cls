@isTest
private class MarchMadnessControllerTest {

    @TestSetup
    static void setupData() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();
        List<Team__c> teams = MarchMadnessTestDataFactory.createTeamPair(tournament.Id, 'East');
        Game__c game = MarchMadnessTestDataFactory.createGame(
            tournament.Id, teams[0].Id, teams[1].Id, 'Round of 64', 'East'
        );
        MarchMadnessTestDataFactory.createPrediction(game.Id, teams[0].Id, 80.0);
        MarchMadnessTestDataFactory.createResearch(teams[0].Id, 75);
        MarchMadnessTestDataFactory.createNewsArticle(teams[0].Id, 'Performance');
        MarchMadnessTestDataFactory.createNewsArticle(teams[1].Id, 'Injury');
    }

    @isTest
    static void testGetAllGames() {
        Tournament__c tournament = [SELECT Id FROM Tournament__c LIMIT 1];

        Test.startTest();
        List<Game__c> games = MarchMadnessController.getAllGames(tournament.Id);
        Test.stopTest();

        System.assert(!games.isEmpty(), 'Should return at least one game');
        System.assertNotEquals(null, games[0].Team_1__c, 'Game should have Team 1');
        System.assertNotEquals(null, games[0].Team_2__c, 'Game should have Team 2');
    }

    @isTest
    static void testGetCurrentPredictions() {
        Tournament__c tournament = [SELECT Id FROM Tournament__c LIMIT 1];

        Test.startTest();
        List<Prediction__c> predictions = MarchMadnessController.getCurrentPredictions(tournament.Id);
        Test.stopTest();

        System.assert(!predictions.isEmpty(), 'Should return current predictions');
        System.assertNotEquals(null, predictions[0].Predicted_Winner__c,
            'Prediction should have a predicted winner');
    }

    @isTest
    static void testGetTeamDetail() {
        Team__c team = [SELECT Id FROM Team__c WHERE Seed__c = 1 LIMIT 1];

        Test.startTest();
        Team__c detail = MarchMadnessController.getTeamDetail(team.Id);
        Test.stopTest();

        System.assertNotEquals(null, detail, 'Team detail should not be null');
        System.assertNotEquals(null, detail.Name, 'Team name should be populated');
        System.assert(!detail.Research_Records__r.isEmpty(),
            'Team should have research records from sub-query');
    }

    @isTest
    static void testGetLatestNews() {
        Test.startTest();
        List<News_Article__c> articles = MarchMadnessController.getLatestNews(10);
        Test.stopTest();

        System.assert(!articles.isEmpty(), 'Should return news articles');
        System.assert(articles.size() <= 10, 'Should respect the limit parameter');
    }

    @isTest
    static void testGetNewsForTeam() {
        Team__c team = [SELECT Id FROM Team__c WHERE Seed__c = 1 LIMIT 1];

        Test.startTest();
        List<News_Article__c> articles = MarchMadnessController.getNewsForTeam(team.Id);
        Test.stopTest();

        System.assert(!articles.isEmpty(), 'Should return articles for the specified team');
        for (News_Article__c article : articles) {
            System.assertEquals(team.Id, article.Team__c,
                'All articles should belong to the queried team');
        }
    }

    @isTest
    static void testGetPredictionsForRound() {
        Test.startTest();
        List<Prediction__c> predictions = MarchMadnessController.getPredictionsForRound('Round of 64');
        Test.stopTest();

        System.assert(!predictions.isEmpty(),
            'Should return predictions for Round of 64');
        for (Prediction__c p : predictions) {
            System.assertEquals(true, p.Is_Current__c,
                'All returned predictions should be current');
        }
    }

    @isTest
    static void testGetDashboardStats() {
        Tournament__c tournament = [SELECT Id FROM Tournament__c LIMIT 1];

        Test.startTest();
        Map<String, Object> stats = MarchMadnessController.getDashboardStats(tournament.Id);
        Test.stopTest();

        System.assert(stats.containsKey('totalPredictions'), 'Stats should contain totalPredictions');
        System.assert(stats.containsKey('avgConfidence'), 'Stats should contain avgConfidence');
        System.assert(stats.containsKey('predictionAccuracy'), 'Stats should contain predictionAccuracy');
        System.assert(stats.containsKey('correctPredictions'), 'Stats should contain correctPredictions');
        System.assert(stats.containsKey('completedGames'), 'Stats should contain completedGames');
        System.assert(stats.containsKey('upcomingGames'), 'Stats should contain upcomingGames');
    }

    @isTest
    static void testSearchTeams() {
        Test.startTest();
        List<Team__c> results = MarchMadnessController.searchTeams('Top Seed');
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should find teams matching search term');
    }

    @isTest
    static void testSearchTeams_ShortTerm() {
        Test.startTest();
        List<Team__c> results = MarchMadnessController.searchTeams('A');
        Test.stopTest();

        System.assert(results.isEmpty(),
            'Single-character search should return empty list');
    }

    @isTest
    static void testRunPrediction() {
        Game__c game = [SELECT Id FROM Game__c LIMIT 1];

        Test.startTest();
        String resultJson = MarchMadnessController.runPrediction(game.Id);
        Test.stopTest();

        System.assertNotEquals(null, resultJson, 'Result JSON should not be null');
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        System.assert(result.containsKey('predictionId'), 'Result should contain predictionId');
        System.assert(result.containsKey('predictedWinner'), 'Result should contain predictedWinner');
        System.assert(result.containsKey('confidence'), 'Result should contain confidence');
        System.assert(result.containsKey('rationale'), 'Result should contain rationale');
    }
}
