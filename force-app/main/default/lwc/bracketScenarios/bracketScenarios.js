import { LightningElement, api, wire } from 'lwc';
import getBracketScenarios from '@salesforce/apex/MarchMadnessController.getBracketScenarios';
import generateBracketScenarios from '@salesforce/apex/MarchMadnessController.generateBracketScenarios';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const ROUND_ORDER = [
    'Round of 64', 'Round of 32', 'Sweet 16', 'Elite 8', 'Final Four', 'Championship'
];

const STRATEGY_ICONS = {
    'Chalk': '📋',
    'Statistical Favorite': '📊',
    'Mild Upsets': '🎲',
    'Upset Special': '💥',
    'Cinderella Story': '👸',
    'Blue Blood': '🏛️',
    'Defense Wins': '🛡️',
    'Hot Streak': '🔥',
    'Vegas Consensus': '🎰',
    'Historical Trends': '📜',
    'Chaos Bracket': '🌪️',
    'Balanced Blend': '⚖️',
    'Random Sim #1': '🎯',
    'Random Sim #2': '🎯',
    'Random Sim #3': '🎯'
};

export default class BracketScenarios extends LightningElement {
    @api tournamentId;

    scenarios = [];
    selectedScenario = null;
    isLoading = false;
    isGenerating = false;
    wiredResult;
    viewMode = 'grid'; // grid or bracket
    selectedRound = 'all';

    @wire(getBracketScenarios, { tournamentId: '$tournamentId' })
    wiredScenarios(result) {
        this.wiredResult = result;
        if (result.data) {
            this.scenarios = result.data.map(s => this.enrichScenario(s));
        }
    }

    enrichScenario(s) {
        const icon = STRATEGY_ICONS[s.Strategy__c] || '📊';
        const hasChampion = s.Champion__c != null;
        const champColor = s.Champion__r?.Primary_Color__c ?? '003da5';
        const champLogo = s.Champion__r?.Logo_URL__c;
        const champSeed = s.Champion__r?.Seed__c;
        const champRegion = s.Champion__r?.Region__c;
        const runnerLogo = s.Runner_Up__r?.Logo_URL__c;

        let bracketData = null;
        try {
            if (s.Bracket_JSON__c) {
                bracketData = JSON.parse(s.Bracket_JSON__c);
            }
        } catch (e) { /* ignore parse errors */ }

        const upsetLevel =
            s.Total_Upsets__c >= 12 ? 'high' :
            s.Total_Upsets__c >= 6 ? 'medium' : 'low';

        return {
            ...s,
            icon,
            hasChampion,
            champColor,
            champLogo,
            champSeed: champSeed != null ? `#${champSeed}` : '',
            champRegion,
            champName: s.Champion__r?.Name ?? 'TBD',
            runnerName: s.Runner_Up__r?.Name ?? 'TBD',
            runnerLogo,
            runnerSeed: s.Runner_Up__r?.Seed__c != null ? `#${s.Runner_Up__r.Seed__c}` : '',
            bracketData,
            upsetLevel,
            upsetBadgeClass: `upset-badge upset-${upsetLevel}`,
            confidenceDisplay: s.Overall_Confidence__c != null
                ? `${s.Overall_Confidence__c}%` : '-',
            cardStyle: `border-top: 4px solid #${champColor};`,
            isSelected: false
        };
    }

    get generateLabel() {
        return this.hasScenarios ? 'Regenerate All' : 'Generate All Scenarios';
    }

    get hasScenarios() {
        return this.scenarios.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasScenarios;
    }

    get showGrid() {
        return this.viewMode === 'grid' && !this.selectedScenario;
    }

    get showBracketDetail() {
        return this.selectedScenario != null;
    }

    get scenarioCount() {
        return this.scenarios.length;
    }

    // Champion frequency analysis
    get championSummary() {
        const champCounts = {};
        for (const s of this.scenarios) {
            const name = s.champName;
            if (name && name !== 'TBD') {
                champCounts[name] = (champCounts[name] || 0) + 1;
            }
        }
        return Object.entries(champCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5)
            .map(([name, count]) => {
                const scenario = this.scenarios.find(s => s.champName === name);
                return {
                    name,
                    count,
                    pct: Math.round((count / this.scenarios.length) * 100),
                    logo: scenario?.champLogo,
                    seed: scenario?.champSeed,
                    barStyle: `width: ${Math.round((count / this.scenarios.length) * 100)}%;`
                };
            });
    }

    get hasChampionSummary() {
        return this.championSummary.length > 0;
    }

    // Final Four frequency
    get finalFourSummary() {
        const ffCounts = {};
        for (const s of this.scenarios) {
            if (!s.bracketData?.finalFour) continue;
            for (const team of s.bracketData.finalFour) {
                const name = team.name;
                ffCounts[name] = (ffCounts[name] || 0) + 1;
            }
        }
        return Object.entries(ffCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 8)
            .map(([name, count]) => ({
                name,
                count,
                pct: Math.round((count / this.scenarios.length) * 100),
                barStyle: `width: ${Math.round((count / this.scenarios.length) * 100)}%;`
            }));
    }

    get hasFinalFourSummary() {
        return this.finalFourSummary.length > 0;
    }

    // Most common upsets
    get commonUpsets() {
        const upsetMap = {};
        for (const s of this.scenarios) {
            if (!s.bracketData?.upsets) continue;
            for (const u of s.bracketData.upsets) {
                const key = `${u.winnerName} over ${u.loserName}`;
                if (!upsetMap[key]) {
                    upsetMap[key] = { ...u, count: 0, key };
                }
                upsetMap[key].count++;
            }
        }
        return Object.values(upsetMap)
            .sort((a, b) => b.count - a.count || b.seedDiff - a.seedDiff)
            .slice(0, 10)
            .map(u => ({
                ...u,
                display: `#${u.winnerSeed} ${u.winnerName} over #${u.loserSeed} ${u.loserName}`,
                frequency: `${u.count}/${this.scenarios.length}`,
                pct: Math.round((u.count / this.scenarios.length) * 100)
            }));
    }

    get hasCommonUpsets() {
        return this.commonUpsets.length > 0;
    }

    // Selected bracket detail
    get selectedBracketRounds() {
        if (!this.selectedScenario?.bracketData?.rounds) return [];
        const rounds = this.selectedScenario.bracketData.rounds;
        return ROUND_ORDER
            .filter(r => rounds[r] && (this.selectedRound === 'all' || this.selectedRound === r))
            .map(roundName => {
                const games = rounds[roundName] || [];
                const regions = {};
                for (const g of games) {
                    const region = g.region || 'Unknown';
                    if (!regions[region]) regions[region] = [];
                    regions[region].push({
                        ...g,
                        key: `${g.team1?.name}-${g.team2?.name}`,
                        team1Display: g.team1 ? `#${g.team1.seed} ${g.team1.name}` : 'TBD',
                        team2Display: g.team2 ? `#${g.team2.seed} ${g.team2.name}` : 'TBD',
                        winnerDisplay: g.winner ? g.winner.name : 'TBD',
                        team1Logo: g.team1?.logo,
                        team2Logo: g.team2?.logo,
                        winnerLogo: g.winner?.logo,
                        team1IsWinner: g.winner && g.team1 && g.winner.id === g.team1.id,
                        team2IsWinner: g.winner && g.team2 && g.winner.id === g.team2.id,
                        team1Class: `bracket-team${g.winner && g.team1 && g.winner.id === g.team1.id ? ' winner' : g.winner ? ' loser' : ''}`,
                        team2Class: `bracket-team${g.winner && g.team2 && g.winner.id === g.team2.id ? ' winner' : g.winner ? ' loser' : ''}`,
                        confidenceDisplay: g.winProbability ? `${g.winProbability}%` : '',
                        upsetBadge: g.isUpset ? 'UPSET' : ''
                    });
                }
                return {
                    name: roundName,
                    key: roundName,
                    gameCount: games.length,
                    regionGroups: Object.entries(regions).map(([region, regionGames]) => ({
                        region,
                        key: `${roundName}-${region}`,
                        games: regionGames
                    }))
                };
            });
    }

    get selectedUpsets() {
        if (!this.selectedScenario?.bracketData?.upsets) return [];
        return this.selectedScenario.bracketData.upsets.map((u, i) => ({
            ...u,
            key: `upset-${i}`,
            display: `#${u.winnerSeed} ${u.winnerName} over #${u.loserSeed} ${u.loserName}`,
            roundDisplay: u.round
        }));
    }

    get hasSelectedUpsets() {
        return this.selectedUpsets.length > 0;
    }

    get selectedFinalFour() {
        if (!this.selectedScenario?.bracketData?.finalFour) return [];
        return this.selectedScenario.bracketData.finalFour.map((t, i) => ({
            ...t,
            key: `ff-${i}`,
            seedDisplay: `#${t.seed}`,
            hasLogo: t.logo != null
        }));
    }

    get roundFilterOptions() {
        const options = [{ label: 'All Rounds', value: 'all' }];
        for (const r of ROUND_ORDER) {
            options.push({ label: r, value: r });
        }
        return options;
    }

    // --- Handlers ---

    async handleGenerate() {
        this.isGenerating = true;
        try {
            const result = await generateBracketScenarios({ tournamentId: this.tournamentId });
            const parsed = JSON.parse(result);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Brackets Generated',
                message: parsed.message,
                variant: 'success'
            }));
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Generation Error',
                message: error.body?.message ?? 'Failed to generate bracket scenarios',
                variant: 'error'
            }));
        } finally {
            this.isGenerating = false;
        }
    }

    handleScenarioClick(event) {
        const scenarioId = event.currentTarget.dataset.scenarioId;
        this.selectedScenario = this.scenarios.find(s => s.Id === scenarioId) || null;
        this.selectedRound = 'all';
    }

    handleBackToGrid() {
        this.selectedScenario = null;
    }

    handleRoundFilter(event) {
        this.selectedRound = event.detail.value;
    }
}
