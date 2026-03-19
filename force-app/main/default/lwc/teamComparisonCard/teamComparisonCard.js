import { LightningElement, api, wire } from 'lwc';
import getGamesByRound from '@salesforce/apex/MarchMadnessController.getGamesByRound';
import runPrediction from '@salesforce/apex/MarchMadnessController.runPrediction';
import getCurrentPredictions from '@salesforce/apex/MarchMadnessController.getCurrentPredictions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const SEED_WIN_RATES = {
    '1v16': 99, '2v15': 94, '3v14': 85, '4v13': 79, '5v12': 65,
    '6v11': 63, '7v10': 61, '8v9': 51, '1v8': 80, '1v4': 72,
    '2v3': 55, '1v2': 52
};

const STAT_CONFIGS = [
    { field: 'Seed__c', name: 'Seed', inverse: true, format: 'seed' },
    { field: 'KenPom_Rating__c', name: 'KenPom', inverse: false },
    { field: 'NET_Ranking__c', name: 'NET Rank', inverse: true },
    { field: 'Points_Per_Game__c', name: 'PPG', inverse: false },
    { field: 'Opp_Points_Per_Game__c', name: 'Opp PPG', inverse: true },
    { field: 'Strength_of_Schedule__c', name: 'SOS', inverse: false },
    { field: 'Overall_Power_Rating__c', name: 'Power Rating', inverse: false }
];

export default class TeamComparisonCard extends LightningElement {
    @api gameId;
    @api tournamentId;

    gameData;
    team1;
    team2;
    prediction;
    isLoading = false;
    isPredicting = false;

    @wire(getGamesByRound, { round: '$activeRound' })
    wiredGames({ data }) {
        if (data && this.gameId) {
            const game = data.find(g => g.Id === this.gameId);
            if (game) {
                this.gameData = game;
                this.team1 = game.Team_1__r;
                this.team2 = game.Team_2__r;
            }
        }
    }

    @wire(getCurrentPredictions, { tournamentId: '$tournamentId' })
    wiredPredictions({ data }) {
        if (data && this.gameId) {
            this.prediction = data.find(p => p.Game__c === this.gameId) ?? null;
        }
    }

    get activeRound() {
        return this.gameData?.Round__c ?? 'Round of 64';
    }

    get hasGame() {
        return this.gameData != null;
    }

    get team1Name() { return this.team1?.Name ?? 'TBD'; }
    get team2Name() { return this.team2?.Name ?? 'TBD'; }
    get team1Seed() { return this.team1?.Seed__c != null ? `#${this.team1.Seed__c}` : ''; }
    get team2Seed() { return this.team2?.Seed__c != null ? `#${this.team2.Seed__c}` : ''; }
    get team1Logo() { return this.team1?.Logo_URL__c ?? null; }
    get team2Logo() { return this.team2?.Logo_URL__c ?? null; }
    get team1Record() {
        if (this.team1?.Record_Wins__c == null) return '';
        return `${this.team1.Record_Wins__c}-${this.team1.Record_Losses__c ?? 0}`;
    }
    get team2Record() {
        if (this.team2?.Record_Wins__c == null) return '';
        return `${this.team2.Record_Wins__c}-${this.team2.Record_Losses__c ?? 0}`;
    }
    get gameRound() { return this.gameData?.Round__c ?? ''; }

    get comparisonStats() {
        if (!this.team1 || !this.team2) return [];
        return STAT_CONFIGS.map(cfg => {
            const val1 = this.team1[cfg.field];
            const val2 = this.team2[cfg.field];
            const num1 = val1 != null ? Number(val1) : null;
            const num2 = val2 != null ? Number(val2) : null;

            let team1Better = false;
            let team2Better = false;
            if (num1 != null && num2 != null) {
                if (cfg.inverse) {
                    team1Better = num1 < num2;
                    team2Better = num2 < num1;
                } else {
                    team1Better = num1 > num2;
                    team2Better = num2 > num1;
                }
            }

            let pct1 = 50;
            let pct2 = 50;
            if (num1 != null && num2 != null && (num1 + num2) > 0) {
                if (cfg.inverse) {
                    const inv1 = num2;
                    const inv2 = num1;
                    pct1 = Math.round((inv1 / (inv1 + inv2)) * 100);
                    pct2 = 100 - pct1;
                } else {
                    pct1 = Math.round((num1 / (num1 + num2)) * 100);
                    pct2 = 100 - pct1;
                }
            }

            return {
                name: cfg.name,
                team1Display: val1 != null ? `${val1}` : '-',
                team2Display: val2 != null ? `${val2}` : '-',
                team1ValueClass: `stat-val${team1Better ? ' advantage' : ''}`,
                team2ValueClass: `stat-val${team2Better ? ' advantage' : ''}`,
                team1BarStyle: `width: ${pct1}%;`,
                team2BarStyle: `width: ${pct2}%;`
            };
        });
    }

    get hasBettingLines() {
        return this.gameData?.Spread__c != null ||
               this.gameData?.Team_1_Moneyline__c != null ||
               this.gameData?.Over_Under__c != null;
    }
    get hasSpread() { return this.gameData?.Spread__c != null; }
    get hasOverUnder() { return this.gameData?.Over_Under__c != null; }
    get hasMoneylines() { return this.gameData?.Team_1_Moneyline__c != null; }
    get spreadDisplay() {
        const s = this.gameData?.Spread__c;
        if (s == null) return '';
        const favored = s < 0 ? this.team1Name : this.team2Name;
        return `${favored} ${Math.abs(s) > 0 ? (s < 0 ? s : '+' + s) : 'PK'}`;
    }
    get overUnderDisplay() { return this.gameData?.Over_Under__c != null ? `${this.gameData.Over_Under__c}` : ''; }
    get team1MoneylineDisplay() {
        const ml = this.gameData?.Team_1_Moneyline__c;
        if (ml == null) return '';
        return ml > 0 ? `+${ml}` : `${ml}`;
    }
    get team2MoneylineDisplay() {
        const ml = this.gameData?.Team_2_Moneyline__c;
        if (ml == null) return '';
        return ml > 0 ? `+${ml}` : `${ml}`;
    }
    get bettingSource() { return this.gameData?.Betting_Line_Source__c ?? ''; }

    get hasSeeds() {
        return this.team1?.Seed__c != null && this.team2?.Seed__c != null;
    }

    get seedInsight() {
        if (!this.hasSeeds) return '';
        const s1 = Math.min(this.team1.Seed__c, this.team2.Seed__c);
        const s2 = Math.max(this.team1.Seed__c, this.team2.Seed__c);
        const key = `${s1}v${s2}`;
        const rate = SEED_WIN_RATES[key];
        if (rate) {
            return `Historically, #${s1} seeds beat #${s2} seeds ${rate}% of the time in the NCAA Tournament.`;
        }
        return `#${s1} seed vs #${s2} seed matchup.`;
    }

    get hasPrediction() {
        return this.prediction != null;
    }

    get predictedWinnerName() {
        if (!this.hasPrediction) return '';
        return this.prediction.Predicted_Winner__r?.Name ?? '';
    }

    get confidenceDisplay() {
        return this.hasPrediction ? `${Math.round(this.prediction.Confidence_Score__c ?? 0)}%` : '';
    }

    get probRingStyle() {
        const conf = this.prediction?.Confidence_Score__c ?? 50;
        const deg = Math.round((conf / 100) * 360);
        return `background: conic-gradient(var(--mm-blue) ${deg}deg, var(--mm-surface) ${deg}deg);`;
    }

    get hasRationale() {
        return this.prediction?.Prediction_Rationale__c != null;
    }

    get rationaleText() {
        return this.prediction?.Prediction_Rationale__c ?? '';
    }

    get predictButtonLabel() {
        return this.hasPrediction ? 'Re-Predict' : 'Predict Winner';
    }

    async handlePredict() {
        if (!this.gameId) return;
        this.isPredicting = true;
        try {
            const result = await runPrediction({ gameId: this.gameId });
            const parsed = JSON.parse(result);
            this.showToast('Prediction Complete',
                `${parsed.predictedWinner} predicted to win with ${Math.round(parsed.confidence ?? 0)}% confidence`, 'success');
            this.dispatchEvent(new CustomEvent('predictioncomplete', {
                detail: parsed,
                bubbles: true,
                composed: true
            }));
        } catch (error) {
            this.showToast('Prediction Failed', error.body?.message ?? 'An error occurred', 'error');
        } finally {
            this.isPredicting = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
