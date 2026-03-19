HttpRequest req = new HttpRequest();
req.setEndpoint('https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard?groups=100&limit=200&dates=20260317-20260408');
req.setMethod('GET');
req.setTimeout(30000);
req.setHeader('Accept', 'application/json');
HttpResponse res = new Http().send(req);

Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
List<Object> events = (List<Object>) parsed.get('events');

Map<String, String> teamNameToRegion = new Map<String, String>();

for (Object eventObj : events) {
    Map<String, Object> event = (Map<String, Object>) eventObj;
    List<Object> comps = (List<Object>) event.get('competitions');
    Map<String, Object> comp = (Map<String, Object>) comps[0];

    List<Object> notes = (List<Object>) comp.get('notes');
    String region = null;

    if (notes != null) {
        for (Object noteObj : notes) {
            Map<String, Object> note = (Map<String, Object>) noteObj;
            String headline = (String) note.get('headline');
            if (headline == null) continue;
            for (String r : new List<String>{ 'East', 'Midwest', 'South', 'West' }) {
                if (headline.containsIgnoreCase(r + ' Region')) { region = r; break; }
            }
            if (headline.containsIgnoreCase('Final Four') || headline.containsIgnoreCase('National')) {
                region = 'Final Four';
            }
        }
    }
    if (region == null || region == 'Final Four') continue;

    List<Object> competitors = (List<Object>) comp.get('competitors');
    if (competitors != null && competitors.size() >= 2) {
        for (Object c : competitors) {
            Map<String, Object> cMap = (Map<String, Object>) c;
            Map<String, Object> teamData = (Map<String, Object>) cMap.get('team');
            String teamName = (String) teamData.get('displayName');
            if (teamName != null && teamName != 'TBD') {
                teamNameToRegion.put(teamName, region);
            }
        }
    }
}

System.debug('ESPN team->region map: ' + teamNameToRegion.size() + ' entries');
Map<String, Integer> regionCounts = new Map<String, Integer>();
for (String r : teamNameToRegion.values()) {
    regionCounts.put(r, (regionCounts.containsKey(r) ? regionCounts.get(r) : 0) + 1);
}
System.debug('Teams per region: ' + regionCounts);

// Fix teams
List<Team__c> teams = [SELECT Id, Name, Region__c FROM Team__c WHERE Region__c != null];
List<Team__c> teamsToUpdate = new List<Team__c>();
for (Team__c t : teams) {
    String correctRegion = teamNameToRegion.get(t.Name);
    if (correctRegion != null && correctRegion != t.Region__c) {
        System.debug('Fixing team: ' + t.Name + ' "' + t.Region__c + '" -> "' + correctRegion + '"');
        t.Region__c = correctRegion;
        teamsToUpdate.add(t);
    }
}

if (!teamsToUpdate.isEmpty()) {
    update teamsToUpdate;
    System.debug('Fixed region for ' + teamsToUpdate.size() + ' teams');
}

// Fix games by matching team pairs
Map<String, Id> teamIdMap = new Map<String, Id>();
for (Team__c t : [SELECT Id, Name FROM Team__c]) {
    teamIdMap.put(t.Name, t.Id);
}

List<Game__c> games = [
    SELECT Id, Team_1__c, Team_2__c, Team_1__r.Name, Team_2__r.Name, Region__c
    FROM Game__c
    WHERE Tournament__r.Type__c != 'Conference'
];

List<Game__c> gamesToUpdate = new List<Game__c>();
for (Game__c g : games) {
    String t1Region = g.Team_1__r != null ? teamNameToRegion.get(g.Team_1__r.Name) : null;
    String t2Region = g.Team_2__r != null ? teamNameToRegion.get(g.Team_2__r.Name) : null;
    String correctRegion = t1Region != null ? t1Region : t2Region;
    if (correctRegion != null && correctRegion != g.Region__c) {
        System.debug('Fixing game: ' + g.Team_1__r?.Name + ' vs ' + g.Team_2__r?.Name + ' "' + g.Region__c + '" -> "' + correctRegion + '"');
        g.Region__c = correctRegion;
        gamesToUpdate.add(g);
    }
}

if (!gamesToUpdate.isEmpty()) {
    update gamesToUpdate;
    System.debug('Fixed region for ' + gamesToUpdate.size() + ' games');
}

// Verify
List<AggregateResult> verify = [
    SELECT Region__c, COUNT(Id) cnt FROM Game__c
    WHERE Tournament__r.Type__c != 'Conference'
    GROUP BY Region__c ORDER BY Region__c
];
for (AggregateResult ar : verify) {
    System.debug('VERIFY: Region "' + ar.get('Region__c') + '" = ' + ar.get('cnt') + ' games');
}
