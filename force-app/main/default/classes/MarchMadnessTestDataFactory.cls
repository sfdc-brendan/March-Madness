public class MarchMadnessTestDataFactory {

    public static Tournament__c createTournament() {
        Tournament__c t = new Tournament__c(
            Year__c = 2026,
            Status__c = 'Active',
            Start_Date__c = Date.newInstance(2026, 3, 17),
            End_Date__c = Date.newInstance(2026, 4, 7)
        );
        insert t;
        return t;
    }

    public static Team__c createTeam(Id tournamentId, String name, Integer seed, String region) {
        Team__c team = new Team__c(
            Name = name,
            Seed__c = seed,
            Region__c = region,
            Conference__c = 'Big 12',
            Tournament__c = tournamentId,
            Record_Wins__c = 28,
            Record_Losses__c = 5,
            KenPom_Rating__c = 22.5,
            NET_Ranking__c = 10,
            Strength_of_Schedule__c = 0.72,
            Points_Per_Game__c = 78.5,
            Opp_Points_Per_Game__c = 64.2,
            Overall_Power_Rating__c = 88.0,
            Last_10_Record__c = '8-2'
        );
        insert team;
        return team;
    }

    public static List<Team__c> createTeamPair(Id tournamentId, String region) {
        Team__c team1 = new Team__c(
            Name = region + ' Top Seed',
            Seed__c = 1,
            Region__c = region,
            Conference__c = 'ACC',
            Tournament__c = tournamentId,
            Record_Wins__c = 30,
            Record_Losses__c = 3,
            KenPom_Rating__c = 28.0,
            NET_Ranking__c = 3,
            Strength_of_Schedule__c = 0.80,
            Points_Per_Game__c = 82.0,
            Opp_Points_Per_Game__c = 61.5,
            Overall_Power_Rating__c = 94.0,
            Last_10_Record__c = '9-1'
        );

        Team__c team2 = new Team__c(
            Name = region + ' Bottom Seed',
            Seed__c = 16,
            Region__c = region,
            Conference__c = 'MEAC',
            Tournament__c = tournamentId,
            Record_Wins__c = 18,
            Record_Losses__c = 14,
            KenPom_Rating__c = -5.0,
            NET_Ranking__c = 200,
            Strength_of_Schedule__c = 0.30,
            Points_Per_Game__c = 65.0,
            Opp_Points_Per_Game__c = 72.0,
            Overall_Power_Rating__c = 35.0,
            Last_10_Record__c = '5-5'
        );

        insert new List<Team__c>{ team1, team2 };
        return new List<Team__c>{ team1, team2 };
    }

    public static Game__c createGame(Id tournamentId, Id team1Id, Id team2Id, String round, String region) {
        Game__c game = new Game__c(
            Tournament__c = tournamentId,
            Team_1__c = team1Id,
            Team_2__c = team2Id,
            Round__c = round,
            Region__c = region,
            Status__c = 'Scheduled',
            Game_Date__c = DateTime.now().addDays(1),
            Game_Number__c = Math.round(Math.random() * 10000),
            Bracket_Position__c = 1
        );
        insert game;
        return game;
    }

    public static Team_Research__c createResearch(Id teamId, Integer sentiment) {
        Team_Research__c research = new Team_Research__c(
            Team__c = teamId,
            Research_Date__c = DateTime.now(),
            Source_Type__c = 'Gemini AI',
            Summary__c = 'Test research summary for team analysis.',
            Sentiment_Score__c = sentiment,
            Key_Factors__c = 'Strong defense; Good three-point shooting; Experienced roster',
            Confidence_Level__c = 'High',
            Is_Current__c = true
        );
        insert research;
        return research;
    }

    public static News_Article__c createNewsArticle(Id teamId, String category) {
        News_Article__c article = new News_Article__c(
            Name = 'Test Article - ' + category,
            Team__c = teamId,
            Article_Date__c = DateTime.now(),
            Source__c = 'ESPN',
            Source_URL__c = 'https://espn.com/test',
            Summary__c = 'Test article summary about team performance.',
            Sentiment_Score__c = 75,
            Category__c = category,
            Is_Featured__c = false,
            Relevance_Score__c = 85,
            Tags__c = 'basketball,ncaa,tournament'
        );
        insert article;
        return article;
    }

    public static Prediction__c createPrediction(Id gameId, Id winnerId, Decimal confidence) {
        Prediction__c pred = new Prediction__c(
            Game__c = gameId,
            Predicted_Winner__c = winnerId,
            Confidence_Score__c = confidence,
            Team_1_Win_Probability__c = 50 + (confidence / 2),
            Team_2_Win_Probability__c = 50 - (confidence / 2),
            Prediction_Rationale__c = 'Test prediction rationale.',
            Model_Version__c = 'v1.0',
            Prediction_Date__c = DateTime.now(),
            Is_Current__c = true
        );
        insert pred;
        return pred;
    }
}
