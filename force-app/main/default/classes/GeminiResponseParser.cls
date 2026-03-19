public with sharing class GeminiResponseParser {

    private static final Pattern CODE_FENCE_PATTERN = Pattern.compile('```(?:json)?\\s*([\\s\\S]*?)\\s*```');

    public static Team_Research__c parseTeamResearch(String jsonResponse, Id teamId) {
        Team_Research__c research = new Team_Research__c(
            Team__c = teamId,
            Research_Date__c = DateTime.now(),
            Source_Type__c = 'General Analysis',
            Is_Current__c = true,
            Raw_Response__c = truncateForLongText(jsonResponse)
        );

        try {
            String cleaned = stripCodeFences(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);

            research.Summary__c = truncateForLongText((String) parsed.get('summary'));
            research.Sentiment_Score__c = extractDecimal(parsed, 'sentimentScore');
            research.Confidence_Level__c = (String) parsed.get('confidenceLevel');

            List<Object> keyFactors = (List<Object>) parsed.get('keyFactors');
            if (keyFactors != null) {
                research.Key_Factors__c = truncateForLongText(String.join(stringifyList(keyFactors), '; '));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiResponseParser.parseTeamResearch failed: ' + e.getMessage());
            research.Summary__c = extractFallbackSummary(jsonResponse);
            research.Confidence_Level__c = 'Low';
        }

        return research;
    }

    public static List<News_Article__c> parseNewsArticles(String jsonResponse, Id teamId) {
        List<News_Article__c> articles = new List<News_Article__c>();

        try {
            String cleaned = stripCodeFences(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> rawArticles = (List<Object>) parsed.get('articles');

            if (rawArticles == null) {
                return articles;
            }

            for (Object rawArticle : rawArticles) {
                Map<String, Object> articleMap = (Map<String, Object>) rawArticle;
                String artUrl = (String) articleMap.get('sourceUrl');
                if (String.isNotBlank(artUrl) && artUrl.length() > 255) artUrl = null;

                News_Article__c article = new News_Article__c(
                    Team__c = teamId,
                    Name = truncateForName((String) articleMap.get('title')),
                    Article_Date__c = Date.today(),
                    Source__c = (String) articleMap.get('source'),
                    Source_URL__c = artUrl,
                    Summary__c = truncateForLongText((String) articleMap.get('summary')),
                    Sentiment_Score__c = extractDecimal(articleMap, 'sentimentScore'),
                    Category__c = validateNewsCategory((String) articleMap.get('category')),
                    Relevance_Score__c = extractDecimal(articleMap, 'relevanceScore'),
                    Is_Featured__c = false,
                    Is_Verified__c = false,
                    Source_Type__c = 'AI Analysis'
                );

                List<Object> tags = (List<Object>) articleMap.get('tags');
                if (tags != null) {
                    article.Tags__c = truncateForField(String.join(stringifyList(tags), ', '), 255);
                }

                articles.add(article);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiResponseParser.parseNewsArticles failed: ' + e.getMessage());
        }

        return articles;
    }

    public static List<News_Article__c> parseGroundedNewsArticles(
        String jsonResponse, Id teamId, List<GeminiAPIService.GroundingSource> groundingSources
    ) {
        List<News_Article__c> articles = new List<News_Article__c>();

        try {
            String cleaned = stripCodeFences(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> rawArticles = (List<Object>) parsed.get('articles');

            if (rawArticles == null) return articles;

            Map<String, String> sourceUriMap = new Map<String, String>();
            if (groundingSources != null) {
                for (GeminiAPIService.GroundingSource src : groundingSources) {
                    if (src.title != null && src.uri != null) {
                        sourceUriMap.put(src.title.toLowerCase(), src.uri);
                    }
                }
            }

            String groundingText = '';
            if (groundingSources != null && !groundingSources.isEmpty()) {
                List<String> srcList = new List<String>();
                for (GeminiAPIService.GroundingSource src : groundingSources) {
                    srcList.add((src.title ?? '') + ' | ' + (src.uri ?? ''));
                }
                groundingText = String.join(srcList, '\n');
            }

            for (Object rawArticle : rawArticles) {
                Map<String, Object> articleMap = (Map<String, Object>) rawArticle;

                String title = (String) articleMap.get('title');
                String sourceUrl = (String) articleMap.get('sourceUrl');
                String sourceName = (String) articleMap.get('source');

                Boolean isVerified = String.isNotBlank(sourceUrl)
                    && (sourceUrl.startsWith('http://') || sourceUrl.startsWith('https://'));

                if (!isVerified && String.isNotBlank(title)) {
                    String titleLower = title.toLowerCase();
                    for (String key : sourceUriMap.keySet()) {
                        if (titleLower.contains(key) || key.contains(titleLower.left(30))) {
                            sourceUrl = sourceUriMap.get(key);
                            isVerified = true;
                            break;
                        }
                    }
                }

                if (String.isNotBlank(sourceUrl) && sourceUrl.length() > 255) {
                    sourceUrl = null;
                }

                String imageUrl = (String) articleMap.get('imageUrl');
                if (String.isNotBlank(imageUrl) && imageUrl.length() > 255) {
                    imageUrl = null;
                }

                News_Article__c article = new News_Article__c(
                    Team__c = teamId,
                    Name = truncateForName(title),
                    Article_Date__c = Date.today(),
                    Source__c = sourceName,
                    Source_URL__c = sourceUrl,
                    Summary__c = truncateForLongText((String) articleMap.get('summary')),
                    Sentiment_Score__c = extractDecimal(articleMap, 'sentimentScore'),
                    Category__c = validateNewsCategory((String) articleMap.get('category')),
                    Relevance_Score__c = extractDecimal(articleMap, 'relevanceScore'),
                    Is_Featured__c = false,
                    Is_Verified__c = isVerified,
                    Source_Type__c = 'Google Search',
                    Grounding_Sources__c = isVerified ? groundingText : null,
                    Image_URL__c = imageUrl
                );

                List<Object> tags = (List<Object>) articleMap.get('tags');
                if (tags != null) {
                    article.Tags__c = truncateForField(String.join(stringifyList(tags), ', '), 255);
                }

                articles.add(article);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiResponseParser.parseGroundedNewsArticles failed: ' + e.getMessage());
        }

        return articles;
    }

    private static String truncateForName(String value) {
        if (value == null) return 'Untitled';
        return value.length() > 80 ? value.substring(0, 80) : value;
    }

    public static Map<String, Object> parseHeadToHeadAnalysis(String jsonResponse) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            String cleaned = stripCodeFences(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);

            result.put('team1WinProb', extractDecimal(parsed, 'team1WinProbability'));
            result.put('team2WinProb', extractDecimal(parsed, 'team2WinProbability'));
            result.put('confidence', extractDecimal(parsed, 'confidence'));
            result.put('rationale', (String) parsed.get('rationale'));

            List<Object> keyFactors = (List<Object>) parsed.get('keyFactors');
            result.put('keyFactors', keyFactors != null ? stringifyList(keyFactors) : new List<String>());

            result.put('statisticalFactors', parsed.get('statisticalFactors'));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiResponseParser.parseHeadToHeadAnalysis failed: ' + e.getMessage());
            result.put('team1WinProb', 0.5);
            result.put('team2WinProb', 0.5);
            result.put('confidence', 0.0);
            result.put('rationale', 'Analysis could not be parsed: ' + e.getMessage());
            result.put('keyFactors', new List<String>());
        }

        return result;
    }

    public static List<Statistical_Factor__c> parseStatisticalFactors(String jsonResponse, Id teamId) {
        List<Statistical_Factor__c> factors = new List<Statistical_Factor__c>();

        try {
            String cleaned = stripCodeFences(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> rawFactors = (List<Object>) parsed.get('statisticalFactors');

            if (rawFactors == null) {
                return factors;
            }

            for (Object rawFactor : rawFactors) {
                Map<String, Object> factorMap = (Map<String, Object>) rawFactor;
                factors.add(new Statistical_Factor__c(
                    Team__c = teamId,
                    Factor_Name__c = (String) factorMap.get('factorName'),
                    Factor_Value__c = extractDecimal(factorMap, 'team1Value'),
                    Weight__c = extractDecimal(factorMap, 'weight'),
                    Category__c = (String) factorMap.get('category')
                ));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiResponseParser.parseStatisticalFactors failed: ' + e.getMessage());
        }

        return factors;
    }

    private static final Set<String> VALID_NEWS_CATEGORIES = new Set<String>{
        'Game Recap', 'Injury Update', 'Conference Tournament',
        'Expert Analysis', 'Bracket Projection', 'General News', 'Transfer Portal'
    };

    private static String validateNewsCategory(String category) {
        if (String.isBlank(category)) return 'General News';
        if (VALID_NEWS_CATEGORIES.contains(category)) return category;
        String lower = category.toLowerCase();
        if (lower.contains('injury')) return 'Injury Update';
        if (lower.contains('recap') || lower.contains('result') || lower.contains('performance')) return 'Game Recap';
        if (lower.contains('conference') || lower.contains('tournament')) return 'Conference Tournament';
        if (lower.contains('bracket') || lower.contains('projection') || lower.contains('seed')) return 'Bracket Projection';
        if (lower.contains('analysis') || lower.contains('expert') || lower.contains('strategy')) return 'Expert Analysis';
        if (lower.contains('transfer') || lower.contains('recruit')) return 'Transfer Portal';
        return 'General News';
    }

    public static String cleanJsonResponse(String input) {
        return stripCodeFences(input);
    }

    @TestVisible
    private static String stripCodeFences(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        Matcher m = CODE_FENCE_PATTERN.matcher(input);
        if (m.find()) {
            return m.group(1).trim();
        }
        return input.trim();
    }

    private static Decimal extractDecimal(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static List<String> stringifyList(List<Object> items) {
        List<String> strings = new List<String>();
        for (Object item : items) {
            strings.add(String.valueOf(item));
        }
        return strings;
    }

    private static String truncateForLongText(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > 131072 ? value.substring(0, 131072) : value;
    }

    private static String truncateForField(String value, Integer maxLen) {
        if (value == null) return null;
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }

    private static String truncateForRichText(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > 131072 ? value.substring(0, 131072) : value;
    }

    private static String extractFallbackSummary(String rawText) {
        if (String.isBlank(rawText)) {
            return 'No summary available.';
        }
        String cleaned = rawText.replaceAll('[\\{\\}\\[\\]"]', ' ').replaceAll('\\s+', ' ').trim();
        return cleaned.length() > 500 ? cleaned.substring(0, 500) + '...' : cleaned;
    }
}
