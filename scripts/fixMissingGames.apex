Tournament__c tourn = [SELECT Id FROM Tournament__c WHERE Status__c IN ('Active','Upcoming') LIMIT 1];

// Build team lookup
Map<String, Team__c> teamMap = new Map<String, Team__c>();
for (Team__c t : [SELECT Id, Name, Seed__c, Region__c FROM Team__c WHERE Tournament__c = :tourn.Id AND Region__c != null]) {
    teamMap.put(t.Name, t);
}

// === 1. Assign teams to TBD R64 placeholder games ===
// These are feeder games from First Four

// Midwest TBD game 1: #1 Michigan vs First Four #16 winner (Howard/UMBC) 
// Midwest TBD game 2: #6 BYU vs First Four #11 winner (NC State/Texas)
List<Game__c> mwTBD = [
    SELECT Id FROM Game__c
    WHERE Region__c = 'Midwest' AND Round__c = 'Round of 64'
      AND Team_1__c = null AND Team_2__c = null
    ORDER BY Game_Date__c ASC
];
if (mwTBD.size() >= 1) {
    mwTBD[0].Team_1__c = teamMap.get('Michigan Wolverines').Id;
    System.debug('Assigned Michigan to Midwest R64 TBD game (vs First Four #16 winner)');
}
if (mwTBD.size() >= 2) {
    mwTBD[1].Team_1__c = teamMap.get('BYU Cougars').Id;
    System.debug('Assigned BYU to Midwest R64 TBD game (vs First Four #11 winner)');
}
if (!mwTBD.isEmpty()) update mwTBD;

// South TBD game: #1 Florida vs First Four #16 winner (Lehigh/PV A&M)
List<Game__c> southTBD = [
    SELECT Id FROM Game__c
    WHERE Region__c = 'South' AND Round__c = 'Round of 64'
      AND Team_1__c = null AND Team_2__c = null
    LIMIT 1
];
if (!southTBD.isEmpty()) {
    southTBD[0].Team_1__c = teamMap.get('Florida Gators').Id;
    update southTBD;
    System.debug('Assigned Florida to South R64 TBD game (vs First Four #16 winner)');
}

// West TBD game: #6 Tennessee vs First Four #11 winner (SMU/Miami OH)
List<Game__c> westTBD = [
    SELECT Id FROM Game__c
    WHERE Region__c = 'West' AND Round__c = 'Round of 64'
      AND Team_1__c = null AND Team_2__c = null
    LIMIT 1
];
if (!westTBD.isEmpty()) {
    westTBD[0].Team_1__c = teamMap.get('Tennessee Volunteers').Id;
    update westTBD;
    System.debug('Assigned Tennessee to West R64 TBD game (vs First Four #11 winner)');
}

// === 2. Create missing R64 games ===
Integer nextGameNum = [SELECT COUNT() FROM Game__c WHERE Tournament__c = :tourn.Id] + 1;
List<Game__c> newGames = new List<Game__c>();

// East: #4 Kansas vs #13 Cal Baptist
newGames.add(new Game__c(
    Tournament__c = tourn.Id,
    Region__c = 'East',
    Round__c = 'Round of 64',
    Team_1__c = teamMap.get('Kansas Jayhawks').Id,
    Team_2__c = teamMap.get('California Baptist Lancers').Id,
    Status__c = 'Scheduled',
    Game_Date__c = Date.newInstance(2026, 3, 20),
    Game_Number__c = nextGameNum++
));
System.debug('Creating: East R64 - #4 Kansas vs #13 Cal Baptist');

// Midwest: #2 Purdue vs #15 Queens
newGames.add(new Game__c(
    Tournament__c = tourn.Id,
    Region__c = 'Midwest',
    Round__c = 'Round of 64',
    Team_1__c = teamMap.get('Purdue Boilermakers').Id,
    Team_2__c = teamMap.get('Queens University Royals').Id,
    Status__c = 'Scheduled',
    Game_Date__c = Date.newInstance(2026, 3, 20),
    Game_Number__c = nextGameNum++
));
System.debug('Creating: Midwest R64 - #2 Purdue vs #15 Queens');

// West: #1 Arizona vs #16 LIU
newGames.add(new Game__c(
    Tournament__c = tourn.Id,
    Region__c = 'West',
    Round__c = 'Round of 64',
    Team_1__c = teamMap.get('Arizona Wildcats').Id,
    Team_2__c = teamMap.get('Long Island University Sharks').Id,
    Status__c = 'Scheduled',
    Game_Date__c = Date.newInstance(2026, 3, 20),
    Game_Number__c = nextGameNum++
));
System.debug('Creating: West R64 - #1 Arizona vs #16 LIU');

insert newGames;
System.debug('Created ' + newGames.size() + ' new R64 games');

// === 3. Verify final state ===
for (String r : new List<String>{ 'East', 'Midwest', 'South', 'West' }) {
    List<Game__c> games = [
        SELECT Team_1__r.Name, Team_1__r.Seed__c, Team_2__r.Name, Team_2__r.Seed__c
        FROM Game__c
        WHERE Region__c = :r AND Round__c = 'Round of 64'
        ORDER BY Team_1__r.Seed__c NULLS LAST
    ];
    System.debug('=== ' + r + ' R64 (' + games.size() + ' games) ===');
    for (Game__c g : games) {
        String t1 = g.Team_1__r != null ? '#' + g.Team_1__r.Seed__c + ' ' + g.Team_1__r.Name : 'TBD';
        String t2 = g.Team_2__r != null ? '#' + g.Team_2__r.Seed__c + ' ' + g.Team_2__r.Name : 'TBD (First Four)';
        System.debug('  ' + t1 + ' vs ' + t2);
    }
}
