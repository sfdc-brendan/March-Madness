@isTest
private class BracketSimulatorTest {

    private static Tournament__c setupBracket() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();

        List<Team__c> eastTeams = new List<Team__c>();
        List<Team__c> westTeams = new List<Team__c>();

        for (Integer i = 0; i < 4; i++) {
            Integer topSeed = i + 1;
            Integer bottomSeed = 16 - i;
            String eastName = 'East Team ' + topSeed;
            String westName = 'West Team ' + topSeed;

            Team__c eastTop = new Team__c(
                Name = eastName, Seed__c = topSeed, Region__c = 'East',
                Conference__c = 'ACC', Tournament__c = tournament.Id,
                Record_Wins__c = 30 - i, Record_Losses__c = 3 + i,
                KenPom_Rating__c = 28 - (i * 3), NET_Ranking__c = topSeed * 2,
                Strength_of_Schedule__c = 0.80 - (i * 0.05),
                Points_Per_Game__c = 82 - i, Opp_Points_Per_Game__c = 62 + i,
                Overall_Power_Rating__c = 94 - (i * 5), Last_10_Record__c = (9 - i) + '-' + (1 + i)
            );
            Team__c westTop = new Team__c(
                Name = westName, Seed__c = topSeed, Region__c = 'West',
                Conference__c = 'Big 12', Tournament__c = tournament.Id,
                Record_Wins__c = 29 - i, Record_Losses__c = 4 + i,
                KenPom_Rating__c = 26 - (i * 3), NET_Ranking__c = topSeed * 2 + 1,
                Strength_of_Schedule__c = 0.78 - (i * 0.05),
                Points_Per_Game__c = 80 - i, Opp_Points_Per_Game__c = 63 + i,
                Overall_Power_Rating__c = 92 - (i * 5), Last_10_Record__c = (8 - i) + '-' + (2 + i)
            );

            eastTeams.add(eastTop);
            westTeams.add(westTop);
        }

        List<Team__c> allTeams = new List<Team__c>();
        allTeams.addAll(eastTeams);
        allTeams.addAll(westTeams);
        insert allTeams;

        List<Game__c> games = new List<Game__c>();
        Integer gameNum = 1;

        games.add(buildGame(tournament.Id, eastTeams[0].Id, eastTeams[3].Id, 'Round of 64', 'East', gameNum++));
        games.add(buildGame(tournament.Id, eastTeams[1].Id, eastTeams[2].Id, 'Round of 64', 'East', gameNum++));
        games.add(buildGame(tournament.Id, westTeams[0].Id, westTeams[3].Id, 'Round of 64', 'West', gameNum++));
        games.add(buildGame(tournament.Id, westTeams[1].Id, westTeams[2].Id, 'Round of 64', 'West', gameNum++));

        Game__c eastElite = buildGame(tournament.Id, eastTeams[0].Id, eastTeams[1].Id, 'Elite 8', 'East', gameNum++);
        Game__c westElite = buildGame(tournament.Id, westTeams[0].Id, westTeams[1].Id, 'Elite 8', 'West', gameNum++);
        games.add(eastElite);
        games.add(westElite);

        games.add(buildGame(tournament.Id, eastTeams[0].Id, westTeams[0].Id, 'Final Four', null, gameNum++));

        insert games;
        return tournament;
    }

    private static Game__c buildGame(Id tournamentId, Id team1Id, Id team2Id,
            String round, String region, Integer gameNum) {
        return new Game__c(
            Tournament__c = tournamentId,
            Team_1__c = team1Id,
            Team_2__c = team2Id,
            Round__c = round,
            Region__c = region,
            Status__c = 'Scheduled',
            Game_Date__c = DateTime.now().addDays(1),
            Game_Number__c = gameNum,
            Bracket_Position__c = gameNum
        );
    }

    @isTest
    static void testSimulateBracket() {
        Tournament__c tournament = setupBracket();

        Test.startTest();
        Map<Id, Map<String, Decimal>> results = BracketSimulator.simulateBracket(tournament.Id, 10);
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Simulation results should not be empty');
        for (Id teamId : results.keySet()) {
            Map<String, Decimal> teamResults = results.get(teamId);
            System.assertNotEquals(null, teamResults,
                'Each team should have round probability data');
        }
    }

    @isTest
    static void testGetProjectedFinalFour() {
        Tournament__c tournament = setupBracket();

        Test.startTest();
        List<Map<String, Object>> finalFour = BracketSimulator.getProjectedFinalFour(tournament.Id);
        Test.stopTest();

        System.assertEquals(4, finalFour.size(),
            'Should return exactly 4 Final Four teams');
        for (Map<String, Object> team : finalFour) {
            System.assertNotEquals(null, team.get('teamId'), 'Team should have an Id');
            System.assertNotEquals(null, team.get('teamName'), 'Team should have a name');
            System.assertNotEquals(null, team.get('probability'), 'Team should have a probability');
        }
    }

    @isTest
    static void testGetProjectedChampion() {
        Tournament__c tournament = setupBracket();

        Test.startTest();
        Map<String, Object> champion = BracketSimulator.getProjectedChampion(tournament.Id);
        Test.stopTest();

        System.assert(!champion.isEmpty(), 'Champion result should not be empty');
        System.assertNotEquals(null, champion.get('teamId'), 'Champion should have a teamId');
        System.assertNotEquals(null, champion.get('teamName'), 'Champion should have a teamName');
        System.assertNotEquals(null, champion.get('probability'), 'Champion should have a probability');

        Decimal prob = (Decimal) champion.get('probability');
        System.assert(prob >= 0 && prob <= 1,
            'Champion probability should be 0-1, got: ' + prob);
    }

    @isTest
    static void testRunAndSavePredictions() {
        Tournament__c tournament = setupBracket();

        Test.startTest();
        BracketSimulator.runAndSavePredictions(tournament.Id);
        Test.stopTest();

        Integer predCount = [
            SELECT COUNT() FROM Prediction__c
            WHERE Game__r.Tournament__c = :tournament.Id AND Is_Current__c = true
        ];
        Integer scheduledGames = [
            SELECT COUNT() FROM Game__c
            WHERE Tournament__c = :tournament.Id
              AND Status__c = 'Scheduled'
              AND Team_1__c != null AND Team_2__c != null
        ];
        System.assertEquals(scheduledGames, predCount,
            'Should have one current prediction per scheduled game');
    }
}
