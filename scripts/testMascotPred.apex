Id gameId = 'a3FHp0000039F5KMAU';
Game__c g = [SELECT Team_1__r.Name, Team_1__r.Mascot__c, Team_2__r.Name, Team_2__r.Mascot__c FROM Game__c WHERE Id = :gameId];
System.debug('Mascot Battle: ' + g.Team_1__r.Name + ' (' + g.Team_1__r.Mascot__c + ') vs ' + g.Team_2__r.Name + ' (' + g.Team_2__r.Mascot__c + ')');

MascotPredictionEngine.predictAndSave(gameId);
Prediction__c p = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c, Prediction_Rationale__c FROM Prediction__c WHERE Game__c = :gameId AND Is_Current__c = true AND Model_Type__c = 'Mascot Battle' LIMIT 1];
System.debug('MASCOT BATTLE => Winner: ' + p.Predicted_Winner__r.Name + ' | Confidence: ' + p.Confidence_Score__c + '% | ModelType: ' + p.Model_Type__c);
System.debug('Rationale: ' + p.Prediction_Rationale__c);
