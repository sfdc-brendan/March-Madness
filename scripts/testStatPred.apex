List<Game__c> games = [
    SELECT Id, Team_1__r.Name, Team_1__r.Seed__c, Team_2__r.Name, Team_2__r.Seed__c, Round__c
    FROM Game__c
    WHERE Round__c = 'Round of 64'
      AND Team_1__c != null AND Team_2__c != null
      AND Team_1__r.Name != 'TBD' AND Team_2__r.Name != 'TBD'
    ORDER BY Team_1__r.Seed__c ASC
    LIMIT 1
];
Game__c g = games[0];
System.debug('Game: ' + g.Team_1__r.Name + ' (' + g.Team_1__r.Seed__c + ') vs ' + g.Team_2__r.Name + ' (' + g.Team_2__r.Seed__c + ')');
System.debug('Game Id: ' + g.Id);

PredictionEngine.predictAndSave(g.Id);
Prediction__c p = [SELECT Predicted_Winner__r.Name, Confidence_Score__c, Model_Type__c FROM Prediction__c WHERE Game__c = :g.Id AND Is_Current__c = true AND Model_Type__c = 'Statistical' LIMIT 1];
System.debug('STATISTICAL => Winner: ' + p.Predicted_Winner__r.Name + ' | Confidence: ' + p.Confidence_Score__c + '% | ModelType: ' + p.Model_Type__c);
