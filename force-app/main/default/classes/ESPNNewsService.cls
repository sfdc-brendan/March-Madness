public with sharing class ESPNNewsService {

    private static final String ESPN_NEWS_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/news';
    private static final String ESPN_TEAMS_URL =
        'https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams';
    private static final Integer HTTP_OK = 200;
    private static final Integer TIMEOUT_MS = 30000;

    public static List<News_Article__c> fetchGeneralNews(Integer articleLimit) {
        String url = ESPN_NEWS_URL + '?limit=' + articleLimit;
        return fetchAndParse(url, null);
    }

    public static List<News_Article__c> fetchTeamNews(String teamName, Id teamId) {
        String espnTeamId = lookupESPNTeamId(teamName);

        if (String.isNotBlank(espnTeamId)) {
            String url = ESPN_TEAMS_URL + '/' + espnTeamId + '/news?limit=15';
            List<News_Article__c> teamArticles = fetchAndParse(url, teamId);
            if (!teamArticles.isEmpty()) {
                return teamArticles;
            }
        }

        String url = ESPN_NEWS_URL + '?limit=40';
        List<News_Article__c> allArticles = fetchAndParse(url, teamId);

        List<News_Article__c> relevant = new List<News_Article__c>();
        String lower = teamName.toLowerCase();
        String shortName = extractShortName(teamName).toLowerCase();

        for (News_Article__c article : allArticles) {
            String headline = (article.Name ?? '').toLowerCase();
            String summary = (article.Summary__c ?? '').toLowerCase();

            if (headline.contains(lower) || headline.contains(shortName)
                || summary.contains(lower) || summary.contains(shortName)) {
                article.Team__c = teamId;
                relevant.add(article);
            }
        }

        return relevant;
    }

    private static String lookupESPNTeamId(String teamName) {
        String searchTerm = extractLocationName(teamName);
        String searchUrl = ESPN_TEAMS_URL + '?search=' + EncodingUtil.urlEncode(searchTerm, 'UTF-8') + '&limit=10';
        String responseJson = callESPN(searchUrl);
        if (responseJson == null) return null;

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseJson);
            List<Object> sports = (List<Object>) parsed.get('sports');
            if (sports == null || sports.isEmpty()) return null;

            Map<String, Object> sport = (Map<String, Object>) sports[0];
            List<Object> leagues = (List<Object>) sport.get('leagues');
            if (leagues == null || leagues.isEmpty()) return null;

            Map<String, Object> league = (Map<String, Object>) leagues[0];
            List<Object> teamList = (List<Object>) league.get('teams');
            if (teamList == null || teamList.isEmpty()) return null;

            String lowerName = teamName.toLowerCase();
            for (Object tw : teamList) {
                Map<String, Object> wrapper = (Map<String, Object>) tw;
                Map<String, Object> teamData = (Map<String, Object>) wrapper.get('team');
                if (teamData == null) continue;
                String displayName = ((String) teamData.get('displayName') ?? '').toLowerCase();
                String location = ((String) teamData.get('location') ?? '').toLowerCase();
                if (displayName == lowerName || lowerName.contains(location) || displayName.contains(searchTerm.toLowerCase())) {
                    return (String) teamData.get('id');
                }
            }

            Map<String, Object> firstWrapper = (Map<String, Object>) teamList[0];
            Map<String, Object> firstTeam = (Map<String, Object>) firstWrapper.get('team');
            return firstTeam != null ? (String) firstTeam.get('id') : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'ESPN team lookup failed: ' + e.getMessage());
        }
        return null;
    }

    private static String extractLocationName(String fullName) {
        if (String.isBlank(fullName)) return '';
        List<String> parts = fullName.split(' ');
        if (parts.size() <= 1) return fullName;
        if (parts.size() == 2) return parts[0];
        return parts[0] + ' ' + parts[1];
    }

    private static List<News_Article__c> fetchAndParse(String url, Id teamId) {
        List<News_Article__c> articles = new List<News_Article__c>();

        String responseJson = callESPN(url);
        if (responseJson == null) return articles;

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseJson);
            List<Object> rawArticles = (List<Object>) parsed.get('articles');

            if (rawArticles == null) return articles;

            Set<String> existingUrls = getExistingArticleUrls();

            for (Object rawObj : rawArticles) {
                Map<String, Object> raw = (Map<String, Object>) rawObj;

                String headline = (String) raw.get('headline');
                String description = (String) raw.get('description');
                String published = (String) raw.get('published');

                String articleUrl = extractArticleUrl(raw);

                if (existingUrls.contains(articleUrl)) continue;

                News_Article__c article = new News_Article__c();
                article.Name = truncate(headline, 80);
                article.Summary__c = description;
                article.Source__c = 'ESPN';
                article.Source_URL__c = articleUrl;
                article.Source_Type__c = 'ESPN';
                article.Is_Verified__c = true;
                article.Is_Featured__c = false;
                article.Category__c = categorizeESPNArticle(headline, description);
                article.Relevance_Score__c = 85;
                article.Sentiment_Score__c = estimateSentiment(headline, description);

                if (teamId != null) {
                    article.Team__c = teamId;
                }

                if (String.isNotBlank(published)) {
                    try {
                        article.Article_Date__c = Date.valueOf(published.substring(0, 10));
                    } catch (Exception e) {
                        article.Article_Date__c = Date.today();
                    }
                } else {
                    article.Article_Date__c = Date.today();
                }

                List<Object> categories = (List<Object>) raw.get('categories');
                if (categories != null) {
                    List<String> tags = new List<String>();
                    for (Object catObj : categories) {
                        Map<String, Object> catMap = (Map<String, Object>) catObj;
                        String catDesc = (String) catMap.get('description');
                        if (String.isNotBlank(catDesc)) tags.add(catDesc);
                    }
                    if (!tags.isEmpty()) {
                        String joined = String.join(tags, ', ');
                        article.Tags__c = joined.length() > 255 ? joined.substring(0, 255) : joined;
                    }
                }

                String imageUrl = extractImageUrl(raw);
                if (String.isNotBlank(imageUrl)) {
                    article.Image_URL__c = imageUrl;
                }

                String byline = (String) raw.get('byline');
                if (String.isNotBlank(byline)) {
                    article.Source__c = 'ESPN - ' + byline;
                }

                articles.add(article);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ESPNNewsService parse error: ' + e.getMessage());
        }

        return articles;
    }

    private static String extractImageUrl(Map<String, Object> raw) {
        List<Object> images = (List<Object>) raw.get('images');
        if (images == null || images.isEmpty()) return null;
        Map<String, Object> firstImage = (Map<String, Object>) images[0];
        String url = (String) firstImage.get('url');
        return String.isNotBlank(url) && url.length() <= 255 ? url : null;
    }

    private static String extractArticleUrl(Map<String, Object> raw) {
        Map<String, Object> links = (Map<String, Object>) raw.get('links');
        if (links != null) {
            Map<String, Object> web = (Map<String, Object>) links.get('web');
            if (web != null) {
                return (String) web.get('href');
            }
        }
        return '';
    }

    private static Set<String> getExistingArticleUrls() {
        Set<String> urls = new Set<String>();
        for (News_Article__c existing : [
            SELECT Source_URL__c FROM News_Article__c
            WHERE Source_URL__c != null AND Is_Verified__c = true
            ORDER BY CreatedDate DESC LIMIT 200
        ]) {
            urls.add(existing.Source_URL__c);
        }
        return urls;
    }

    private static String categorizeESPNArticle(String headline, String description) {
        String combined = ((headline ?? '') + ' ' + (description ?? '')).toLowerCase();
        if (combined.contains('injury') || combined.contains('injured') || combined.contains('out for')) {
            return 'Injury Update';
        }
        if (combined.contains('bracket') || combined.contains('seed') || combined.contains('selection')) {
            return 'Bracket Projection';
        }
        if (combined.contains('conference tournament') || combined.contains('conf.') || combined.contains('semifinal') || combined.contains('quarterfinal')) {
            return 'Conference Tournament';
        }
        if (combined.contains('preview') || combined.contains('analysis') || combined.contains('power rankings')) {
            return 'Expert Analysis';
        }
        if (combined.contains('recap') || combined.contains('defeats') || combined.contains('beats') || combined.contains('upset')) {
            return 'Game Recap';
        }
        if (combined.contains('transfer') || combined.contains('portal') || combined.contains('commit')) {
            return 'Transfer Portal';
        }
        return 'General News';
    }

    private static Integer estimateSentiment(String headline, String description) {
        String combined = ((headline ?? '') + ' ' + (description ?? '')).toLowerCase();
        Integer score = 0;

        List<String> positive = new List<String>{'wins', 'victory', 'dominant', 'clinch', 'advance', 'rally', 'surge', 'upset win', 'record-breaking'};
        List<String> negative = new List<String>{'loss', 'loses', 'eliminated', 'injury', 'injured', 'suspend', 'upset', 'collapse', 'struggle'};

        for (String word : positive) {
            if (combined.contains(word)) score += 20;
        }
        for (String word : negative) {
            if (combined.contains(word)) score -= 20;
        }

        return Math.max(-100, Math.min(100, score));
    }

    private static String extractShortName(String fullName) {
        if (String.isBlank(fullName)) return '';
        List<String> parts = fullName.split(' ');
        return parts.size() > 1 ? parts[parts.size() - 1] : fullName;
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) return '';
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }

    private static String callESPN(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == HTTP_OK) {
                return res.getBody();
            }
            System.debug(LoggingLevel.ERROR, 'ESPN News API HTTP ' + res.getStatusCode());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ESPN News API callout failed: ' + e.getMessage());
        }
        return null;
    }
}
