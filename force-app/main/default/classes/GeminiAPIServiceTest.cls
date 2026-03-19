@isTest
private class GeminiAPIServiceTest {

    private static final String MOCK_SUCCESS_BODY = '{"candidates":[{"content":{"parts":[{"text":"Test response"}]}}],"usageMetadata":{"totalTokenCount":100}}';

    private class GeminiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public GeminiMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    @isTest
    static void testGenerateContent_Success() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, MOCK_SUCCESS_BODY));

        Test.startTest();
        GeminiAPIService.GeminiResponse result = GeminiAPIService.generateContent('Test prompt');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Response should be successful');
        System.assertEquals('Test response', result.text, 'Response text should match mock');
        System.assertEquals(100, result.tokenCount, 'Token count should match mock');
        System.assertEquals(null, result.errorMessage, 'Error message should be null on success');
    }

    @isTest
    static void testGenerateContent_RateLimit() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(429, '{"error":"rate limited"}'));

        Test.startTest();
        GeminiAPIService.GeminiResponse result = GeminiAPIService.generateContent('Test prompt');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Response should not be successful on 429');
        System.assert(result.errorMessage.containsIgnoreCase('rate limit'),
            'Error should mention rate limit, got: ' + result.errorMessage);
    }

    @isTest
    static void testGenerateContent_ServerError() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(500, '{"error":"internal server error"}'));

        Test.startTest();
        GeminiAPIService.GeminiResponse result = GeminiAPIService.generateContent('Test prompt');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Response should not be successful on 500');
        System.assertNotEquals(null, result.errorMessage, 'Error message should be populated');
        System.assert(result.errorMessage.contains('500'),
            'Error should reference status code 500, got: ' + result.errorMessage);
    }

    @isTest
    static void testGenerateStructuredContent() {
        String structuredBody = '{"candidates":[{"content":{"parts":[{"text":"{\\"key\\":\\"value\\"}"}]}}],"usageMetadata":{"totalTokenCount":50}}';
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, structuredBody));

        String schema = '{"type":"object","properties":{"key":{"type":"string"}}}';

        Test.startTest();
        GeminiAPIService.GeminiResponse result = GeminiAPIService.generateStructuredContent('Test prompt', schema);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Structured content response should be successful');
        System.assertNotEquals(null, result.text, 'Response text should not be null');
        System.assertEquals(50, result.tokenCount, 'Token count should match mock');
    }

    @isTest
    static void testGenerateContent_ClientError() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(400, '{"error":"bad request"}'));

        Test.startTest();
        GeminiAPIService.GeminiResponse result = GeminiAPIService.generateContent('Test prompt');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Response should not be successful on 400');
        System.assert(result.errorMessage.contains('400'),
            'Error should reference status code 400');
    }
}
