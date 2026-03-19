Id gameId = 'a3FHp0000039F5KMAU';

AIPredictionEngine.predictAndSave(gameId);
Prediction__c p = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c, Prediction_Rationale__c FROM Prediction__c WHERE Game__c = :gameId AND Is_Current__c = true AND Model_Type__c = 'AI Research' LIMIT 1];
System.debug('AI RESEARCH => Winner: ' + p.Predicted_Winner__r.Name + ' | Confidence: ' + p.Confidence_Score__c + '% | ModelType: ' + p.Model_Type__c);
System.debug('Rationale: ' + p.Prediction_Rationale__c);

// Verify all 3 models exist for this game
Integer total = [SELECT COUNT() FROM Prediction__c WHERE Game__c = :gameId AND Is_Current__c = true];
System.debug('Total current predictions for this game: ' + total);
