public with sharing class NewsIngestionService {

    public class IngestNewsRequest {
        @InvocableVariable(label='Team Id' required=false)
        public Id teamId;

        @InvocableVariable(label='Conference Name' required=false)
        public String conference;
    }

    @InvocableMethod(label='Ingest News for Teams' description='Uses Gemini AI to research and ingest news for teams')
    public static List<String> ingestNewsForTeams(List<IngestNewsRequest> requests) {
        List<String> results = new List<String>();

        for (IngestNewsRequest request : requests) {
            try {
                if (request.teamId != null) {
                    ingestNewsForTeamAsync(request.teamId);
                    results.add('News ingestion queued for team: ' + request.teamId);
                } else if (String.isNotBlank(request.conference)) {
                    ingestConferenceTournamentNewsAsync(request.conference);
                    results.add('Conference tournament news ingestion queued for: ' + request.conference);
                } else {
                    results.add('Error: Either teamId or conference must be provided');
                }
            } catch (Exception e) {
                results.add('Error: ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, 'NewsIngestionService.ingestNewsForTeams error: ' + e.getMessage());
            }
        }

        return results;
    }

    public static void ingestNewsForAllTeams(Id tournamentId) {
        List<Team__c> teams = [
            SELECT Id FROM Team__c
            WHERE Tournament__c = :tournamentId
            ORDER BY Seed__c ASC NULLS LAST
        ];

        for (Team__c team : teams) {
            ingestNewsForTeamAsync(team.Id);
        }
    }

    public static void ingestNewsForTeam(Id teamId) {
        Team__c team = [
            SELECT Id, Name, Conference__c, Record_Wins__c, Record_Losses__c,
                   Seed__c, Region__c, KenPom_Rating__c, NET_Ranking__c,
                   Strength_of_Schedule__c, Points_Per_Game__c, Opp_Points_Per_Game__c
            FROM Team__c
            WHERE Id = :teamId
            LIMIT 1
        ];

        // --- All callouts FIRST, before any DML ---
        String researchPrompt = TeamResearchPromptBuilder.buildTeamResearchWithBettingPrompt(team);
        GeminiAPIService.GeminiResponse researchResponse = GeminiAPIService.generateGroundedContent(researchPrompt);

        String groundedPrompt = TeamResearchPromptBuilder.buildGroundedNewsPrompt(team.Name);
        GeminiAPIService.GeminiResponse groundedResponse = GeminiAPIService.generateGroundedContent(groundedPrompt);

        // --- All DML AFTER callouts ---
        markExistingResearchNotCurrent(teamId);

        if (researchResponse.success) {
            Team_Research__c research = GeminiResponseParser.parseTeamResearch(researchResponse.text, teamId);
            if (researchResponse.hasGrounding()) {
                research.Raw_Response__c = appendGroundingSources(research.Raw_Response__c, researchResponse);
            }
            insert research;
        }

        if (groundedResponse.success) {
            List<News_Article__c> groundedArticles = GeminiResponseParser.parseGroundedNewsArticles(
                groundedResponse.text, teamId, groundedResponse.groundingSources
            );
            if (!groundedArticles.isEmpty()) {
                groundedArticles = deduplicateArticles(groundedArticles);
                insert groundedArticles;
            }
        }
    }

    public static void ingestGeneralNews() {
        List<News_Article__c> espnArticles = ESPNNewsService.fetchGeneralNews(25);
        if (!espnArticles.isEmpty()) {
            insert espnArticles;
            System.debug('Inserted ' + espnArticles.size() + ' ESPN general news articles');
        }
    }

    private static List<News_Article__c> deduplicateArticles(List<News_Article__c> articles) {
        Set<String> seen = new Set<String>();
        List<News_Article__c> unique = new List<News_Article__c>();
        for (News_Article__c a : articles) {
            String key = (a.Name ?? '').toLowerCase().replaceAll('[^a-z0-9]', '');
            if (key.length() > 40) key = key.substring(0, 40);
            if (!seen.contains(key) && String.isNotBlank(a.Name)) {
                seen.add(key);
                unique.add(a);
            }
        }
        return unique;
    }

    private static String appendGroundingSources(String existing, GeminiAPIService.GeminiResponse response) {
        String sources = '\n\n--- Grounding Sources ---\n';
        for (GeminiAPIService.GroundingSource src : response.groundingSources) {
            sources += '- ' + (src.title ?? 'Source') + ': ' + (src.uri ?? '') + '\n';
        }
        return (existing ?? '') + sources;
    }

    public static void ingestConferenceTournamentNews(String conference) {
        String prompt = TeamResearchPromptBuilder.buildConferenceTournamentPrompt(conference);
        GeminiAPIService.GeminiResponse response = GeminiAPIService.generateContent(prompt);

        if (!response.success) {
            System.debug(LoggingLevel.ERROR, 'NewsIngestionService conference news failed for ' + conference + ': ' + response.errorMessage);
            return;
        }

        try {
            String cleaned = stripCodeFences(response.text);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> results = (List<Object>) parsed.get('results');

            if (results == null) {
                return;
            }

            List<Team__c> teamsToUpdate = new List<Team__c>();

            Map<String, Team__c> teamsByName = buildTeamNameMap(conference);

            for (Object rawResult : results) {
                Map<String, Object> resultMap = (Map<String, Object>) rawResult;
                String teamName = (String) resultMap.get('teamName');
                String tournamentLikelihood = (String) resultMap.get('tournamentLikelihood');
                String resultStatus = (String) resultMap.get('result');

                Team__c matchedTeam = teamsByName.get(teamName?.toLowerCase());
                if (matchedTeam != null) {
                    matchedTeam.Conference_Tournament_Status__c = resultStatus;
                    if (String.isNotBlank(tournamentLikelihood)) {
                        try {
                            matchedTeam.Tournament_Likelihood__c = Decimal.valueOf(tournamentLikelihood);
                        } catch (Exception e) {
                            Map<String, Decimal> lkMap = new Map<String, Decimal>{
                                'lock' => 95, 'likely' => 80, 'bubble' => 50, 'unlikely' => 20, 'eliminated' => 0
                            };
                            Decimal pct = lkMap.get(tournamentLikelihood.toLowerCase());
                            if (pct != null) {
                                matchedTeam.Tournament_Likelihood__c = pct;
                            }
                        }
                    }
                    teamsToUpdate.add(matchedTeam);
                }
            }

            if (!teamsToUpdate.isEmpty()) {
                update teamsToUpdate;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'NewsIngestionService.ingestConferenceTournamentNews parse error: ' + e.getMessage());
        }
    }

    public static void updateTournamentLikelihood(Id teamId) {
        Team__c team = [
            SELECT Id, Name, Conference__c, Record_Wins__c, Record_Losses__c,
                   Seed__c, KenPom_Rating__c, NET_Ranking__c,
                   Conference_Tournament_Status__c, Tournament_Likelihood__c
            FROM Team__c
            WHERE Id = :teamId
            LIMIT 1
        ];

        String prompt = 'You are an NCAA basketball analyst. Based on the following team profile, '
            + 'assess their likelihood of making the NCAA tournament.\n\n'
            + 'Team: ' + team.Name + '\n'
            + 'Conference: ' + safeString(team.Conference__c) + '\n'
            + 'Record: ' + safeString(String.valueOf(team.Record_Wins__c)) + '-' + safeString(String.valueOf(team.Record_Losses__c)) + '\n'
            + 'NET Ranking: ' + (team.NET_Ranking__c != null ? String.valueOf(team.NET_Ranking__c.intValue()) : 'Unknown') + '\n'
            + 'KenPom Rating: ' + (team.KenPom_Rating__c != null ? String.valueOf(team.KenPom_Rating__c) : 'Unknown') + '\n'
            + 'Conference Tournament Status: ' + safeString(team.Conference_Tournament_Status__c) + '\n\n'
            + 'Respond with ONLY one of: "Lock", "Likely", "Bubble", "Unlikely", "Eliminated"';

        GeminiAPIService.GeminiResponse response = GeminiAPIService.generateContent(prompt);

        if (response.success && String.isNotBlank(response.text)) {
            String likelihood = response.text.trim().replaceAll('[^a-zA-Z]', '');
            Map<String, Decimal> likelihoodMap = new Map<String, Decimal>{
                'Lock' => 95, 'Likely' => 80, 'Bubble' => 50, 'Unlikely' => 20, 'Eliminated' => 0
            };

            if (likelihoodMap.containsKey(likelihood)) {
                team.Tournament_Likelihood__c = likelihoodMap.get(likelihood);
                update team;
            }
        }
    }

    @future(callout=true)
    private static void ingestNewsForTeamAsync(Id teamId) {
        ingestNewsForTeam(teamId);
    }

    @future(callout=true)
    private static void ingestConferenceTournamentNewsAsync(String conference) {
        ingestConferenceTournamentNews(conference);
    }

    private static void markExistingResearchNotCurrent(Id teamId) {
        List<Team_Research__c> existing = [
            SELECT Id FROM Team_Research__c
            WHERE Team__c = :teamId AND Is_Current__c = true
        ];

        for (Team_Research__c research : existing) {
            research.Is_Current__c = false;
        }

        if (!existing.isEmpty()) {
            update existing;
        }
    }

    private static Map<String, Team__c> buildTeamNameMap(String conference) {
        List<Team__c> teams = [
            SELECT Id, Name, Conference_Tournament_Status__c, Tournament_Likelihood__c
            FROM Team__c
            WHERE Conference__c = :conference
        ];

        Map<String, Team__c> teamMap = new Map<String, Team__c>();
        for (Team__c team : teams) {
            teamMap.put(team.Name.toLowerCase(), team);
        }
        return teamMap;
    }

    private static String stripCodeFences(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        Pattern p = Pattern.compile('```(?:json)?\\s*([\\s\\S]*?)\\s*```');
        Matcher m = p.matcher(input);
        if (m.find()) {
            return m.group(1).trim();
        }
        return input.trim();
    }

    private static String safeString(String value) {
        return String.isBlank(value) || value == 'null' ? 'Unknown' : value;
    }
}
