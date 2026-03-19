# March Madness Prediction Engine

A full-stack Salesforce application that tracks the NCAA Men's Basketball Tournament, generates AI-powered predictions using three distinct models, simulates bracket scenarios with 15 different strategies, and ingests live data from ESPN and Google Gemini.

Built entirely on the Salesforce Platform with Lightning Web Components, Apex, and external API integrations.

## What It Does

- **Live bracket tracking** — Pulls real game data, scores, seeds, and regions from the ESPN API and keeps them current throughout the tournament
- **Three prediction models** — Statistical (weighted factor model), Mascot Battle (AI-generated mascot fight narratives via Gemini), and AI Research (comprehensive Gemini analysis using team stats, news sentiment, and betting lines)
- **15 bracket scenario strategies** — From Pure Chalk to Chaos Bracket, each simulates the full 63-game tournament using a different weighting philosophy
- **Conference tournament tracking** — Monitors 30+ conference tournaments with live scores, round tracking, and automatic qualification detection
- **AI-powered news and research** — Uses Gemini with Google Search grounding to research teams, generate news articles with source attribution, and assess tournament likelihood
- **Betting line integration** — Fetches and applies spreads, moneylines, and over/unders to inform predictions
- **Automated scheduling** — Configurable scheduled jobs refresh scores, update predictions, and sweep for news throughout tournament day

## Architecture

```
                    +------------------+
                    |  marchMadnessApp |  (Main LWC Shell)
                    +--------+---------+
                             |
          +------------------+------------------+
          |          |           |        |      |
    Dashboard  Conferences  Bracket  Scenarios  News
     (stats)    (conf.lwc)  (bracket) (scenarios)(feed)
          |          |           |        |      |
          +----------+-----------+--------+-----+
                             |
                   MarchMadnessController  (Apex Hub)
                             |
        +--------------------+--------------------+
        |            |            |          |     |
  Prediction    BracketData   Tournament  News   ESPN
   Engine       Service       FieldSvc    Ingest  Services
        |            |            |          |     |
        +------+-----+------+----+----+-----+-----+
               |            |         |
          GeminiAPI     ESPN APIs   HistoricalSeedData
          Service       (public)    (static reference)
```

### Data Model

**7 custom objects + 1 custom metadata type:**

| Object | Purpose | Key Fields |
|--------|---------|------------|
| `Tournament__c` | Tournament container (NCAA or Conference) | Year, Status, Type, Parent_Tournament, Conference_Name, ESPN_Conference_Id |
| `Team__c` | Team profile with stats | Seed, Region, Conference, KenPom_Rating, NET_Ranking, PPG, Opp_PPG, SOS, Last_10_Record, Overall_Power_Rating, Logo_URL, Mascot |
| `Game__c` | Individual game with scores and betting lines | Round, Region, Status, Team_1/2, Winner, Spread, Over_Under, Moneylines, ESPN_Game_Id, Venue, TV_Network |
| `Prediction__c` | Model prediction for a game | Predicted_Winner, Confidence_Score, Team_1/2_Win_Probability, Model_Type, Prediction_Rationale, Is_Current |
| `Bracket_Scenario__c` | Full bracket simulation result | Strategy, Champion, Runner_Up, Final_Four_Summary, Total_Upsets, Bracket_JSON, Overall_Confidence |
| `Team_Research__c` | AI-generated team research | Summary, Key_Factors, Sentiment_Score, Confidence_Level, Is_Current |
| `News_Article__c` | News article (ESPN or AI-generated) | Summary, Source, Source_URL, Sentiment_Score, Category, Is_Verified, Grounding_Sources, Image_URL |
| `Statistical_Factor__c` | Detailed statistical breakdown per team | Factor_Name, Factor_Value, Weight, Category |
| `Gemini_Config__mdt` | Custom Metadata for Gemini API config | API_Key, Default_Model, Endpoint_Base, Is_Active |

### Apex Classes (29 total)

**Controllers & Orchestration:**
- `MarchMadnessController` — Central LWC controller with 25+ `@AuraEnabled` methods covering all CRUD, predictions, bracket loading, and live scoreboards
- `MarchMadnessScheduler` — Schedulable/Queueable chain for automated daily/hourly/gameday refresh cycles
- `PredictionModelQueueable` — Queueable chain runner for async Mascot Battle and AI Research predictions

**Prediction Engines:**
- `PredictionEngine` — Statistical model using 9 weighted factors: seed (0.15), rating (0.20), record (0.10), efficiency (0.10), momentum (0.08), injuries (0.05), sentiment (0.05), historical (0.05), and betting lines (0.22)
- `MascotPredictionEngine` — Sends mascot matchup prompts to Gemini for structured JSON responses with battle narratives, power ratings, and key advantages
- `AIPredictionEngine` — Comprehensive Gemini analysis incorporating team stats, research context, news sentiment, and betting lines for expert-level predictions
- `BracketScenarioGenerator` — Simulates all 63 games across 15 strategies (Chalk, Statistical, Mild Upsets, Upset Special, Cinderella, Blue Blood, Defense Wins, Hot Streak, Vegas Consensus, Historical Trends, Chaos, Balanced Blend, + 3 random sims)
- `BracketSimulator` — Monte Carlo simulator running 1000 iterations to calculate round-by-round advancement probabilities
- `HistoricalSeedData` — Static reference data with historical seed-vs-seed win rates (e.g., 1-vs-16 = 99.4%)

**Data Services:**
- `BracketDataService` — Loads and updates the NCAA tournament bracket from ESPN's scoreboard API, including team seeds, regions, scores, venues, and broadcasts
- `TournamentFieldService` — Uses Gemini AI to populate the projected 68-team tournament field with stats before Selection Sunday
- `ConferenceTournamentService` — Creates and manages 30+ conference tournament records, loads games from ESPN by conference group ID
- `BettingLineService` — Fetches current betting lines (spreads, moneylines, O/U) via Gemini and applies them to scheduled games
- `ESPNScoreboardService` — Real-time scoreboard data with live scores, clock, period, broadcasts, and odds
- `ESPNTeamService` — Team schedule, recent game results, records, win streaks, and performance trends
- `ESPNNewsService` — Fetches news articles from ESPN's news API for general and team-specific coverage

**AI & Parsing:**
- `GeminiAPIService` — Gemini API client supporting `generateContent`, `generateGroundedContent` (with Google Search), and `generateStructuredContent` (with JSON schema enforcement). Config stored in `Gemini_Config__mdt`
- `GeminiResponseParser` — Parses Gemini JSON responses into `Team_Research__c` and `News_Article__c` records with grounding source extraction
- `TeamResearchPromptBuilder` — Constructs detailed prompts for team research, head-to-head analysis, grounded news search, conference tournament updates, and betting line requests
- `NewsIngestionService` — Orchestrates team research ingestion: calls Gemini for analysis + grounded news, deduplicates articles, manages `Is_Current__c` lifecycle
- `ContenderNewsSweep` — Batchable that sweeps all tournament contenders for fresh grounded news articles

### Lightning Web Components (9)

| Component | Description |
|-----------|-------------|
| `marchMadnessApp` | Main shell with tabbed navigation (Dashboard, Conferences, Bracket, Scenarios, Teams, News), tournament header, team sidebar, and stats bar |
| `marchMadnessBracket` | Interactive bracket viewer organized by region with game cards showing seeds, logos, scores, and prediction overlays. Supports round/model filtering and per-game prediction detail panels |
| `bracketScenarios` | Scenario grid showing all 15 bracket strategies with champion/runner-up, confidence scores, upset counts, and drill-down bracket views. Includes champion frequency analysis, Final Four summary, and common upset tracking |
| `predictionDashboard` | Dashboard stats and prediction accuracy tracking |
| `predictionDetail` | Detailed prediction view with multi-model comparison |
| `teamComparisonCard` | Side-by-side team stat comparison |
| `teamResearchPanel` | AI research display with sentiment scores and key factors |
| `conferenceTournaments` | Conference tournament tracker with live scores |
| `marchMadnessNewsFeed` | News feed with verified/grounded article indicators |

## Setup

### Prerequisites

- Salesforce org (Developer Edition, sandbox, or scratch org)
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) v2+
- [Google Gemini API key](https://aistudio.google.com/apikey) (for AI features)
- Node.js 18+ (for LWC local development)

### Deploy

```bash
# Clone the repo
git clone https://github.com/sfdc-brendan/March-Madness.git
cd March-Madness

# Authorize your org
sf org login web --alias march-madness

# Deploy to org
sf project deploy start --target-org march-madness
```

### Configure Gemini API

1. Go to **Setup > Custom Metadata Types > Gemini Config > Manage Records**
2. Create a new record:
   - **Label:** `Default`
   - **API_Key:** Your Gemini API key
   - **Default_Model:** `gemini-2.0-flash`
   - **Endpoint_Base:** `https://generativelanguage.googleapis.com`
   - **Is_Active:** checked

### Configure Remote Site Settings

Add these endpoints in **Setup > Remote Site Settings**:
- `https://generativelanguage.googleapis.com` (Gemini API)
- `https://site.api.espn.com` (ESPN API — public, no key required)

### Load Data

Run from the app UI or via Anonymous Apex in the Developer Console:

```apex
// 1. Load the projected tournament field (uses Gemini AI)
TournamentFieldService.loadField(tournamentId);

// 2. Load bracket from ESPN (after Selection Sunday)
BracketDataService.loadFullBracket(tournamentId);

// 3. Populate team logos from ESPN
BracketDataService.populateLogos(tournamentId);

// 4. Create conference tournaments
ConferenceTournamentService.createConferenceTournaments(tournamentId);

// 5. Refresh betting lines
BettingLineService.refreshLinesForTournament(tournamentId);

// 6. Generate bracket scenarios
BracketScenarioGenerator.generateAllScenarios(tournamentId);

// 7. Schedule automated refreshes
MarchMadnessScheduler.scheduleGameDay();
MarchMadnessScheduler.scheduleNewsSweep();
```

## Bracket Scenario Strategies

| Strategy | Description |
|----------|-------------|
| **Pure Chalk** | Higher seed wins every game |
| **Statistical Favorite** | Full weighted statistical model picks most likely winner |
| **Mild Upset Mix** | Mostly favorites with 4-6 early-round upsets matching historical frequency |
| **Upset Special** | Aggressively favors underdogs with 8+ first-weekend upsets |
| **Cinderella Story** | A double-digit seed makes a deep run to the Elite 8 or beyond |
| **Blue Blood Dominance** | Boosts historically elite programs (Duke, UNC, Kansas, Kentucky, UConn, etc.) |
| **Defense Wins Championships** | Heavily weights defensive efficiency — teams that limit opponent scoring advance |
| **Hot Streak** | Emphasizes last-10-game momentum over season-long stats |
| **Vegas Knows Best** | Betting lines and spreads drive predictions (55% weight) where available |
| **Historical Trends** | Leans heavily on how often each seed historically advances in each round |
| **March Madness Chaos** | Maximum randomness with probability-weighted coin flips and noise |
| **Balanced Blend** | Equal weight across all six factors |
| **Random Sim #1-3** | Probability-weighted random simulations — unique bracket each generation |

## Prediction Model Weights

### Statistical Model

| Factor | Weight | Source |
|--------|--------|--------|
| Betting Lines | 22% | Spreads and moneylines |
| Rating Edge | 20% | KenPom + NET composite |
| Seed Advantage | 15% | Tournament seed differential |
| Record Quality | 10% | Win% adjusted by strength of schedule |
| Efficiency | 10% | Scoring margin (PPG - Opp PPG) |
| Momentum | 8% | Last 10 games record |
| Injuries/Sentiment | 10% | AI research sentiment score |
| Historical Matchup | 5% | Seed-vs-seed historical win rates |

When betting lines are unavailable, the remaining factor weights are proportionally redistributed.

## External APIs

| API | Auth | Usage |
|-----|------|-------|
| ESPN Scoreboard | None (public) | Game scores, schedules, brackets, seeds, regions |
| ESPN Teams | None (public) | Team logos, colors, records, schedules |
| ESPN News | None (public) | General and team-specific news articles |
| ESPN Rankings | None (public) | AP/Coaches poll rankings |
| Google Gemini | API Key | Team research, mascot battles, AI predictions, grounded news, betting lines, tournament field projection |

## Project Structure

```
force-app/main/default/
  applications/        March_Madness.app-meta.xml
  classes/             29 Apex classes (services, engines, controllers, tests)
  lwc/                 9 Lightning Web Components
  objects/             7 custom objects + 1 custom metadata type
  tabs/                8 custom tabs
```

## License

MIT
