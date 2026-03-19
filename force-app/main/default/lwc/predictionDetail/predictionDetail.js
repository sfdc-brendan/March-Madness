import { LightningElement, api, wire } from 'lwc';
import getPredictionDetail from '@salesforce/apex/MarchMadnessController.getPredictionDetail';

export default class PredictionDetail extends LightningElement {
    @api recordId;
    data;
    error;

    @wire(getPredictionDetail, { predictionId: '$recordId' })
    wiredPrediction({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    get hasData() { return this.data != null; }

    get team1Name() { return this.data?.team1Name || 'TBD'; }
    get team1Seed() { return this.data?.team1Seed; }
    get team1Logo() { return this.data?.team1Logo; }
    get team1Color() { return this.data?.team1Color || '003da5'; }
    get team1Score() { return this.data?.team1Score; }

    get team2Name() { return this.data?.team2Name || 'TBD'; }
    get team2Seed() { return this.data?.team2Seed; }
    get team2Logo() { return this.data?.team2Logo; }
    get team2Color() { return this.data?.team2Color || 'ff6600'; }
    get team2Score() { return this.data?.team2Score; }

    get round() { return this.data?.round || ''; }
    get region() { return this.data?.region || ''; }
    get gameStatus() { return this.data?.gameStatus || 'Scheduled'; }
    get actualWinner() { return this.data?.actualWinner; }

    get predictedWinner() { return this.data?.predictedWinner || 'Unknown'; }
    get confidence() { return this.data?.confidence || 0; }
    get team1Prob() { return this.data?.team1Prob || 0; }
    get team2Prob() { return this.data?.team2Prob || 0; }
    get modelType() { return this.data?.modelType || 'Statistical'; }
    get modelVersion() { return this.data?.modelVersion || ''; }
    get predictionDate() { return this.data?.predictionDate; }
    get rationale() { return this.data?.rationale || ''; }
    get isCurrent() { return this.data?.isCurrent; }
    get wasCorrect() { return this.data?.wasCorrect; }

    get hasTeam1Logo() { return this.team1Logo != null; }
    get hasTeam2Logo() { return this.team2Logo != null; }
    get team1SeedDisplay() { return this.team1Seed != null ? `#${this.team1Seed}` : ''; }
    get team2SeedDisplay() { return this.team2Seed != null ? `#${this.team2Seed}` : ''; }

    get modelIcon() {
        const icons = { 'Statistical': '\u{1F4CA}', 'Mascot Battle': '\u2694\uFE0F', 'AI Research': '\u{1F916}' };
        return icons[this.modelType] || '\u{1F4CA}';
    }

    get modelBadgeClass() {
        const m = this.modelType.replace(/\s+/g, '-').toLowerCase();
        return `model-badge model-${m}`;
    }

    get confidenceDisplay() { return `${Math.round(this.confidence)}%`; }
    get team1ProbDisplay() { return `${Number(this.team1Prob).toFixed(1)}%`; }
    get team2ProbDisplay() { return `${Number(this.team2Prob).toFixed(1)}%`; }
    get team1BarStyle() { return `width: ${this.team1Prob}%; background-color: #${this.team1Color};`; }
    get team2BarStyle() { return `width: ${this.team2Prob}%; background-color: #${this.team2Color};`; }

    get confidenceGaugeStyle() {
        const pct = Math.min(100, Math.max(0, this.confidence));
        const deg = (pct / 100) * 180;
        return `--gauge-deg: ${deg}deg;`;
    }

    get confidenceLevel() {
        const c = this.confidence;
        if (c >= 70) return 'Very High';
        if (c >= 50) return 'High';
        if (c >= 30) return 'Moderate';
        if (c >= 15) return 'Low';
        return 'Toss-Up';
    }

    get confidenceLevelClass() {
        const c = this.confidence;
        if (c >= 70) return 'conf-level very-high';
        if (c >= 50) return 'conf-level high';
        if (c >= 30) return 'conf-level moderate';
        if (c >= 15) return 'conf-level low';
        return 'conf-level toss-up';
    }

    get isGameComplete() { return this.gameStatus === 'Final'; }
    get showVerdict() { return this.isGameComplete && this.actualWinner != null; }
    get verdictClass() { return this.wasCorrect ? 'verdict correct' : 'verdict wrong'; }
    get verdictIcon() { return this.wasCorrect ? '\u2713' : '\u2717'; }
    get verdictLabel() { return this.wasCorrect ? 'Prediction Correct!' : 'Prediction Wrong'; }

    get scoreDisplay() {
        if (!this.isGameComplete) return '';
        return `${this.team1Score ?? 0} - ${this.team2Score ?? 0}`;
    }

    get currentBadge() { return this.isCurrent ? 'current-badge active' : 'current-badge inactive'; }
    get currentLabel() { return this.isCurrent ? 'Current' : 'Superseded'; }
    get hasRationale() { return this.rationale && this.rationale.length > 0; }

    get team1IsPredicted() { return this.predictedWinner === this.team1Name; }
    get team2IsPredicted() { return this.predictedWinner === this.team2Name; }
    get team1Class() { return `matchup-team${this.team1IsPredicted ? ' predicted' : ''}`; }
    get team2Class() { return `matchup-team${this.team2IsPredicted ? ' predicted' : ''}`; }
}
