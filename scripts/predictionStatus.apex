Integer statPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'Statistical'];
Integer mascotPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'Mascot Battle'];
Integer aiPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'AI Research'];
Integer nullPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = null];
Integer totalPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true];

System.debug('=== PREDICTION STATUS ===');
System.debug('Statistical: ' + statPreds);
System.debug('Mascot Battle: ' + mascotPreds);
System.debug('AI Research: ' + aiPreds);
System.debug('Legacy (null type): ' + nullPreds);
System.debug('TOTAL CURRENT: ' + totalPreds);

Integer totalR64 = [SELECT COUNT() FROM Game__c WHERE Round__c = 'Round of 64' AND Team_1__c != null AND Team_2__c != null AND Team_1__r.Name != 'TBD' AND Team_2__r.Name != 'TBD'];
System.debug('Total R64 games with both teams: ' + totalR64);
