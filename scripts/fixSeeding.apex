// Comprehensive seeding fix based on official bracket
// Map: team display name pattern -> { seed, region }

Map<String, Map<String, Object>> corrections = new Map<String, Map<String, Object>>();

// EAST
corrections.put('Duke Blue Devils', new Map<String, Object>{ 'seed' => 1, 'region' => 'East' });
corrections.put('UConn Huskies', new Map<String, Object>{ 'seed' => 2, 'region' => 'East' });
corrections.put('Michigan State Spartans', new Map<String, Object>{ 'seed' => 3, 'region' => 'East' });
corrections.put('Kansas Jayhawks', new Map<String, Object>{ 'seed' => 4, 'region' => 'East' });
corrections.put('St. John\'s Red Storm', new Map<String, Object>{ 'seed' => 5, 'region' => 'East' });
corrections.put('Louisville Cardinals', new Map<String, Object>{ 'seed' => 6, 'region' => 'East' });
corrections.put('UCLA Bruins', new Map<String, Object>{ 'seed' => 7, 'region' => 'East' });
corrections.put('Ohio State Buckeyes', new Map<String, Object>{ 'seed' => 8, 'region' => 'East' });
corrections.put('TCU Horned Frogs', new Map<String, Object>{ 'seed' => 9, 'region' => 'East' });
corrections.put('UCF Knights', new Map<String, Object>{ 'seed' => 10, 'region' => 'East' });
corrections.put('South Florida Bulls', new Map<String, Object>{ 'seed' => 11, 'region' => 'East' });
corrections.put('Northern Iowa Panthers', new Map<String, Object>{ 'seed' => 12, 'region' => 'East' });
corrections.put('California Baptist Lancers', new Map<String, Object>{ 'seed' => 13, 'region' => 'East' });
corrections.put('North Dakota State Bison', new Map<String, Object>{ 'seed' => 14, 'region' => 'East' });
corrections.put('Furman Paladins', new Map<String, Object>{ 'seed' => 15, 'region' => 'East' });
corrections.put('Siena Saints', new Map<String, Object>{ 'seed' => 16, 'region' => 'East' });

// SOUTH
corrections.put('Florida Gators', new Map<String, Object>{ 'seed' => 1, 'region' => 'South' });
corrections.put('Houston Cougars', new Map<String, Object>{ 'seed' => 2, 'region' => 'South' });
corrections.put('Illinois Fighting Illini', new Map<String, Object>{ 'seed' => 3, 'region' => 'South' });
corrections.put('Nebraska Cornhuskers', new Map<String, Object>{ 'seed' => 4, 'region' => 'South' });
corrections.put('Vanderbilt Commodores', new Map<String, Object>{ 'seed' => 5, 'region' => 'South' });
corrections.put('North Carolina Tar Heels', new Map<String, Object>{ 'seed' => 6, 'region' => 'South' });
corrections.put('Saint Mary\'s Gaels', new Map<String, Object>{ 'seed' => 7, 'region' => 'South' });
corrections.put('Clemson Tigers', new Map<String, Object>{ 'seed' => 8, 'region' => 'South' });
corrections.put('Iowa Hawkeyes', new Map<String, Object>{ 'seed' => 9, 'region' => 'South' });
corrections.put('Texas A&M Aggies', new Map<String, Object>{ 'seed' => 10, 'region' => 'South' });
corrections.put('VCU Rams', new Map<String, Object>{ 'seed' => 11, 'region' => 'South' });
corrections.put('McNeese Cowboys', new Map<String, Object>{ 'seed' => 12, 'region' => 'South' });
corrections.put('Troy Trojans', new Map<String, Object>{ 'seed' => 13, 'region' => 'South' });
corrections.put('Pennsylvania Quakers', new Map<String, Object>{ 'seed' => 14, 'region' => 'South' });
corrections.put('Idaho Vandals', new Map<String, Object>{ 'seed' => 15, 'region' => 'South' });
corrections.put('Prairie View A&M Panthers', new Map<String, Object>{ 'seed' => 16, 'region' => 'South' });
corrections.put('Lehigh Mountain Hawks', new Map<String, Object>{ 'seed' => 16, 'region' => 'South' });

// MIDWEST
corrections.put('Michigan Wolverines', new Map<String, Object>{ 'seed' => 1, 'region' => 'Midwest' });
corrections.put('Purdue Boilermakers', new Map<String, Object>{ 'seed' => 2, 'region' => 'Midwest' });
corrections.put('Gonzaga Bulldogs', new Map<String, Object>{ 'seed' => 3, 'region' => 'Midwest' });
corrections.put('Alabama Crimson Tide', new Map<String, Object>{ 'seed' => 4, 'region' => 'Midwest' });
corrections.put('Texas Tech Red Raiders', new Map<String, Object>{ 'seed' => 5, 'region' => 'Midwest' });
corrections.put('BYU Cougars', new Map<String, Object>{ 'seed' => 6, 'region' => 'Midwest' });
corrections.put('Kentucky Wildcats', new Map<String, Object>{ 'seed' => 7, 'region' => 'Midwest' });
corrections.put('Miami Hurricanes', new Map<String, Object>{ 'seed' => 8, 'region' => 'Midwest' });
corrections.put('Missouri Tigers', new Map<String, Object>{ 'seed' => 9, 'region' => 'Midwest' });
corrections.put('Santa Clara Broncos', new Map<String, Object>{ 'seed' => 10, 'region' => 'Midwest' });
corrections.put('Texas Longhorns', new Map<String, Object>{ 'seed' => 11, 'region' => 'Midwest' });
corrections.put('NC State Wolfpack', new Map<String, Object>{ 'seed' => 11, 'region' => 'Midwest' });
corrections.put('Akron Zips', new Map<String, Object>{ 'seed' => 12, 'region' => 'Midwest' });
corrections.put('Hofstra Pride', new Map<String, Object>{ 'seed' => 13, 'region' => 'Midwest' });
corrections.put('Kennesaw State Owls', new Map<String, Object>{ 'seed' => 14, 'region' => 'Midwest' });
corrections.put('Queens University Royals', new Map<String, Object>{ 'seed' => 15, 'region' => 'Midwest' });
corrections.put('UMBC Retrievers', new Map<String, Object>{ 'seed' => 16, 'region' => 'Midwest' });
corrections.put('Howard Bison', new Map<String, Object>{ 'seed' => 16, 'region' => 'Midwest' });

// WEST
corrections.put('Arizona Wildcats', new Map<String, Object>{ 'seed' => 1, 'region' => 'West' });
corrections.put('Iowa State Cyclones', new Map<String, Object>{ 'seed' => 2, 'region' => 'West' });
corrections.put('Virginia Cavaliers', new Map<String, Object>{ 'seed' => 3, 'region' => 'West' });
corrections.put('Arkansas Razorbacks', new Map<String, Object>{ 'seed' => 4, 'region' => 'West' });
corrections.put('Wisconsin Badgers', new Map<String, Object>{ 'seed' => 5, 'region' => 'West' });
corrections.put('Tennessee Volunteers', new Map<String, Object>{ 'seed' => 6, 'region' => 'West' });
corrections.put('Villanova Wildcats', new Map<String, Object>{ 'seed' => 7, 'region' => 'West' });
corrections.put('Georgia Bulldogs', new Map<String, Object>{ 'seed' => 8, 'region' => 'West' });
corrections.put('Saint Louis Billikens', new Map<String, Object>{ 'seed' => 9, 'region' => 'West' });
corrections.put('Utah State Aggies', new Map<String, Object>{ 'seed' => 10, 'region' => 'West' });
corrections.put('Miami (OH) RedHawks', new Map<String, Object>{ 'seed' => 11, 'region' => 'West' });
corrections.put('SMU Mustangs', new Map<String, Object>{ 'seed' => 11, 'region' => 'West' });
corrections.put('High Point Panthers', new Map<String, Object>{ 'seed' => 12, 'region' => 'West' });
corrections.put('Hawai\'i Rainbow Warriors', new Map<String, Object>{ 'seed' => 13, 'region' => 'West' });
corrections.put('Wright State Raiders', new Map<String, Object>{ 'seed' => 14, 'region' => 'West' });
corrections.put('Tennessee State Tigers', new Map<String, Object>{ 'seed' => 15, 'region' => 'West' });
corrections.put('Long Island University Sharks', new Map<String, Object>{ 'seed' => 16, 'region' => 'West' });

// Query all teams
List<Team__c> allTeams = [SELECT Id, Name, Seed__c, Region__c FROM Team__c];
List<Team__c> toUpdate = new List<Team__c>();
Integer seedFixes = 0;
Integer regionFixes = 0;

for (Team__c t : allTeams) {
    Map<String, Object> fix = corrections.get(t.Name);
    if (fix == null) continue;

    Boolean changed = false;
    Decimal correctSeed = (Decimal) fix.get('seed');
    String correctRegion = (String) fix.get('region');

    if (t.Seed__c != correctSeed) {
        System.debug('SEED FIX: ' + t.Name + ' ' + t.Seed__c + ' -> ' + correctSeed);
        t.Seed__c = correctSeed;
        changed = true;
        seedFixes++;
    }
    if (t.Region__c != correctRegion) {
        System.debug('REGION FIX: ' + t.Name + ' "' + t.Region__c + '" -> "' + correctRegion + '"');
        t.Region__c = correctRegion;
        changed = true;
        regionFixes++;
    }
    if (changed) toUpdate.add(t);
}

if (!toUpdate.isEmpty()) {
    update toUpdate;
}
System.debug('Updated ' + toUpdate.size() + ' teams (' + seedFixes + ' seed fixes, ' + regionFixes + ' region fixes)');

// Verify by region
for (String r : new List<String>{ 'East', 'Midwest', 'South', 'West' }) {
    List<Team__c> regionTeams = [
        SELECT Name, Seed__c FROM Team__c
        WHERE Region__c = :r ORDER BY Seed__c
    ];
    System.debug('=== ' + r + ' (' + regionTeams.size() + ' teams) ===');
    for (Team__c t : regionTeams) {
        System.debug('  #' + t.Seed__c + ' ' + t.Name);
    }
}
