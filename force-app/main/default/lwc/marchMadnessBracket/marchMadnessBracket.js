import { LightningElement, api, wire } from 'lwc';
import getAllGames from '@salesforce/apex/MarchMadnessController.getAllGames';
import getCurrentPredictions from '@salesforce/apex/MarchMadnessController.getCurrentPredictions';
import loadBracketFromESPN from '@salesforce/apex/MarchMadnessController.loadBracketFromESPN';
import refreshBracketResults from '@salesforce/apex/MarchMadnessController.refreshBracketResults';
import runPredictionForModel from '@salesforce/apex/MarchMadnessController.runPredictionForModel';
import runAllPredictionModels from '@salesforce/apex/MarchMadnessController.runAllPredictionModels';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const ROUND_ORDER = ['First Four', 'Round of 64', 'Round of 32', 'Sweet 16', 'Elite 8', 'Final Four', 'Championship'];
const MODEL_TYPES = [
    { value: 'all', label: 'All Models', icon: 'utility:layers', color: '#003DA5' },
    { value: 'Statistical', label: 'Statistical', icon: 'utility:chart', color: '#0176D3' },
    { value: 'Mascot Battle', label: 'Mascot Battle', icon: 'utility:animal_and_nature', color: '#FF6600' },
    { value: 'AI Research', label: 'AI Research', icon: 'utility:einstein', color: '#9050E9' }
];

export default class MarchMadnessBracket extends LightningElement {
    @api tournamentId;

    allGames = [];
    allPredictions = [];
    predictionsMap = {};
    selectedRound = 'all';
    selectedModel = 'all';
    isLoading = true;
    isLoadingBracket = false;
    isRefreshing = false;
    isRunningPrediction = false;
    selectedGameId = null;
    errorMessage;
    _wiredGamesResult;
    _wiredPredResult;

    @wire(getAllGames, { tournamentId: '$tournamentId' })
    wiredGames(result) {
        this._wiredGamesResult = result;
        if (result.data) {
            this.allGames = result.data;
            this.rebuildEnrichedGames();
            this.isLoading = false;
            this.errorMessage = undefined;
        } else if (result.error) {
            this.errorMessage = result.error.body?.message ?? 'Failed to load bracket data';
            this.allGames = [];
            this.isLoading = false;
        }
    }

    @wire(getCurrentPredictions, { tournamentId: '$tournamentId' })
    wiredPredictions(result) {
        this._wiredPredResult = result;
        if (result.data) {
            this.allPredictions = result.data;
            this.rebuildPredictionsMap();
            this.rebuildEnrichedGames();
        }
    }

    rebuildPredictionsMap() {
        const map = {};
        this.allPredictions.forEach(p => {
            const model = p.Model_Type__c || 'Statistical';
            const key = p.Game__c + '::' + model;
            map[key] = p;
        });
        this.predictionsMap = map;
    }

    enrichedGames = [];

    rebuildEnrichedGames() {
        this.enrichedGames = this.allGames.map(game => this.enrichGame(game));
    }

    getPredictionForGame(gameId) {
        if (this.selectedModel === 'all') {
            for (const mt of ['Statistical', 'Mascot Battle', 'AI Research']) {
                const key = gameId + '::' + mt;
                if (this.predictionsMap[key]) return this.predictionsMap[key];
            }
            return null;
        }
        return this.predictionsMap[gameId + '::' + this.selectedModel] || null;
    }

    getModelCountForGame(gameId) {
        let count = 0;
        for (const mt of ['Statistical', 'Mascot Battle', 'AI Research']) {
            if (this.predictionsMap[gameId + '::' + mt]) count++;
        }
        return count;
    }

    enrichGame(game) {
        const team1Name = game.Team_1__r?.Name ?? 'TBD';
        const team2Name = game.Team_2__r?.Name ?? 'TBD';
        const team1Seed = game.Team_1__r?.Seed__c ?? '';
        const team2Seed = game.Team_2__r?.Seed__c ?? '';
        const isCompleted = game.Status__c === 'Final';
        const hasWinner = game.Winner__c != null;

        const pred = this.getPredictionForGame(game.Id);
        const hasPrediction = pred != null;
        const predictionCorrect = hasPrediction && hasWinner && pred.Predicted_Winner__c === game.Winner__c;
        const confidence = pred?.Confidence_Score__c;
        const modelType = pred?.Model_Type__c || 'Statistical';
        const modelCount = this.getModelCountForGame(game.Id);

        let statusClass = 'game-card';
        if (hasPrediction && isCompleted && hasWinner) {
            statusClass += predictionCorrect ? ' prediction-correct' : ' prediction-wrong';
        } else if (hasPrediction) {
            statusClass += ' prediction-pending';
        } else {
            statusClass += ' prediction-none';
        }

        const isTeam1Winner = hasWinner && game.Winner__c === game.Team_1__c;
        const isTeam2Winner = hasWinner && game.Winner__c === game.Team_2__c;
        const isTeam1Predicted = hasPrediction && pred.Predicted_Winner__c === game.Team_1__c;
        const isTeam2Predicted = hasPrediction && pred.Predicted_Winner__c === game.Team_2__c;

        const modelIcon = this.getModelIcon(modelType);
        const modelBadgeClass = `prediction-badge model-${modelType.replace(/\s+/g, '-').toLowerCase()}`;

        return {
            ...game,
            team1Name,
            team2Name,
            team1Seed: team1Seed ? `(${team1Seed})` : '',
            team2Seed: team2Seed ? `(${team2Seed})` : '',
            team1Logo: game.Team_1__r?.Logo_URL__c ?? null,
            team2Logo: game.Team_2__r?.Logo_URL__c ?? null,
            displayScore1: isCompleted ? (game.Team_1_Score__c ?? '-') : '',
            displayScore2: isCompleted ? (game.Team_2_Score__c ?? '-') : '',
            hasPrediction,
            confidenceDisplay: hasPrediction ? `${Math.round(confidence ?? 0)}%` : '',
            predictionTitle: hasPrediction
                ? `${modelType}: ${Math.round(confidence ?? 0)}% confidence`
                : 'No prediction',
            gameClass: statusClass,
            team1Class: `team-row${isTeam1Winner ? ' winner' : ''}${isTeam1Predicted ? ' predicted' : ''}`,
            team2Class: `team-row${isTeam2Winner ? ' winner' : ''}${isTeam2Predicted ? ' predicted' : ''}`,
            modelType,
            modelIcon,
            modelBadgeClass,
            modelCount,
            hasMultipleModels: modelCount > 1,
            modelCountDisplay: modelCount > 1 ? `${modelCount}` : '',
            isSelected: game.Id === this.selectedGameId,
            selectedGameClass: game.Id === this.selectedGameId ? statusClass + ' game-selected' : statusClass,
            predictionRationale: pred?.Prediction_Rationale__c ?? '',
            team1WinProb: pred?.Team_1_Win_Probability__c ?? null,
            team2WinProb: pred?.Team_2_Win_Probability__c ?? null,
            predWinnerName: pred?.Predicted_Winner__r?.Name ?? ''
        };
    }

    getModelIcon(modelType) {
        const icons = {
            'Statistical': '📊',
            'Mascot Battle': '⚔️',
            'AI Research': '🤖'
        };
        return icons[modelType] || '📊';
    }

    get modelOptions() {
        return MODEL_TYPES.map(m => ({
            ...m,
            variant: this.selectedModel === m.value ? 'brand' : 'neutral',
            cssClass: this.selectedModel === m.value ? 'model-btn active' : 'model-btn'
        }));
    }

    get roundOptions() {
        const options = [{ label: 'Full Bracket', value: 'all', variant: this.selectedRound === 'all' ? 'brand' : 'neutral' }];
        ROUND_ORDER.forEach(r => {
            options.push({ label: r, value: r, variant: this.selectedRound === r ? 'brand' : 'neutral' });
        });
        return options;
    }

    get bracketAreaClass() {
        return this.hasSelectedGame ? 'bracket-area bracket-area-with-detail' : 'bracket-area';
    }

    get showFullBracket() {
        return this.selectedRound === 'all';
    }

    get selectedRoundLabel() {
        return this.selectedRound;
    }

    get hasNoGames() {
        return !this.isLoading && this.enrichedGames.length === 0 && !this.errorMessage;
    }

    get selectedGameDetail() {
        if (!this.selectedGameId) return null;
        return this.enrichedGames.find(g => g.Id === this.selectedGameId);
    }

    get hasSelectedGame() {
        return this.selectedGameId != null;
    }

    get selectedGameModels() {
        if (!this.selectedGameId) return [];
        const models = [];
        for (const mt of ['Statistical', 'Mascot Battle', 'AI Research']) {
            const key = this.selectedGameId + '::' + mt;
            const pred = this.predictionsMap[key];
            if (pred) {
                models.push({
                    key: mt,
                    type: mt,
                    icon: this.getModelIcon(mt),
                    winnerName: pred.Predicted_Winner__r?.Name ?? 'Unknown',
                    confidence: Math.round(pred.Confidence_Score__c ?? 0),
                    t1Prob: pred.Team_1_Win_Probability__c?.toFixed(1) ?? '-',
                    t2Prob: pred.Team_2_Win_Probability__c?.toFixed(1) ?? '-',
                    rationale: pred.Prediction_Rationale__c ?? '',
                    isCorrect: !!(pred.Game__r?.Winner__c && pred.Predicted_Winner__c && String(pred.Game__r.Winner__c) === String(pred.Predicted_Winner__c)),
                    hasResult: this.selectedGameDetail?.Status__c === 'Final',
                    badgeClass: `model-result-badge model-${mt.replace(/\s+/g, '-').toLowerCase()}`
                });
            }
        }
        return models;
    }

    get predictionSummaryStats() {
        const stats = { total: 0, statistical: 0, mascot: 0, ai: 0, correct: 0, completed: 0 };
        const counted = new Set();
        this.allPredictions.forEach(p => {
            const model = p.Model_Type__c || 'Statistical';
            stats.total++;
            if (model === 'Statistical') stats.statistical++;
            else if (model === 'Mascot Battle') stats.mascot++;
            else if (model === 'AI Research') stats.ai++;
            if (p.Game__r?.Winner__c && p.Predicted_Winner__c && String(p.Game__r.Winner__c) === String(p.Predicted_Winner__c)) stats.correct++;
            if (!counted.has(p.Game__c)) {
                counted.add(p.Game__c);
            }
        });
        return stats;
    }

    getRegionRounds(region) {
        const regionGames = this.enrichedGames.filter(g => g.Region__c === region);
        const roundNames = ['Round of 64', 'Round of 32', 'Sweet 16', 'Elite 8'];
        return roundNames.map((name, idx) => ({
            name: `${region}-${name}`,
            className: `bracket-round round-${idx}`,
            games: regionGames.filter(g => g.Round__c === name)
        })).filter(r => r.games.length > 0);
    }

    get eastRounds() { return this.getRegionRounds('East'); }
    get southRounds() { return this.getRegionRounds('South'); }
    get midwestRounds() { return this.getRegionRounds('Midwest'); }
    get westRounds() { return this.getRegionRounds('West'); }

    get finalFourGames() {
        return this.enrichedGames.filter(g => g.Round__c === 'Final Four');
    }

    get championshipGames() {
        return this.enrichedGames.filter(g => g.Round__c === 'Championship');
    }

    get filteredGames() {
        if (this.selectedRound === 'all') return this.enrichedGames;
        return this.enrichedGames.filter(g => g.Round__c === this.selectedRound);
    }

    handleRoundSelect(event) {
        this.selectedRound = event.currentTarget.dataset.round;
    }

    handleModelSelect(event) {
        this.selectedModel = event.currentTarget.dataset.model;
        this.rebuildEnrichedGames();
    }

    handleGameClick(event) {
        const gameId = event.currentTarget.dataset.gameId;
        this.selectedGameId = this.selectedGameId === gameId ? null : gameId;
        this.rebuildEnrichedGames();
        this.dispatchEvent(new CustomEvent('gameselect', {
            detail: { gameId, game: this.enrichedGames.find(g => g.Id === gameId) },
            bubbles: true,
            composed: true
        }));
    }

    handleCloseDetail() {
        this.selectedGameId = null;
        this.rebuildEnrichedGames();
    }

    async handleRunModel(event) {
        const modelType = event.currentTarget.dataset.model;
        const gameId = this.selectedGameId;
        if (!gameId) return;

        this.isRunningPrediction = true;
        try {
            await runPredictionForModel({ gameId, modelType });
            await refreshApex(this._wiredPredResult);
            this.rebuildEnrichedGames();
            this.dispatchEvent(new ShowToastEvent({
                title: `${modelType} Prediction Complete`,
                message: `${modelType} model prediction generated successfully.`,
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Prediction Error',
                message: e.body?.message ?? `Failed to run ${modelType} prediction`,
                variant: 'error'
            }));
        } finally {
            this.isRunningPrediction = false;
        }
    }

    async handleRunAllModels() {
        const gameId = this.selectedGameId;
        if (!gameId) return;

        this.isRunningPrediction = true;
        try {
            await runAllPredictionModels({ gameId });
            await refreshApex(this._wiredPredResult);
            this.rebuildEnrichedGames();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Predictions Running',
                message: 'Statistical prediction complete. Mascot Battle and AI Research are processing in the background - refresh in a few seconds to see results.',
                variant: 'success',
                mode: 'sticky'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: e.body?.message ?? 'Failed to run predictions',
                variant: 'error'
            }));
        } finally {
            this.isRunningPrediction = false;
        }
    }

    async handleLoadBracket() {
        if (!this.tournamentId) return;
        this.isLoadingBracket = true;
        try {
            await loadBracketFromESPN({ tournamentId: this.tournamentId });
            await refreshApex(this._wiredGamesResult);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Bracket Loaded',
                message: 'Tournament bracket data has been pulled from ESPN.',
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: e.body?.message ?? 'Failed to load bracket',
                variant: 'error'
            }));
        } finally {
            this.isLoadingBracket = false;
        }
    }

    async handleRefreshResults() {
        if (!this.tournamentId) return;
        this.isRefreshing = true;
        try {
            await refreshBracketResults({ tournamentId: this.tournamentId });
            await refreshApex(this._wiredGamesResult);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Results Updated',
                message: 'Game results have been refreshed.',
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: e.body?.message ?? 'Failed to refresh results',
                variant: 'error'
            }));
        } finally {
            this.isRefreshing = false;
        }
    }
}
