// Queue AI Research predictions for first 10 round of 64 games
List<Game__c> games = [
    SELECT Id, Team_1__r.Name, Team_1__r.Seed__c, Team_2__r.Name, Team_2__r.Seed__c
    FROM Game__c
    WHERE Round__c = 'Round of 64'
      AND Team_1__c != null AND Team_2__c != null
      AND Team_1__r.Name != 'TBD' AND Team_2__r.Name != 'TBD'
      AND Id NOT IN (SELECT Game__c FROM Prediction__c WHERE Model_Type__c = 'AI Research' AND Is_Current__c = true)
    ORDER BY Team_1__r.Seed__c ASC
    LIMIT 10
];

System.debug('Found ' + games.size() + ' games needing AI Research predictions');
Integer queued = 0;
for (Game__c g : games) {
    System.debug('Queueing: ' + g.Team_1__r.Name + ' (' + g.Team_1__r.Seed__c + ') vs ' + g.Team_2__r.Name + ' (' + g.Team_2__r.Seed__c + ')');
    System.enqueueJob(new PredictionModelQueueable(g.Id, 'AI Research'));
    queued++;
}
System.debug('Queued ' + queued + ' AI Research predictions');
