public with sharing class ContenderNewsSweep implements Database.Batchable<Id>, Database.AllowsCallouts, Database.Stateful {

    private List<Id> teamIds;
    private Integer successCount = 0;
    private Integer failCount = 0;
    private Integer articleCount = 0;

    private static final Integer MAX_CONTENDERS = 60;
    private static final Integer NEWS_FRESHNESS_HOURS = 12;

    public ContenderNewsSweep(List<Id> teamIds) {
        this.teamIds = teamIds;
    }

    public Iterable<Id> start(Database.BatchableContext ctx) {
        System.debug('ContenderNewsSweep starting for ' + teamIds.size() + ' teams');
        return teamIds;
    }

    public void execute(Database.BatchableContext ctx, List<Id> scope) {
        Id teamId = scope[0];
        try {
            Team__c t = [SELECT Id, Name FROM Team__c WHERE Id = :teamId LIMIT 1];
            System.debug('Sweep researching: ' + t.Name);

            String prompt = TeamResearchPromptBuilder.buildGroundedNewsPrompt(t.Name);
            GeminiAPIService.GeminiResponse resp = GeminiAPIService.generateGroundedContent(prompt);

            if (resp.success && String.isNotBlank(resp.text)) {
                List<News_Article__c> articles = GeminiResponseParser.parseGroundedNewsArticles(
                    resp.text, t.Id, resp.groundingSources
                );
                articles = deduplicateAgainstExisting(articles, t.Id);
                if (!articles.isEmpty()) {
                    insert articles;
                    articleCount += articles.size();
                    System.debug('Inserted ' + articles.size() + ' articles for ' + t.Name);
                }
            }
            successCount++;
        } catch (Exception e) {
            failCount++;
            System.debug(LoggingLevel.WARN,
                'Sweep failed for team ' + teamId + ': ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('ContenderNewsSweep COMPLETE. Teams: ' + (successCount + failCount)
            + ' | Success: ' + successCount
            + ' | Failed: ' + failCount
            + ' | Articles created: ' + articleCount);
    }

    public static Id startSweep() {
        List<Id> contenderIds = buildContenderList();
        if (contenderIds.isEmpty()) {
            System.debug('No contenders need news. Skipping sweep.');
            return null;
        }

        System.debug('Starting ContenderNewsSweep batch for ' + contenderIds.size() + ' teams');
        return Database.executeBatch(new ContenderNewsSweep(contenderIds), 1);
    }

    public static List<Id> buildContenderList() {
        Datetime freshnessCutoff = Datetime.now().addHours(-NEWS_FRESHNESS_HOURS);

        Set<Id> teamsWithRecentNews = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Team__c teamId
            FROM News_Article__c
            WHERE Team__c != null
                AND CreatedDate >= :freshnessCutoff
                AND Is_Verified__c = true
            GROUP BY Team__c
            HAVING COUNT(Id) >= 3
        ]) {
            teamsWithRecentNews.add((Id) ar.get('teamId'));
        }

        List<Team__c> contenders = [
            SELECT Id, Name, NET_Ranking__c, Record_Wins__c, Record_Losses__c, Conference__c
            FROM Team__c
            WHERE Id NOT IN :teamsWithRecentNews
            AND (
                NET_Ranking__c != null AND NET_Ranking__c <= 120
            )
            ORDER BY NET_Ranking__c ASC NULLS LAST
            LIMIT :MAX_CONTENDERS
        ];

        List<Id> ids = new List<Id>();
        for (Team__c t : contenders) {
            ids.add(t.Id);
        }

        System.debug('Contender list: ' + ids.size() + ' teams (skipped ' + teamsWithRecentNews.size() + ' with recent news)');
        return ids;
    }

    private List<News_Article__c> deduplicateAgainstExisting(List<News_Article__c> newArticles, Id teamId) {
        Set<String> existingKeys = new Set<String>();
        for (News_Article__c existing : [
            SELECT Name FROM News_Article__c
            WHERE Team__c = :teamId AND CreatedDate >= :Datetime.now().addDays(-3)
        ]) {
            existingKeys.add(normalizeKey(existing.Name));
        }

        List<News_Article__c> unique = new List<News_Article__c>();
        for (News_Article__c a : newArticles) {
            String key = normalizeKey(a.Name);
            if (!existingKeys.contains(key) && String.isNotBlank(a.Name)) {
                existingKeys.add(key);
                unique.add(a);
            }
        }
        return unique;
    }

    private String normalizeKey(String title) {
        if (String.isBlank(title)) return '';
        String key = title.toLowerCase().replaceAll('[^a-z0-9]', '');
        return key.length() > 40 ? key.substring(0, 40) : key;
    }
}
