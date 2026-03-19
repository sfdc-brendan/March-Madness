@isTest
private class BracketDataServiceTest {

    private static final String MOCK_TEAMS_RESPONSE = '{"sports":[{"leagues":[{"teams":[' +
        '{"team":{"displayName":"Duke Blue Devils","groups":[{"name":"ACC"}],"record":{"items":[{"summary":"28-5"}]}}},' +
        '{"team":{"displayName":"Kansas Jayhawks","groups":[{"name":"Big 12"}],"record":{"items":[{"summary":"26-7"}]}}}' +
        ']}]}]}';

    private static final String MOCK_SCOREBOARD_RESPONSE = '{"events":[' +
        '{"date":"2026-03-19T00:00Z","competitions":[{' +
        '"competitors":[' +
        '{"team":{"displayName":"Duke Blue Devils"},"score":"75","winner":true,"curatedRank":{"current":1}},' +
        '{"team":{"displayName":"Kansas Jayhawks"},"score":"68","winner":false,"curatedRank":{"current":4}}' +
        '],"status":{"type":{"completed":true}},' +
        '"notes":[{"headline":"NCAA Tournament - First Round"}]' +
        '}]}]}';

    private static final String MOCK_RANKINGS_RESPONSE = '{"rankings":[{"ranks":[' +
        '{"current":1,"team":{"displayName":"Duke Blue Devils"}},' +
        '{"current":5,"team":{"displayName":"Kansas Jayhawks"}}' +
        ']}]}';

    private class ESPNMock implements HttpCalloutMock {
        private String teamsBody;
        private String scoreboardBody;
        private String rankingsBody;

        public ESPNMock(String teamsBody, String scoreboardBody, String rankingsBody) {
            this.teamsBody = teamsBody;
            this.scoreboardBody = scoreboardBody;
            this.rankingsBody = rankingsBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('rankings')) {
                res.setBody(this.rankingsBody);
            } else if (endpoint.contains('scoreboard')) {
                res.setBody(this.scoreboardBody);
            } else {
                res.setBody(this.teamsBody);
            }
            return res;
        }
    }

    @isTest
    static void testLoadBracketData() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();

        String emptyScoreboard = '{"events":[]}';
        Test.setMock(HttpCalloutMock.class,
            new ESPNMock(MOCK_TEAMS_RESPONSE, emptyScoreboard, MOCK_RANKINGS_RESPONSE));

        Test.startTest();
        BracketDataService.BracketLoadRequest req = new BracketDataService.BracketLoadRequest();
        req.tournamentId = tournament.Id;
        List<String> results = BracketDataService.loadBracketData(
            new List<BracketDataService.BracketLoadRequest>{ req }
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return at least one result');
        System.assert(results[0].startsWith('Success'),
            'Result should indicate success, got: ' + results[0]);

        List<Team__c> teams = [SELECT Id, Name FROM Team__c WHERE Tournament__c = :tournament.Id];
        System.assert(teams.size() >= 2,
            'Should have created teams from ESPN data, found: ' + teams.size());
    }

    @isTest
    static void testUpdateGameResults() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();

        Team__c duke = MarchMadnessTestDataFactory.createTeam(tournament.Id, 'Duke Blue Devils', 1, 'East');
        Team__c kansas = MarchMadnessTestDataFactory.createTeam(tournament.Id, 'Kansas Jayhawks', 4, 'East');
        Game__c game = MarchMadnessTestDataFactory.createGame(
            tournament.Id, duke.Id, kansas.Id, 'Round of 64', 'East'
        );

        Test.setMock(HttpCalloutMock.class,
            new ESPNMock(MOCK_TEAMS_RESPONSE, MOCK_SCOREBOARD_RESPONSE, MOCK_RANKINGS_RESPONSE));

        Test.startTest();
        BracketDataService.updateGameResults(tournament.Id);
        Test.stopTest();

        Game__c updatedGame = [
            SELECT Status__c, Team_1_Score__c, Team_2_Score__c, Winner__c
            FROM Game__c
            WHERE Id = :game.Id
        ];

        System.assertEquals('Final', updatedGame.Status__c,
            'Game should be marked as Final after update');
        System.assertEquals(75, updatedGame.Team_1_Score__c,
            'Team 1 score should be updated');
        System.assertEquals(68, updatedGame.Team_2_Score__c,
            'Team 2 score should be updated');
    }

    @isTest
    static void testLoadTeamStats() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();
        MarchMadnessTestDataFactory.createTeam(tournament.Id, 'Duke Blue Devils', 1, 'East');
        MarchMadnessTestDataFactory.createTeam(tournament.Id, 'Kansas Jayhawks', 4, 'East');

        Test.setMock(HttpCalloutMock.class,
            new ESPNMock(MOCK_TEAMS_RESPONSE, '{"events":[]}', MOCK_RANKINGS_RESPONSE));

        Test.startTest();
        BracketDataService.loadTeamStats(tournament.Id);
        Test.stopTest();

        Team__c duke = [
            SELECT NET_Ranking__c FROM Team__c
            WHERE Name = 'Duke Blue Devils' AND Tournament__c = :tournament.Id
        ];
        System.assertEquals(1, duke.NET_Ranking__c,
            'Duke NET ranking should be updated to 1');

        Team__c kansas = [
            SELECT NET_Ranking__c FROM Team__c
            WHERE Name = 'Kansas Jayhawks' AND Tournament__c = :tournament.Id
        ];
        System.assertEquals(5, kansas.NET_Ranking__c,
            'Kansas NET ranking should be updated to 5');
    }
}
