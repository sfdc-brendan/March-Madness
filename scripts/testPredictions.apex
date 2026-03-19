// Get a single first-round game with both teams to test all 3 prediction models
List<Game__c> games = [
    SELECT Id, Team_1__r.Name, Team_1__r.Seed__c, Team_2__r.Name, Team_2__r.Seed__c, Round__c
    FROM Game__c
    WHERE Round__c = 'Round of 64'
      AND Team_1__c != null AND Team_2__c != null
      AND Team_1__r.Name != 'TBD' AND Team_2__r.Name != 'TBD'
    ORDER BY Team_1__r.Seed__c ASC
    LIMIT 1
];

if (games.isEmpty()) {
    System.debug('No eligible games found');
} else {
    Game__c testGame = games[0];
    System.debug('Testing all 3 models on: ' + testGame.Team_1__r.Name + ' (' + testGame.Team_1__r.Seed__c + ') vs ' + testGame.Team_2__r.Name + ' (' + testGame.Team_2__r.Seed__c + ') - ' + testGame.Round__c);

    // Model 1: Statistical
    PredictionEngine.predictAndSave(testGame.Id);
    Prediction__c statPred = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c FROM Prediction__c WHERE Game__c = :testGame.Id AND Is_Current__c = true AND Model_Type__c = 'Statistical' LIMIT 1];
    System.debug('STATISTICAL => Winner: ' + statPred.Predicted_Winner__r.Name + ' | Confidence: ' + statPred.Confidence_Score__c + '%');

    // Model 2: Mascot Battle (callout)
    MascotPredictionEngine.predictAndSave(testGame.Id);
    Prediction__c mascotPred = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c FROM Prediction__c WHERE Game__c = :testGame.Id AND Is_Current__c = true AND Model_Type__c = 'Mascot Battle' LIMIT 1];
    System.debug('MASCOT BATTLE => Winner: ' + mascotPred.Predicted_Winner__r.Name + ' | Confidence: ' + mascotPred.Confidence_Score__c + '%');

    // Model 3: AI Research (callout)
    AIPredictionEngine.predictAndSave(testGame.Id);
    Prediction__c aiPred = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c FROM Prediction__c WHERE Game__c = :testGame.Id AND Is_Current__c = true AND Model_Type__c = 'AI Research' LIMIT 1];
    System.debug('AI RESEARCH => Winner: ' + aiPred.Predicted_Winner__r.Name + ' | Confidence: ' + aiPred.Confidence_Score__c + '%');

    // Summary
    Integer totalPreds = [SELECT COUNT() FROM Prediction__c WHERE Game__c = :testGame.Id AND Is_Current__c = true];
    System.debug('Total current predictions for this game: ' + totalPreds);
}
