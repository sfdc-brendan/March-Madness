public with sharing class TeamResearchPromptBuilder {

    private static final String TEAM_RESEARCH_SCHEMA = '{'
        + '"type": "object",'
        + '"properties": {'
        + '  "recentPerformance": {"type": "string"},'
        + '  "keyPlayers": {"type": "array", "items": {"type": "string"}},'
        + '  "injuries": {"type": "string"},'
        + '  "strengths": {"type": "array", "items": {"type": "string"}},'
        + '  "weaknesses": {"type": "array", "items": {"type": "string"}},'
        + '  "tournamentOutlook": {"type": "string"},'
        + '  "sentimentScore": {"type": "integer", "minimum": -100, "maximum": 100},'
        + '  "confidenceLevel": {"type": "string", "enum": ["Low", "Medium", "High"]},'
        + '  "keyFactors": {"type": "array", "items": {"type": "string"}},'
        + '  "summary": {"type": "string"}'
        + '}'
        + '}';

    private static final String HEAD_TO_HEAD_SCHEMA = '{'
        + '"type": "object",'
        + '"properties": {'
        + '  "team1WinProbability": {"type": "number", "minimum": 0, "maximum": 1},'
        + '  "team2WinProbability": {"type": "number", "minimum": 0, "maximum": 1},'
        + '  "confidence": {"type": "number", "minimum": 0, "maximum": 1},'
        + '  "rationale": {"type": "string"},'
        + '  "keyFactors": {"type": "array", "items": {"type": "string"}},'
        + '  "statisticalFactors": {"type": "array", "items": {'
        + '    "type": "object",'
        + '    "properties": {'
        + '      "factorName": {"type": "string"},'
        + '      "team1Value": {"type": "number"},'
        + '      "team2Value": {"type": "number"},'
        + '      "weight": {"type": "number"},'
        + '      "category": {"type": "string"}'
        + '    }'
        + '  }}'
        + '}'
        + '}';

    private static final String NEWS_SEARCH_SCHEMA = '{'
        + '"type": "object",'
        + '"properties": {'
        + '  "articles": {"type": "array", "items": {'
        + '    "type": "object",'
        + '    "properties": {'
        + '      "title": {"type": "string"},'
        + '      "source": {"type": "string"},'
        + '      "sourceUrl": {"type": "string"},'
        + '      "imageUrl": {"type": "string"},'
        + '      "summary": {"type": "string"},'
        + '      "sentimentScore": {"type": "integer", "minimum": -100, "maximum": 100},'
        + '      "category": {"type": "string"},'
        + '      "relevanceScore": {"type": "number", "minimum": 0, "maximum": 100},'
        + '      "tags": {"type": "array", "items": {"type": "string"}}'
        + '    }'
        + '  }}'
        + '}'
        + '}';

    private static final String BETTING_LINES_SCHEMA = '{'
        + '"type": "object",'
        + '"properties": {'
        + '  "games": {"type": "array", "items": {'
        + '    "type": "object",'
        + '    "properties": {'
        + '      "team1Name": {"type": "string"},'
        + '      "team2Name": {"type": "string"},'
        + '      "spread": {"type": "number"},'
        + '      "overUnder": {"type": "number"},'
        + '      "team1Moneyline": {"type": "integer"},'
        + '      "team2Moneyline": {"type": "integer"},'
        + '      "source": {"type": "string"},'
        + '      "notes": {"type": "string"}'
        + '    }'
        + '  }}'
        + '}'
        + '}';

    private static final String CONFERENCE_TOURNEY_SCHEMA = '{'
        + '"type": "object",'
        + '"properties": {'
        + '  "conferenceName": {"type": "string"},'
        + '  "tournamentStatus": {"type": "string"},'
        + '  "results": {"type": "array", "items": {'
        + '    "type": "object",'
        + '    "properties": {'
        + '      "teamName": {"type": "string"},'
        + '      "result": {"type": "string"},'
        + '      "eliminated": {"type": "boolean"},'
        + '      "tournamentLikelihood": {"type": "string"}'
        + '    }'
        + '  }},'
        + '  "sentimentScore": {"type": "integer", "minimum": -100, "maximum": 100},'
        + '  "confidenceLevel": {"type": "string", "enum": ["Low", "Medium", "High"]},'
        + '  "keyFactors": {"type": "array", "items": {"type": "string"}},'
        + '  "summary": {"type": "string"}'
        + '}'
        + '}';

    public static String buildTeamResearchPrompt(Team__c team) {
        String today = Datetime.now().format('MMMM d, yyyy');
        String seasonYear = String.valueOf(Date.today().year());
        String prevYear = String.valueOf(Date.today().year() - 1);

        String prompt = 'You are an expert NCAA basketball analyst. Today is ' + today + '.\n'
            + 'CRITICAL: This is the ' + prevYear + '-' + seasonYear.right(2) + ' college basketball season. '
            + 'You must ONLY discuss the CURRENT ' + prevYear + '-' + seasonYear.right(2) + ' season rosters, '
            + 'coaches, records, and results. Do NOT reference any prior seasons, past tournament runs, or '
            + 'players/coaches who are no longer on this team.\n\n';

        prompt += 'Research the following team for the ' + seasonYear + ' NCAA March Madness tournament.\n\n';
        prompt += 'Team: ' + team.Name + '\n';
        prompt += 'Conference: ' + safeString(team.Conference__c) + '\n';
        prompt += 'Current ' + prevYear + '-' + seasonYear.right(2) + ' Record: '
            + safeString(String.valueOf(team.Record_Wins__c)) + '-'
            + safeString(String.valueOf(team.Record_Losses__c)) + '\n';

        if (team.Seed__c != null) {
            prompt += 'Seed: ' + String.valueOf(team.Seed__c.intValue()) + '\n';
        }
        if (team.Region__c != null) {
            prompt += 'Region: ' + team.Region__c + '\n';
        }
        if (team.KenPom_Rating__c != null) {
            prompt += 'KenPom Rating: ' + String.valueOf(team.KenPom_Rating__c) + '\n';
        }
        if (team.NET_Ranking__c != null) {
            prompt += 'NET Ranking: ' + String.valueOf(team.NET_Ranking__c.intValue()) + '\n';
        }

        prompt += '\nProvide a comprehensive analysis of THIS CURRENT ' + prevYear + '-' + seasonYear.right(2) + ' season including:\n';
        prompt += '1. Recent performance trends in the current season\n';
        prompt += '2. Key players currently on the roster and their impact this season\n';
        prompt += '3. Current injuries or player availability issues\n';
        prompt += '4. Team strengths this season\n';
        prompt += '5. Team weaknesses this season\n';
        prompt += '6. Tournament outlook and potential for ' + seasonYear + ' March Madness\n';
        prompt += '7. A sentiment score from -100 (very negative outlook) to 100 (very positive outlook)\n';
        prompt += '8. Your confidence level in this assessment (Low, Medium, High)\n';
        prompt += '9. The top key factors that will determine this team\'s tournament success\n\n';
        prompt += 'Respond ONLY with valid JSON matching this schema:\n' + TEAM_RESEARCH_SCHEMA;

        return prompt;
    }

    public static String buildHeadToHeadPrompt(Team__c team1, Team__c team2, String round) {
        String today = Datetime.now().format('MMMM d, yyyy');
        String seasonYear = String.valueOf(Date.today().year());
        String prevYear = String.valueOf(Date.today().year() - 1);

        String prompt = 'You are an expert NCAA basketball analyst. Today is ' + today + '.\n'
            + 'CRITICAL: This is the ' + prevYear + '-' + seasonYear.right(2) + ' season. '
            + 'Only reference current rosters, coaches, and this season\'s stats.\n\n';
        prompt += 'MATCHUP: ' + team1.Name + ' vs ' + team2.Name + '\n';
        prompt += 'Round: ' + safeString(round) + '\n\n';

        prompt += formatTeamDetails('Team 1', team1);
        prompt += formatTeamDetails('Team 2', team2);

        prompt += '\nAnalyze this matchup considering:\n';
        prompt += '- Historical seed performance in this round\n';
        prompt += '- Offensive and defensive efficiency\n';
        prompt += '- Strength of schedule and quality wins\n';
        prompt += '- Pace of play and style matchup\n';
        prompt += '- Momentum and recent form\n';
        prompt += '- Coaching experience in the tournament\n\n';
        prompt += 'Provide win probabilities that sum to 1.0, a confidence score, detailed rationale, and statistical factor comparisons.\n\n';
        prompt += 'Respond ONLY with valid JSON matching this schema:\n' + HEAD_TO_HEAD_SCHEMA;

        return prompt;
    }

    public static String buildConferenceTournamentPrompt(String conference) {
        String today = Datetime.now().format('MMMM d, yyyy');
        String seasonYear = String.valueOf(Date.today().year());
        String prevYear = String.valueOf(Date.today().year() - 1);

        String prompt = 'You are an expert NCAA basketball analyst. Today is ' + today + '.\n'
            + 'CRITICAL: This is the ' + prevYear + '-' + seasonYear.right(2) + ' season. '
            + 'Only discuss the current season\'s conference tournament.\n\n';
        prompt += 'Provide the latest information about the ';
        prompt += safeString(conference) + ' conference basketball tournament.\n\n';
        prompt += 'Include:\n';
        prompt += '1. Current tournament status (upcoming, in progress, completed)\n';
        prompt += '2. Results for each team that has played\n';
        prompt += '3. Which teams have been eliminated\n';
        prompt += '4. NCAA tournament likelihood for bubble teams\n';
        prompt += '5. A sentiment score from -100 to 100 for the conference overall\n';
        prompt += '6. Confidence level in the assessment\n';
        prompt += '7. Key factors affecting the conference\'s tournament representation\n\n';
        prompt += 'Respond ONLY with valid JSON matching this schema:\n' + CONFERENCE_TOURNEY_SCHEMA;

        return prompt;
    }

    public static String buildNewsSearchPrompt(String teamName) {
        String prompt = 'You are a sports news aggregator. Find and summarize the most recent and relevant news articles ';
        prompt += 'about the ' + safeString(teamName) + ' NCAA basketball team heading into March Madness.\n\n';
        prompt += 'Focus on:\n';
        prompt += '- Game results and upcoming schedule\n';
        prompt += '- Player injuries, suspensions, or transfers\n';
        prompt += '- Coaching changes or strategies\n';
        prompt += '- Conference tournament performance\n';
        prompt += '- NCAA tournament projections and bracket seeding\n';
        prompt += '- Any other relevant basketball news\n\n';
        prompt += 'For each article, provide: title, source name, source URL (if known), summary, ';
        prompt += 'sentiment score (-100 to 100), category (must be exactly one of: Game Recap, Injury Update, Conference Tournament, Expert Analysis, Bracket Projection, General News, Transfer Portal), ';
        prompt += 'relevance score (0-100), and tags.\n\n';
        prompt += 'Respond ONLY with valid JSON matching this schema:\n' + NEWS_SEARCH_SCHEMA;

        return prompt;
    }

    public static String buildBettingLinesPrompt(List<Game__c> games) {
        String prompt = 'You are a sports betting analyst with access to current NCAA March Madness betting lines. '
            + 'Provide the latest consensus betting lines for the following games.\n\n';

        for (Game__c game : games) {
            String t1 = game.Team_1__r != null ? game.Team_1__r.Name : 'TBD';
            String t2 = game.Team_2__r != null ? game.Team_2__r.Name : 'TBD';
            prompt += '- ' + t1 + ' vs ' + t2 + ' (' + safeString(game.Round__c) + ')\n';
        }

        prompt += '\nFor each game provide:\n';
        prompt += '1. Point spread (negative means team1 is favored)\n';
        prompt += '2. Over/Under total points line\n';
        prompt += '3. Moneyline for each team (American format, e.g., -150, +130)\n';
        prompt += '4. Source of the lines (DraftKings, FanDuel, consensus, etc.)\n';
        prompt += '5. Any notable line movement or notes\n\n';
        prompt += 'Use team1Name and team2Name exactly as listed above.\n\n';
        prompt += 'Respond ONLY with valid JSON matching this schema:\n' + BETTING_LINES_SCHEMA;

        return prompt;
    }

    public static String buildGroundedNewsPrompt(String teamName) {
        String today = Datetime.now().format('MMMM d, yyyy');
        String seasonYear = String.valueOf(Date.today().year());
        String prevYear = String.valueOf(Date.today().year() - 1);

        String prompt = 'Today is ' + today + '. Search for the latest real news articles about the '
            + safeString(teamName) + ' NCAA basketball team from the past 7 days.\n\n'
            + 'CRITICAL: Only include articles from the CURRENT ' + prevYear + '-' + seasonYear.right(2)
            + ' season. Do NOT include any articles from prior seasons or tournaments.\n\n'
            + 'Focus on: conference tournament games happening now in March ' + seasonYear + ', '
            + 'game results, injuries, bracket projections for ' + seasonYear + ' March Madness, '
            + 'and current roster/coaching news.\n\n'
            + 'IMPORTANT: Only include articles that you can find from real news sources with actual URLs. '
            + 'Do NOT fabricate or hallucinate any articles. If you cannot find enough real articles, '
            + 'return fewer articles rather than making them up.\n\n'
            + 'For each real article found, provide: title, source name, source URL, imageUrl (a direct URL to the '
            + 'article\'s header/thumbnail image if available - must be a real image URL ending in .jpg, .png, or .webp), '
            + 'a brief summary, sentiment score (-100 to 100), category (must be exactly one of: Game Recap, Injury Update, '
            + 'Conference Tournament, Expert Analysis, Bracket Projection, General News, Transfer Portal), '
            + 'relevance score (0-100), and tags.\n\n'
            + 'Respond ONLY with valid JSON matching this schema:\n' + NEWS_SEARCH_SCHEMA;
        return prompt;
    }

    public static String buildTeamResearchWithBettingPrompt(Team__c team) {
        String prompt = buildTeamResearchPrompt(team);
        prompt = prompt.replace(
            'Respond ONLY with valid JSON',
            'Also factor in any current betting market sentiment, futures odds for tournament advancement, '
            + 'and how the betting market views this team\'s chances.\n\nRespond ONLY with valid JSON'
        );
        return prompt;
    }

    private static String formatTeamDetails(String label, Team__c team) {
        String details = label + ': ' + team.Name + '\n';
        details += '  Seed: ' + (team.Seed__c != null ? String.valueOf(team.Seed__c.intValue()) : 'N/A') + '\n';
        details += '  Record: ' + safeString(String.valueOf(team.Record_Wins__c)) + '-' + safeString(String.valueOf(team.Record_Losses__c)) + '\n';
        details += '  Conference: ' + safeString(team.Conference__c) + '\n';

        if (team.KenPom_Rating__c != null) {
            details += '  KenPom: ' + String.valueOf(team.KenPom_Rating__c) + '\n';
        }
        if (team.NET_Ranking__c != null) {
            details += '  NET Ranking: ' + String.valueOf(team.NET_Ranking__c.intValue()) + '\n';
        }
        if (team.Strength_of_Schedule__c != null) {
            details += '  SOS: ' + String.valueOf(team.Strength_of_Schedule__c) + '\n';
        }
        if (team.Points_Per_Game__c != null) {
            details += '  PPG: ' + String.valueOf(team.Points_Per_Game__c) + '\n';
        }
        if (team.Opp_Points_Per_Game__c != null) {
            details += '  Opp PPG: ' + String.valueOf(team.Opp_Points_Per_Game__c) + '\n';
        }

        return details + '\n';
    }

    private static String safeString(String value) {
        return String.isBlank(value) || value == 'null' ? 'Unknown' : value;
    }
}
