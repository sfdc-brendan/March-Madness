public with sharing class MascotPredictionEngine {

    public static final String MODEL_TYPE = 'Mascot Battle';
    private static final String MODEL_VERSION = 'mascot-v1.0';

    public static Prediction__c predictGame(Id gameId) {
        Game__c game = [
            SELECT Id, Round__c, Region__c,
                Team_1__c, Team_1__r.Name, Team_1__r.Seed__c, Team_1__r.Mascot__c,
                Team_1__r.Primary_Color__c, Team_1__r.Logo_URL__c,
                Team_2__c, Team_2__r.Name, Team_2__r.Seed__c, Team_2__r.Mascot__c,
                Team_2__r.Primary_Color__c, Team_2__r.Logo_URL__c
            FROM Game__c
            WHERE Id = :gameId
            LIMIT 1
        ];

        if (game.Team_1__c == null || game.Team_2__c == null) {
            throw new MascotPredictionException('Both teams must be set before running mascot predictions');
        }

        String mascot1 = String.isNotBlank(game.Team_1__r.Mascot__c)
            ? game.Team_1__r.Mascot__c : extractMascot(game.Team_1__r.Name);
        String mascot2 = String.isNotBlank(game.Team_2__r.Mascot__c)
            ? game.Team_2__r.Mascot__c : extractMascot(game.Team_2__r.Name);

        String prompt = buildPrompt(
            game.Team_1__r.Name, mascot1, game.Team_1__r.Seed__c,
            game.Team_2__r.Name, mascot2, game.Team_2__r.Seed__c,
            game.Round__c, game.Region__c
        );

        String schema = buildResponseSchema();
        GeminiAPIService.GeminiResponse response = GeminiAPIService.generateStructuredContent(prompt, schema);

        if (!response.success) {
            throw new MascotPredictionException('Gemini API call failed: ' + response.errorMessage);
        }

        return parsePrediction(response.text, game, mascot1, mascot2);
    }

    public static void predictAndSave(Id gameId) {
        Prediction__c prediction = predictGame(gameId);

        List<Prediction__c> existing = [
            SELECT Id FROM Prediction__c
            WHERE Game__c = :gameId AND Is_Current__c = true AND Model_Type__c = :MODEL_TYPE
        ];
        for (Prediction__c p : existing) {
            p.Is_Current__c = false;
        }
        if (!existing.isEmpty()) {
            update existing;
        }

        insert prediction;
    }

    private static String buildPrompt(String team1, String mascot1, Decimal seed1,
                                       String team2, String mascot2, Decimal seed2,
                                       String round, String region) {
        String seedInfo1 = seed1 != null ? ' (#' + Integer.valueOf(seed1) + ' seed)' : '';
        String seedInfo2 = seed2 != null ? ' (#' + Integer.valueOf(seed2) + ' seed)' : '';

        return 'You are an expert at analyzing hypothetical mascot battles for March Madness entertainment.\n\n'
            + 'MATCHUP: ' + team1 + seedInfo1 + ' (' + mascot1 + ') vs '
            + team2 + seedInfo2 + ' (' + mascot2 + ')\n'
            + 'ROUND: ' + (String.isNotBlank(round) ? round : 'Tournament Game') + '\n'
            + 'REGION: ' + (String.isNotBlank(region) ? region : 'N/A') + '\n\n'
            + 'Imagine these two mascots facing off in an epic battle. Consider:\n'
            + '- Physical attributes: size, strength, speed, agility\n'
            + '- Special abilities: natural weapons (claws, horns, venom), supernatural powers\n'
            + '- Intelligence and cunning\n'
            + '- Historical/mythological significance\n'
            + '- Home turf advantage based on region\n'
            + '- Tournament momentum (higher seeds get slight morale boost)\n\n'
            + 'Be creative and entertaining! This is meant to be fun.\n'
            + 'Provide a vivid play-by-play narrative of the battle.\n'
            + 'The winner of the mascot battle predicts the basketball game winner.\n\n'
            + 'IMPORTANT: Return valid JSON matching the schema exactly.';
    }

    private static String buildResponseSchema() {
        Map<String, Object> schema = new Map<String, Object>{
            'type' => 'object',
            'properties' => new Map<String, Object>{
                'winner' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Name of the winning team (must exactly match one of the team names provided)'
                },
                'winnerMascot' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'Name of the winning mascot'
                },
                'winProbability' => new Map<String, Object>{
                    'type' => 'number',
                    'description' => 'Win probability for the winning team (50-95)'
                },
                'battleNarrative' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'A vivid 3-4 sentence narrative of the mascot battle with dramatic flair'
                },
                'mascot1Power' => new Map<String, Object>{
                    'type' => 'number',
                    'description' => 'Power rating for mascot 1 (1-100)'
                },
                'mascot2Power' => new Map<String, Object>{
                    'type' => 'number',
                    'description' => 'Power rating for mascot 2 (1-100)'
                },
                'keyAdvantage' => new Map<String, Object>{
                    'type' => 'string',
                    'description' => 'The single biggest advantage the winning mascot had'
                }
            },
            'required' => new List<String>{
                'winner', 'winnerMascot', 'winProbability', 'battleNarrative',
                'mascot1Power', 'mascot2Power', 'keyAdvantage'
            }
        };
        return JSON.serialize(schema);
    }

    private static Prediction__c parsePrediction(String jsonText, Game__c game,
                                                  String mascot1, String mascot2) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(jsonText);

        String winner = (String) result.get('winner');
        Decimal winProb = toDecimal(result.get('winProbability'));
        String narrative = (String) result.get('battleNarrative');
        Decimal m1Power = toDecimal(result.get('mascot1Power'));
        Decimal m2Power = toDecimal(result.get('mascot2Power'));
        String keyAdv = (String) result.get('keyAdvantage');

        Id winnerId;
        if (winner != null && winner.containsIgnoreCase(game.Team_1__r.Name)) {
            winnerId = game.Team_1__c;
        } else if (winner != null && winner.containsIgnoreCase(game.Team_2__r.Name)) {
            winnerId = game.Team_2__c;
        } else {
            winnerId = m1Power >= m2Power ? game.Team_1__c : game.Team_2__c;
        }

        Boolean team1Wins = winnerId == game.Team_1__c;
        Decimal t1Prob = team1Wins ? winProb : (100 - winProb);
        Decimal t2Prob = 100 - t1Prob;
        Decimal confidence = Math.abs(t1Prob - 50) * 2;

        String rationale = buildRationale(
            game.Team_1__r.Name, mascot1, m1Power,
            game.Team_2__r.Name, mascot2, m2Power,
            narrative, keyAdv, team1Wins ? game.Team_1__r.Name : game.Team_2__r.Name
        );

        Prediction__c pred = new Prediction__c();
        pred.Game__c = game.Id;
        pred.Predicted_Winner__c = winnerId;
        pred.Team_1_Win_Probability__c = t1Prob.setScale(1);
        pred.Team_2_Win_Probability__c = t2Prob.setScale(1);
        pred.Confidence_Score__c = confidence.setScale(1);
        pred.Prediction_Rationale__c = rationale;
        pred.Model_Version__c = MODEL_VERSION;
        pred.Model_Type__c = MODEL_TYPE;
        pred.Prediction_Date__c = DateTime.now();
        pred.Is_Current__c = true;
        return pred;
    }

    private static String buildRationale(String team1, String mascot1, Decimal m1Power,
                                          String team2, String mascot2, Decimal m2Power,
                                          String narrative, String keyAdv, String winnerName) {
        String r = '<div class="mascot-battle-rationale">';
        r += '<h3>⚔️ Mascot Battle: ' + mascot1 + ' vs ' + mascot2 + '</h3>';
        r += '<p><strong>Winner: ' + winnerName + '</strong></p>';
        r += '<div class="battle-narrative">' + narrative + '</div>';
        r += '<div class="power-ratings">';
        r += '<p>' + team1 + ' (' + mascot1 + '): Power ' + m1Power + '/100</p>';
        r += '<p>' + team2 + ' (' + mascot2 + '): Power ' + m2Power + '/100</p>';
        r += '</div>';
        r += '<p><strong>Decisive Factor:</strong> ' + keyAdv + '</p>';
        r += '</div>';
        return r;
    }

    @TestVisible
    private static String extractMascot(String teamName) {
        if (String.isBlank(teamName)) return 'Unknown';

        Map<String, String> knownMascots = new Map<String, String>{
            'Duke' => 'Blue Devils', 'North Carolina' => 'Tar Heels', 'Kentucky' => 'Wildcats',
            'Kansas' => 'Jayhawks', 'Gonzaga' => 'Bulldogs', 'Villanova' => 'Wildcats',
            'Michigan State' => 'Spartans', 'UCLA' => 'Bruins', 'Arizona' => 'Wildcats',
            'UConn' => 'Huskies', 'Purdue' => 'Boilermakers', 'Houston' => 'Cougars',
            'Tennessee' => 'Volunteers', 'Alabama' => 'Crimson Tide', 'Auburn' => 'Tigers',
            'Iowa State' => 'Cyclones', 'Baylor' => 'Bears', 'Creighton' => 'Bluejays',
            'Marquette' => 'Golden Eagles', 'Texas Tech' => 'Red Raiders',
            'Michigan' => 'Wolverines', 'Wisconsin' => 'Badgers', 'Illinois' => 'Fighting Illini',
            'Oregon' => 'Ducks', 'Florida' => 'Gators', 'Arkansas' => 'Razorbacks',
            'LSU' => 'Tigers', 'Memphis' => 'Tigers', 'Cincinnati' => 'Bearcats',
            'San Diego State' => 'Aztecs', 'St. Mary\'s' => 'Gaels',
            'Clemson' => 'Tigers', 'Iowa' => 'Hawkeyes', 'BYU' => 'Cougars',
            'Texas' => 'Longhorns', 'Ohio State' => 'Buckeyes', 'Indiana' => 'Hoosiers',
            'Syracuse' => 'Orange', 'Georgetown' => 'Hoyas', 'Louisville' => 'Cardinals',
            'NC State' => 'Wolfpack', 'Virginia' => 'Cavaliers', 'Maryland' => 'Terrapins',
            'Xavier' => 'Musketeers', 'Pittsburgh' => 'Panthers', 'Florida State' => 'Seminoles',
            'Oklahoma' => 'Sooners', 'Texas A&M' => 'Aggies', 'Missouri' => 'Tigers',
            'Colorado' => 'Buffaloes', 'Nevada' => 'Wolf Pack', 'VCU' => 'Rams',
            'Davidson' => 'Wildcats', 'Loyola Chicago' => 'Ramblers',
            'Drake' => 'Bulldogs', 'Dayton' => 'Flyers', 'Wichita State' => 'Shockers',
            'Butler' => 'Bulldogs', 'Saint Louis' => 'Billikens',
            'Grand Canyon' => 'Antelopes', 'New Mexico' => 'Lobos',
            'Mississippi State' => 'Bulldogs', 'Ole Miss' => 'Rebels',
            'South Carolina' => 'Gamecocks', 'Georgia' => 'Bulldogs',
            'Northwestern' => 'Wildcats', 'Nebraska' => 'Cornhuskers',
            'Minnesota' => 'Golden Gophers', 'Penn State' => 'Nittany Lions',
            'Rutgers' => 'Scarlet Knights', 'Stanford' => 'Cardinal',
            'Washington' => 'Huskies', 'USC' => 'Trojans', 'Colorado State' => 'Rams',
            'Utah State' => 'Aggies', 'Boise State' => 'Broncos',
            'Liberty' => 'Flames', 'Oral Roberts' => 'Golden Eagles',
            'Akron' => 'Zips', 'Robert Morris' => 'Colonials',
            'Montana State' => 'Bobcats', 'Colgate' => 'Raiders',
            'UNC Wilmington' => 'Seahawks', 'Morehead State' => 'Eagles',
            'Norfolk State' => 'Spartans', 'Wagner' => 'Seahawks',
            'Long Beach State' => 'Beach', 'Stetson' => 'Hatters',
            'Grambling' => 'Tigers', 'Howard' => 'Bison'
        };

        for (String key : knownMascots.keySet()) {
            if (teamName.containsIgnoreCase(key)) {
                return knownMascots.get(key);
            }
        }

        List<String> parts = teamName.split(' ');
        return parts.size() > 1 ? parts[parts.size() - 1] : teamName;
    }

    private static Decimal toDecimal(Object val) {
        if (val == null) return 50;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        if (val instanceof Double) return Decimal.valueOf((Double) val);
        try { return Decimal.valueOf(String.valueOf(val)); } catch (Exception e) { return 50; }
    }

    public class MascotPredictionException extends Exception {}
}
