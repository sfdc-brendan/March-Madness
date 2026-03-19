Map<String, String> mascotMap = new Map<String, String>();
mascotMap.put('Duke', 'Blue Devils');
mascotMap.put('North Carolina', 'Tar Heels');
mascotMap.put('Kentucky', 'Wildcats');
mascotMap.put('Kansas', 'Jayhawks');
mascotMap.put('Gonzaga', 'Bulldogs');
mascotMap.put('Arizona', 'Wildcats');
mascotMap.put('UConn', 'Huskies');
mascotMap.put('Connecticut', 'Huskies');
mascotMap.put('Purdue', 'Boilermakers');
mascotMap.put('Houston', 'Cougars');
mascotMap.put('Tennessee', 'Volunteers');
mascotMap.put('Alabama', 'Crimson Tide');
mascotMap.put('Auburn', 'Tigers');
mascotMap.put('Iowa State', 'Cyclones');
mascotMap.put('Baylor', 'Bears');
mascotMap.put('Creighton', 'Bluejays');
mascotMap.put('Marquette', 'Golden Eagles');
mascotMap.put('Texas Tech', 'Red Raiders');
mascotMap.put('Michigan State', 'Spartans');
mascotMap.put('UCLA', 'Bruins');
mascotMap.put('Michigan', 'Wolverines');
mascotMap.put('Wisconsin', 'Badgers');
mascotMap.put('Illinois', 'Fighting Illini');
mascotMap.put('Oregon', 'Ducks');
mascotMap.put('Florida', 'Gators');
mascotMap.put('Arkansas', 'Razorbacks');
mascotMap.put('LSU', 'Tigers');
mascotMap.put('Memphis', 'Tigers');
mascotMap.put('Cincinnati', 'Bearcats');
mascotMap.put('San Diego State', 'Aztecs');
mascotMap.put('Clemson', 'Tigers');
mascotMap.put('Iowa', 'Hawkeyes');
mascotMap.put('BYU', 'Cougars');
mascotMap.put('Texas', 'Longhorns');
mascotMap.put('Ohio State', 'Buckeyes');
mascotMap.put('Indiana', 'Hoosiers');
mascotMap.put('Louisville', 'Cardinals');
mascotMap.put('NC State', 'Wolfpack');
mascotMap.put('Virginia', 'Cavaliers');
mascotMap.put('Maryland', 'Terrapins');
mascotMap.put('Xavier', 'Musketeers');
mascotMap.put('Pittsburgh', 'Panthers');
mascotMap.put('Oklahoma', 'Sooners');
mascotMap.put('Texas A&M', 'Aggies');
mascotMap.put('Missouri', 'Tigers');
mascotMap.put('Colorado', 'Buffaloes');
mascotMap.put('Nevada', 'Wolf Pack');
mascotMap.put('VCU', 'Rams');
mascotMap.put('Davidson', 'Wildcats');
mascotMap.put('Grand Canyon', 'Antelopes');
mascotMap.put('New Mexico', 'Lobos');
mascotMap.put('Mississippi State', 'Bulldogs');
mascotMap.put('Ole Miss', 'Rebels');
mascotMap.put('South Carolina', 'Gamecocks');
mascotMap.put('Georgia', 'Bulldogs');
mascotMap.put('Northwestern', 'Wildcats');
mascotMap.put('Penn State', 'Nittany Lions');
mascotMap.put('Rutgers', 'Scarlet Knights');
mascotMap.put('Stanford', 'Cardinal');
mascotMap.put('Washington', 'Huskies');
mascotMap.put('USC', 'Trojans');
mascotMap.put('Boise State', 'Broncos');
mascotMap.put('Liberty', 'Flames');
mascotMap.put('Oral Roberts', 'Golden Eagles');
mascotMap.put('Akron', 'Zips');
mascotMap.put('Robert Morris', 'Colonials');
mascotMap.put('Colgate', 'Raiders');
mascotMap.put('Morehead State', 'Eagles');
mascotMap.put('Norfolk State', 'Spartans');
mascotMap.put('Wagner', 'Seahawks');
mascotMap.put('Stetson', 'Hatters');
mascotMap.put('Grambling', 'Tigers');
mascotMap.put('Howard', 'Bison');
mascotMap.put('Saint Mary', 'Gaels');
mascotMap.put('St. John', 'Red Storm');
mascotMap.put('Villanova', 'Wildcats');
mascotMap.put('Providence', 'Friars');
mascotMap.put('Georgetown', 'Hoyas');
mascotMap.put('Syracuse', 'Orange');
mascotMap.put('Wake Forest', 'Demon Deacons');
mascotMap.put('Virginia Tech', 'Hokies');
mascotMap.put('Notre Dame', 'Fighting Irish');
mascotMap.put('West Virginia', 'Mountaineers');
mascotMap.put('TCU', 'Horned Frogs');
mascotMap.put('Kansas State', 'Wildcats');
mascotMap.put('UCF', 'Knights');
mascotMap.put('SMU', 'Mustangs');
mascotMap.put('Utah', 'Utes');
mascotMap.put('Arizona State', 'Sun Devils');
mascotMap.put('Oregon State', 'Beavers');
mascotMap.put('High Point', 'Panthers');
mascotMap.put('Troy', 'Trojans');
mascotMap.put('McNeese', 'Cowboys');
mascotMap.put('Omaha', 'Mavericks');
mascotMap.put('Yale', 'Bulldogs');
mascotMap.put('Northern Kentucky', 'Norse');
mascotMap.put('Drake', 'Bulldogs');
mascotMap.put('Lipscomb', 'Bisons');
mascotMap.put('Wofford', 'Terriers');
mascotMap.put('Montana State', 'Bobcats');
mascotMap.put('Dayton', 'Flyers');
mascotMap.put('Nebraska', 'Cornhuskers');
mascotMap.put('Minnesota', 'Golden Gophers');

List<Team__c> teams = [SELECT Id, Name, Mascot__c FROM Team__c WHERE Seed__c != null];
List<Team__c> toUpdate = new List<Team__c>();

for (Team__c t : teams) {
    String mascot = null;
    for (String key : mascotMap.keySet()) {
        if (t.Name.containsIgnoreCase(key)) {
            mascot = mascotMap.get(key);
            break;
        }
    }
    if (mascot != null && t.Mascot__c != mascot) {
        t.Mascot__c = mascot;
        toUpdate.add(t);
    }
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
}
System.debug('Updated mascots for ' + toUpdate.size() + ' teams');
for (Team__c t : toUpdate) {
    System.debug('  ' + t.Name + ' => ' + t.Mascot__c);
}
