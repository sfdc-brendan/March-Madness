public with sharing class GeminiAPIService {

    private static final Integer TIMEOUT_MS = 120000;
    private static final String FALLBACK_MODEL = 'gemini-2.0-flash';
    private static final String FALLBACK_ENDPOINT = 'https://generativelanguage.googleapis.com';
    private static final String ENDPOINT_TEMPLATE = '{0}/v1beta/models/{1}:generateContent?key={2}';

    private static Gemini_Config__mdt cachedConfig;

    public class GeminiResponse {
        public String text;
        public Boolean success;
        public String errorMessage;
        public Integer tokenCount;
        public List<GroundingSource> groundingSources;

        public GeminiResponse() {
            this.success = false;
            this.tokenCount = 0;
            this.groundingSources = new List<GroundingSource>();
        }

        public Boolean hasGrounding() {
            return !this.groundingSources.isEmpty();
        }
    }

    public class GroundingSource {
        public String uri;
        public String title;
    }

    public static GeminiResponse generateContent(String prompt) {
        return generateContent(prompt, getDefaultModel());
    }

    public static GeminiResponse generateContent(String prompt, String model) {
        Map<String, Object> requestBody = buildRequestBody(prompt);
        return executeRequest(requestBody, model);
    }

    public static GeminiResponse generateGroundedContent(String prompt) {
        Map<String, Object> requestBody = buildRequestBody(prompt);
        List<Object> tools = new List<Object>{
            new Map<String, Object>{ 'googleSearch' => new Map<String, Object>() }
        };
        requestBody.put('tools', tools);
        return executeRequest(requestBody, getDefaultModel());
    }

    public static GeminiResponse generateStructuredContent(String prompt, String jsonSchema) {
        Map<String, Object> requestBody = buildRequestBody(prompt);

        Map<String, Object> generationConfig = new Map<String, Object>();
        generationConfig.put('responseMimeType', 'application/json');
        if (String.isNotBlank(jsonSchema)) {
            generationConfig.put('responseSchema', JSON.deserializeUntyped(jsonSchema));
        }
        requestBody.put('generationConfig', generationConfig);

        return executeRequest(requestBody, getDefaultModel());
    }

    @TestVisible
    private static Gemini_Config__mdt getConfig() {
        if (cachedConfig != null) {
            return cachedConfig;
        }
        List<Gemini_Config__mdt> configs = [
            SELECT API_Key__c, Default_Model__c, Endpoint_Base__c, Is_Active__c
            FROM Gemini_Config__mdt
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        cachedConfig = configs.isEmpty() ? null : configs[0];
        return cachedConfig;
    }

    private static String getApiKey() {
        Gemini_Config__mdt config = getConfig();
        if (config == null || String.isBlank(config.API_Key__c)) {
            throw new GeminiConfigException(
                'Gemini API key not configured. Go to Setup > Custom Metadata Types > Gemini Config and set the API Key.'
            );
        }
        return config.API_Key__c;
    }

    private static String getDefaultModel() {
        Gemini_Config__mdt config = getConfig();
        return (config != null && String.isNotBlank(config.Default_Model__c))
            ? config.Default_Model__c : FALLBACK_MODEL;
    }

    private static String getEndpointBase() {
        Gemini_Config__mdt config = getConfig();
        return (config != null && String.isNotBlank(config.Endpoint_Base__c))
            ? config.Endpoint_Base__c : FALLBACK_ENDPOINT;
    }

    private static Map<String, Object> buildRequestBody(String prompt) {
        Map<String, Object> textPart = new Map<String, Object>{ 'text' => prompt };
        Map<String, Object> content = new Map<String, Object>{
            'parts' => new List<Object>{ textPart }
        };
        return new Map<String, Object>{
            'contents' => new List<Object>{ content }
        };
    }

    private static GeminiResponse executeRequest(Map<String, Object> requestBody, String model) {
        GeminiResponse result = new GeminiResponse();

        String apiKey = getApiKey();
        String endpoint = String.format(
            ENDPOINT_TEMPLATE,
            new List<String>{ getEndpointBase(), model, apiKey }
        );

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(requestBody));

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            result = handleResponse(res);
        } catch (GeminiConfigException e) {
            result.errorMessage = e.getMessage();
        } catch (System.CalloutException e) {
            result.errorMessage = 'Callout failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'GeminiAPIService callout exception: ' + e.getMessage());
        }

        return result;
    }

    private static GeminiResponse handleResponse(HttpResponse res) {
        GeminiResponse result = new GeminiResponse();
        Integer statusCode = res.getStatusCode();

        if (statusCode == 200) {
            return parseSuccessResponse(res.getBody());
        }

        if (statusCode == 429) {
            result.errorMessage = 'Rate limit exceeded. Retry after a delay.';
        } else if (statusCode >= 500) {
            result.errorMessage = 'Gemini server error (HTTP ' + statusCode + '): ' + res.getBody();
        } else {
            result.errorMessage = 'Gemini API error (HTTP ' + statusCode + '): ' + res.getBody();
        }

        System.debug(LoggingLevel.ERROR, 'GeminiAPIService HTTP ' + statusCode + ': ' + res.getBody());
        return result;
    }

    private static GeminiResponse parseSuccessResponse(String responseBody) {
        GeminiResponse result = new GeminiResponse();

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> candidates = (List<Object>) parsed.get('candidates');
            if (candidates != null && !candidates.isEmpty()) {
                Map<String, Object> candidate = (Map<String, Object>) candidates[0];
                Map<String, Object> content = (Map<String, Object>) candidate.get('content');
                List<Object> parts = (List<Object>) content.get('parts');
                if (parts != null && !parts.isEmpty()) {
                    Map<String, Object> part = (Map<String, Object>) parts[0];
                    result.text = (String) part.get('text');
                    result.success = true;
                }
            }

            Map<String, Object> usage = (Map<String, Object>) parsed.get('usageMetadata');
            if (usage != null && usage.containsKey('totalTokenCount')) {
                result.tokenCount = (Integer) usage.get('totalTokenCount');
            }

            if (candidates != null && !candidates.isEmpty()) {
                Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
                Map<String, Object> groundingMeta = (Map<String, Object>) firstCandidate.get('groundingMetadata');
                if (groundingMeta != null) {
                    List<Object> chunks = (List<Object>) groundingMeta.get('groundingChunks');
                    if (chunks != null) {
                        for (Object chunkObj : chunks) {
                            Map<String, Object> chunk = (Map<String, Object>) chunkObj;
                            Map<String, Object> web = (Map<String, Object>) chunk.get('web');
                            if (web != null) {
                                GroundingSource src = new GroundingSource();
                                src.uri = (String) web.get('uri');
                                src.title = (String) web.get('title');
                                result.groundingSources.add(src);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            result.errorMessage = 'Failed to parse Gemini response: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'GeminiAPIService parse error: ' + e.getMessage() + ' | Body: ' + responseBody);
        }

        return result;
    }

    public class GeminiConfigException extends Exception {}
}
