List<Prediction__c> legacy = [
    SELECT Id, Model_Type__c FROM Prediction__c
    WHERE Is_Current__c = true AND Model_Type__c = null
];
for (Prediction__c p : legacy) {
    p.Model_Type__c = 'Statistical';
}
if (!legacy.isEmpty()) {
    update legacy;
}
System.debug('Updated ' + legacy.size() + ' legacy predictions to Statistical type');

// Verify
Integer statPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'Statistical'];
Integer mascotPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'Mascot Battle'];
Integer aiPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = 'AI Research'];
Integer nullPreds = [SELECT COUNT() FROM Prediction__c WHERE Is_Current__c = true AND Model_Type__c = null];
System.debug('=== FINAL STATUS ===');
System.debug('Statistical: ' + statPreds);
System.debug('Mascot Battle: ' + mascotPreds);
System.debug('AI Research: ' + aiPreds);
System.debug('Null: ' + nullPreds);
System.debug('TOTAL: ' + (statPreds + mascotPreds + aiPreds + nullPreds));
