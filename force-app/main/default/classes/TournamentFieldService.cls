public with sharing class TournamentFieldService {

    private static final Integer BATCH_SIZE = 25;

    private static final String TEAM_SCHEMA = '{'
        + '"type":"object","properties":{'
        + '"teams":{"type":"array","items":{"type":"object","properties":{'
        + '"name":{"type":"string"},'
        + '"conference":{"type":"string"},'
        + '"wins":{"type":"integer"},'
        + '"losses":{"type":"integer"},'
        + '"ppg":{"type":"number"},'
        + '"oppg":{"type":"number"},'
        + '"kenpom":{"type":"number"},'
        + '"netRanking":{"type":"integer"},'
        + '"sos":{"type":"number"},'
        + '"projectedSeed":{"type":"integer"},'
        + '"last10":{"type":"string"},'
        + '"tournamentLikelihood":{"type":"string"},'
        + '"powerRating":{"type":"number"}'
        + '}}}'
        + '}}';

    @InvocableMethod(label='Load Projected Tournament Field' description='Uses Gemini AI to populate the projected tournament field')
    public static List<String> loadProjectedField(List<Id> tournamentIds) {
        List<String> results = new List<String>();
        for (Id tId : tournamentIds) {
            Integer count = loadField(tId);
            results.add('Loaded/updated ' + count + ' projected tournament teams.');
        }
        return results;
    }

    public static Integer loadField(Id tournamentId) {
        Map<String, Team__c> existingByName = buildExistingTeamMap(tournamentId);

        Integer totalUpdated = 0;
        Integer totalTeams = 68;
        Integer batches = (Integer) Math.ceil((Decimal) totalTeams / BATCH_SIZE);

        for (Integer i = 0; i < batches; i++) {
            Integer startRank = (i * BATCH_SIZE) + 1;
            Integer endRank = Math.min((i + 1) * BATCH_SIZE, totalTeams);

            String prompt = buildBatchPrompt(BATCH_SIZE, i + 1, batches, startRank, endRank);

            GeminiAPIService.GeminiResponse resp = GeminiAPIService.generateContent(prompt);
            if (resp.success && String.isNotBlank(resp.text)) {
                Integer updated = parseAndUpsertTeams(resp.text, tournamentId, existingByName);
                totalUpdated += updated;
                System.debug('Batch ' + (i + 1) + ': updated ' + updated + ' teams.');
            } else {
                System.debug(LoggingLevel.WARN, 'Batch ' + (i + 1) + ' failed: ' + resp.errorMessage);
            }
        }

        return totalUpdated;
    }

    public static Integer loadFieldSingleBatch(Id tournamentId, Integer count) {
        Map<String, Team__c> existingByName = buildExistingTeamMap(tournamentId);
        String prompt = buildBatchPrompt(count, 1, 1, 1, count);

        GeminiAPIService.GeminiResponse resp = GeminiAPIService.generateContent(prompt);
        if (resp.success && String.isNotBlank(resp.text)) {
            return parseAndUpsertTeams(resp.text, tournamentId, existingByName);
        }

        System.debug(LoggingLevel.ERROR, 'Failed to load field: ' + resp.errorMessage);
        return 0;
    }

    private static String buildBatchPrompt(Integer batchSize, Integer batchNum, Integer totalBatches, Integer startRank, Integer endRank) {
        String prompt = 'You are an NCAA basketball expert. It is March 2026 and Selection Sunday is approaching.\n\n'
            + 'List the next ' + batchSize + ' teams most likely to be in the 2026 NCAA Men\'s Basketball Tournament. '
            + 'Include all projected at-large bids and likely automatic qualifiers from major and mid-major conferences.\n\n'
            + 'For each team provide:\n'
            + '- name: The full ESPN-style team name (e.g., "Duke Blue Devils", "North Carolina Tar Heels", "Gonzaga Bulldogs")\n'
            + '- conference: Conference name\n'
            + '- wins: Season wins\n'
            + '- losses: Season losses\n'
            + '- ppg: Points per game\n'
            + '- oppg: Opponent points per game\n'
            + '- kenpom: KenPom adjusted efficiency margin (typically between -5 and 35)\n'
            + '- netRanking: NET ranking (1 = best)\n'
            + '- sos: Strength of schedule (0.0 to 1.0 scale)\n'
            + '- projectedSeed: Projected tournament seed (1-16)\n'
            + '- last10: Last 10 games record (e.g., "8-2")\n'
            + '- tournamentLikelihood: "Lock", "Likely", or "Bubble"\n'
            + '- powerRating: Overall power rating 0-100\n\n'
            + 'Respond ONLY with valid JSON matching this schema:\n' + TEAM_SCHEMA + '\n\n'
            + 'This is batch ' + batchNum + ' of ' + totalBatches
            + ': Return teams ranked approximately ' + startRank + ' through ' + endRank + ' by projected seed/overall strength.';
        return prompt;
    }

    private static Map<String, Team__c> buildExistingTeamMap(Id tournamentId) {
        Map<String, Team__c> byName = new Map<String, Team__c>();
        for (Team__c t : [SELECT Id, Name FROM Team__c WHERE Tournament__c = :tournamentId]) {
            byName.put(t.Name.toLowerCase(), t);
        }
        return byName;
    }

    public static Integer parseAndUpsertTeams(String jsonResponse, Id tournamentId, Map<String, Team__c> existingByName) {
        try {
            String cleaned = GeminiResponseParser.cleanJsonResponse(jsonResponse);
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            List<Object> teamList = (List<Object>) parsed.get('teams');

            if (teamList == null || teamList.isEmpty()) {
                return 0;
            }

            List<Team__c> toUpsert = new List<Team__c>();

            for (Object obj : teamList) {
                Map<String, Object> td = (Map<String, Object>) obj;
                String name = (String) td.get('name');
                if (String.isBlank(name)) continue;

                Team__c team = findOrCreate(name, tournamentId, existingByName);

                team.Conference__c = (String) td.get('conference');
                team.Record_Wins__c = toDecimal(td.get('wins'));
                team.Record_Losses__c = toDecimal(td.get('losses'));
                team.Points_Per_Game__c = toDecimal(td.get('ppg'));
                team.Opp_Points_Per_Game__c = toDecimal(td.get('oppg'));
                team.KenPom_Rating__c = toDecimal(td.get('kenpom'));
                team.NET_Ranking__c = toDecimal(td.get('netRanking'));
                team.Strength_of_Schedule__c = toDecimal(td.get('sos'));
                team.Seed__c = toDecimal(td.get('projectedSeed'));
                team.Last_10_Record__c = (String) td.get('last10');
                String likelihood = (String) td.get('tournamentLikelihood');
                if (likelihood == 'Lock') {
                    team.Tournament_Likelihood__c = 95;
                } else if (likelihood == 'Likely') {
                    team.Tournament_Likelihood__c = 75;
                } else if (likelihood == 'Bubble') {
                    team.Tournament_Likelihood__c = 50;
                }
                team.Overall_Power_Rating__c = toDecimal(td.get('powerRating'));

                toUpsert.add(team);
            }

            if (!toUpsert.isEmpty()) {
                upsert toUpsert;
            }

            return toUpsert.size();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'TournamentFieldService parse error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return 0;
        }
    }

    private static Team__c findOrCreate(String name, Id tournamentId, Map<String, Team__c> existingByName) {
        String lowerName = name.toLowerCase();

        if (existingByName.containsKey(lowerName)) {
            return existingByName.get(lowerName);
        }

        for (String key : existingByName.keySet()) {
            if (fuzzyMatch(lowerName, key)) {
                return existingByName.get(key);
            }
        }

        Team__c newTeam = new Team__c(Name = name, Tournament__c = tournamentId);
        existingByName.put(lowerName, newTeam);
        return newTeam;
    }

    @TestVisible
    private static Boolean fuzzyMatch(String a, String b) {
        if (a.contains(b) || b.contains(a)) return true;

        String coreA = a.replaceAll('[^a-z]', '');
        String coreB = b.replaceAll('[^a-z]', '');
        if (coreA.length() > 5 && coreB.length() > 5) {
            if (coreA.contains(coreB) || coreB.contains(coreA)) return true;
        }

        return false;
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}
