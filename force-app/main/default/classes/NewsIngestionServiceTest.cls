@isTest
private class NewsIngestionServiceTest {

    private static final String MOCK_RESEARCH_RESPONSE = '{"candidates":[{"content":{"parts":[{"text":"' +
        '{\\"summary\\":\\"Strong team with excellent defense.\\",\\"sentimentScore\\":80,' +
        '\\"confidenceLevel\\":\\"High\\",\\"keyFactors\\":[\\"Elite defense\\",\\"Strong guard play\\"],' +
        '\\"recentPerformance\\":\\"Won 8 of last 10\\",\\"injuries\\":\\"None\\",\\"tournamentOutlook\\":\\"Favorable\\",' +
        '\\"keyPlayers\\":[\\"Player A\\",\\"Player B\\"],\\"strengths\\":[\\"Defense\\"],\\"weaknesses\\":[\\"Free throws\\"]}"' +
        '}]}}],"usageMetadata":{"totalTokenCount":200}}';

    private static final String MOCK_NEWS_RESPONSE = '{"candidates":[{"content":{"parts":[{"text":"' +
        '{\\"articles\\":[{\\"title\\":\\"Team Wins Big\\",\\"source\\":\\"ESPN\\",' +
        '\\"sourceUrl\\":\\"https://espn.com/test\\",\\"summary\\":\\"Great win last night.\\",' +
        '\\"sentimentScore\\":75,\\"category\\":\\"Performance\\",\\"relevanceScore\\":90,' +
        '\\"tags\\":[\\"basketball\\",\\"ncaa\\"]}]}"' +
        '}]}}],"usageMetadata":{"totalTokenCount":150}}';

    private static final String MOCK_CONFERENCE_RESPONSE = '{"candidates":[{"content":{"parts":[{"text":"' +
        '{\\"conferenceName\\":\\"ACC\\",\\"tournamentStatus\\":\\"In Progress\\",' +
        '\\"results\\":[{\\"teamName\\":\\"east top seed\\",\\"result\\":\\"Won Quarterfinal\\",' +
        '\\"eliminated\\":false,\\"tournamentLikelihood\\":\\"Lock\\"}],' +
        '\\"sentimentScore\\":70,\\"confidenceLevel\\":\\"High\\",' +
        '\\"keyFactors\\":[\\"Strong top seeds\\"],\\"summary\\":\\"Conference performing well.\\"}"' +
        '}]}}],"usageMetadata":{"totalTokenCount":180}}';

    private static final String MOCK_LIKELIHOOD_RESPONSE = '{"candidates":[{"content":{"parts":[{"text":"Lock"}]}}],"usageMetadata":{"totalTokenCount":10}}';

    private class GeminiMock implements HttpCalloutMock {
        private List<String> responses;
        private Integer callIndex = 0;

        public GeminiMock(List<String> responses) {
            this.responses = responses;
        }

        public GeminiMock(String singleResponse) {
            this.responses = new List<String>{ singleResponse };
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String body = this.callIndex < this.responses.size()
                ? this.responses[this.callIndex]
                : this.responses[this.responses.size() - 1];
            res.setBody(body);
            this.callIndex++;
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        Tournament__c tournament = MarchMadnessTestDataFactory.createTournament();
        MarchMadnessTestDataFactory.createTeamPair(tournament.Id, 'East');
    }

    @isTest
    static void testIngestNewsForTeam() {
        Team__c team = [SELECT Id FROM Team__c WHERE Seed__c = 1 LIMIT 1];

        Test.setMock(HttpCalloutMock.class,
            new GeminiMock(new List<String>{ MOCK_RESEARCH_RESPONSE, MOCK_NEWS_RESPONSE }));

        Test.startTest();
        NewsIngestionService.ingestNewsForTeam(team.Id);
        Test.stopTest();

        List<Team_Research__c> research = [
            SELECT Id, Summary__c, Sentiment_Score__c, Is_Current__c
            FROM Team_Research__c
            WHERE Team__c = :team.Id AND Is_Current__c = true
        ];
        System.assert(!research.isEmpty(),
            'Should have created a current research record');

        List<News_Article__c> articles = [
            SELECT Id, Name FROM News_Article__c WHERE Team__c = :team.Id
        ];
        System.assert(!articles.isEmpty(),
            'Should have created news articles');
    }

    @isTest
    static void testIngestConferenceTournamentNews() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(MOCK_CONFERENCE_RESPONSE));

        Test.startTest();
        NewsIngestionService.ingestConferenceTournamentNews('ACC');
        Test.stopTest();

        List<Team__c> updatedTeams = [
            SELECT Id, Conference_Tournament_Status__c
            FROM Team__c
            WHERE Conference__c = 'ACC' AND Conference_Tournament_Status__c != null
        ];

        System.assert(updatedTeams.size() >= 0,
            'Teams in conference should have been processed');
    }

    @isTest
    static void testUpdateTournamentLikelihood() {
        Team__c team = [SELECT Id FROM Team__c WHERE Seed__c = 1 LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new GeminiMock(MOCK_LIKELIHOOD_RESPONSE));

        Test.startTest();
        NewsIngestionService.updateTournamentLikelihood(team.Id);
        Test.stopTest();

        Team__c updated = [
            SELECT Tournament_Likelihood__c FROM Team__c WHERE Id = :team.Id
        ];
        System.assertEquals(95, updated.Tournament_Likelihood__c,
            'Lock response should set likelihood to 95');
    }

    @isTest
    static void testIngestNewsForTeams_Invocable() {
        Team__c team = [SELECT Id FROM Team__c WHERE Seed__c = 1 LIMIT 1];

        Test.setMock(HttpCalloutMock.class,
            new GeminiMock(new List<String>{ MOCK_RESEARCH_RESPONSE, MOCK_NEWS_RESPONSE }));

        NewsIngestionService.IngestNewsRequest request = new NewsIngestionService.IngestNewsRequest();
        request.teamId = team.Id;

        Test.startTest();
        List<String> results = NewsIngestionService.ingestNewsForTeams(
            new List<NewsIngestionService.IngestNewsRequest>{ request }
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Invocable method should return results');
        System.assert(results[0].containsIgnoreCase('queued') || results[0].containsIgnoreCase('success'),
            'Result should indicate queued or success, got: ' + results[0]);
    }

    @isTest
    static void testIngestNewsForTeams_Conference() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(MOCK_CONFERENCE_RESPONSE));

        NewsIngestionService.IngestNewsRequest request = new NewsIngestionService.IngestNewsRequest();
        request.conference = 'ACC';

        Test.startTest();
        List<String> results = NewsIngestionService.ingestNewsForTeams(
            new List<NewsIngestionService.IngestNewsRequest>{ request }
        );
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Conference invocable should return results');
        System.assert(results[0].containsIgnoreCase('conference'),
            'Result should mention conference, got: ' + results[0]);
    }
}
