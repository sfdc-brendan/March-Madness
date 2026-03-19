List<Team__c> teams = [SELECT Id, Name, Mascot__c FROM Team__c WHERE Seed__c != null];
List<Team__c> toFix = new List<Team__c>();

for (Team__c t : teams) {
    String correct = null;
    String n = t.Name;

    if (n == 'Arkansas Razorbacks') correct = 'Razorbacks';
    else if (n == 'Florida Atlantic Owls') correct = 'Owls';
    else if (n == 'Georgia Tech Yellow Jackets') correct = 'Yellow Jackets';
    else if (n == 'Indiana State Sycamores') correct = 'Sycamores';
    else if (n == 'Kansas State Wildcats') correct = 'Wildcats';
    else if (n == 'Northern Iowa Panthers') correct = 'Panthers';
    else if (n == 'South Florida Bulls') correct = 'Bulls';
    else if (n == 'Tennessee State Tigers') correct = 'Tigers';
    else if (n == 'Texas A&M Aggies') correct = 'Aggies';
    else if (n == 'Utah State Aggies') correct = 'Aggies';
    else if (n == 'Virginia Tech Hokies') correct = 'Hokies';

    if (correct != null && t.Mascot__c != correct) {
        t.Mascot__c = correct;
        toFix.add(t);
        System.debug('Fixed: ' + t.Name + ' => ' + correct);
    }
}

if (!toFix.isEmpty()) {
    update toFix;
}
System.debug('Fixed ' + toFix.size() + ' mascot assignments');
