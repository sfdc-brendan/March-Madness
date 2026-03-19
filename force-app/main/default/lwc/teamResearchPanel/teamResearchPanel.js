import { LightningElement, api, wire } from 'lwc';
import getTeamDetail from '@salesforce/apex/MarchMadnessController.getTeamDetail';
import getTeamPerformance from '@salesforce/apex/MarchMadnessController.getTeamPerformance';
import getPredictionsForRound from '@salesforce/apex/MarchMadnessController.getPredictionsForRound';
import refreshTeamResearch from '@salesforce/apex/MarchMadnessController.refreshTeamResearch';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class TeamResearchPanel extends LightningElement {
    _teamId;
    @api recordId;

    @api
    get teamId() { return this._teamId; }
    set teamId(val) {
        if (val !== this._teamId) {
            this._teamId = val;
            this.performance = null;
            this._perfLoadedForTeam = null;
            this.perfError = false;
        }
    }

    team;
    performance;
    predictions = [];
    isLoading = true;
    isLoadingPerf = false;
    isRefreshing = false;
    perfError = false;
    _perfLoadedForTeam = null;
    wiredTeamResult;

    get effectiveTeamId() {
        return this._teamId ?? this.recordId;
    }

    @wire(getTeamDetail, { teamId: '$effectiveTeamId' })
    wiredTeam(result) {
        this.wiredTeamResult = result;
        this.isLoading = false;
        if (result.data) {
            this.team = result.data;
        } else if (result.error) {
            this.team = null;
            this.showToast('Error', result.error.body?.message ?? 'Failed to load team', 'error');
        }
    }

    @wire(getPredictionsForRound, { round: '' })
    wiredPredictions({ data }) {
        if (data) {
            this.predictions = data.filter(p => {
                const tid = this.effectiveTeamId;
                return p.Game__r?.Team_1__c === tid || p.Game__r?.Team_2__c === tid ||
                       p.Predicted_Winner__c === tid;
            });
        }
    }

    get cardTitle() {
        return this.team ? `Team Intelligence: ${this.team.Name}` : 'Team Intelligence';
    }

    get hasTeam() { return this.team != null; }

    get seedDisplay() {
        return this.team?.Seed__c != null ? `#${this.team.Seed__c}` : 'N/A';
    }

    get teamRecord() {
        if (this.team?.Record_Wins__c == null) return '';
        return `${this.team.Record_Wins__c}-${this.team.Record_Losses__c ?? 0}`;
    }

    get powerRating() {
        return this.team?.Overall_Power_Rating__c != null
            ? Math.round(this.team.Overall_Power_Rating__c) : '-';
    }

    get powerRingStyle() {
        const rating = this.team?.Overall_Power_Rating__c ?? 0;
        const pct = Math.min(Math.max(rating, 0), 100);
        const deg = Math.round((pct / 100) * 360);
        return `background: conic-gradient(var(--mm-blue) ${deg}deg, var(--mm-surface) ${deg}deg);`;
    }

    get latestResearch() {
        const researches = this.team?.Research_Records__r;
        return researches?.length > 0 ? researches[0] : null;
    }

    get hasLatestResearch() { return this.latestResearch != null; }

    get latestResearchDate() {
        const dt = this.latestResearch?.Research_Date__c;
        if (!dt) return '';
        return new Date(dt).toLocaleDateString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit'
        });
    }

    get sentimentValue() {
        return this.latestResearch?.Sentiment_Score__c ?? 0;
    }

    get sentimentDisplay() {
        const v = this.sentimentValue;
        const label = v > 30 ? 'Positive' : v < -30 ? 'Negative' : 'Neutral';
        return `${v > 0 ? '+' : ''}${v} (${label})`;
    }

    get sentimentGaugeStyle() {
        const normalized = ((this.sentimentValue + 100) / 200) * 100;
        return `width: ${Math.max(normalized, 2)}%;`;
    }

    get sentimentMarkerStyle() {
        const normalized = ((this.sentimentValue + 100) / 200) * 100;
        return `left: ${normalized}%;`;
    }

    get hasTournamentLikelihood() {
        return this.team?.Tournament_Likelihood__c != null;
    }

    get likelihoodDisplay() {
        return `${Math.round(this.team?.Tournament_Likelihood__c ?? 0)}%`;
    }

    get likelihoodStyle() {
        return `width: ${Math.max(this.team?.Tournament_Likelihood__c ?? 0, 2)}%;`;
    }

    get netRankDisplay() { return this.team?.NET_Ranking__c != null ? `#${Math.round(this.team.NET_Ranking__c)}` : '-'; }
    get kenPomDisplay() { return this.team?.KenPom_Rating__c != null ? `${this.team.KenPom_Rating__c}` : '-'; }
    get ppgDisplay() { return this.team?.Points_Per_Game__c != null ? `${this.team.Points_Per_Game__c}` : '-'; }
    get oppPpgDisplay() { return this.team?.Opp_Points_Per_Game__c != null ? `${this.team.Opp_Points_Per_Game__c}` : '-'; }
    get sosDisplay() { return this.team?.Strength_of_Schedule__c != null ? `${this.team.Strength_of_Schedule__c}` : '-'; }
    get last10Display() { return this.team?.Last_10_Record__c ?? '-'; }
    get recordDisplay() {
        if (this.team?.Record_Wins__c == null) return '-';
        return `${Math.round(this.team.Record_Wins__c)}-${Math.round(this.team.Record_Losses__c ?? 0)}`;
    }

    get hasPerformance() { return this.performance?.games?.length > 0; }

    get streakDisplay() {
        if (!this.performance) return '-';
        return `${this.performance.streakType}${this.performance.currentStreak}`;
    }
    get streakClass() {
        const type = this.performance?.streakType;
        return `ks-value${type === 'W' ? ' streak-win' : type === 'L' ? ' streak-loss' : ''}`;
    }

    get chartGames() {
        if (!this.hasPerformance) return [];
        const games = this.performance.games.filter(g => g.status === 'post');
        const maxScore = Math.max(...games.map(g => Math.max(g.teamScore ?? 0, g.oppScore ?? 0)), 80);
        const chartMax = Math.ceil(maxScore / 10) * 10;

        return games.map((g, idx) => {
            const scored = g.teamScore ?? 0;
            const allowed = g.oppScore ?? 0;
            const scoredPct = (scored / chartMax) * 100;
            const allowedPct = (allowed / chartMax) * 100;
            const margin = g.margin ?? 0;
            const oppLabel = g.isHome ? `vs ${g.opponent ?? '?'}` : `@ ${g.opponent ?? '?'}`;
            const rankStr = g.opponentRank ? `#${g.opponentRank} ` : '';

            return {
                key: `game-${idx}`,
                scoredStyle: `height: ${scoredPct}%;`,
                allowedStyle: `height: ${allowedPct}%;`,
                barWrapClass: `bar-wrap${g.isConfTourney ? ' conf-tourney' : ''}`,
                marginBadgeClass: `margin-badge${g.isWin ? ' win' : ' loss'}`,
                marginLabel: margin > 0 ? `+${margin}` : `${margin}`,
                oppLabel: g.opponent ?? '?',
                tooltip: `${rankStr}${oppLabel}: ${scored}-${allowed} (${g.isWin ? 'W' : 'L'})`,
                isConfTourney: g.isConfTourney === true
            };
        });
    }

    get chartMaxLabel() {
        if (!this.hasPerformance) return '100';
        const games = this.performance.games.filter(g => g.status === 'post');
        const maxScore = Math.max(...games.map(g => Math.max(g.teamScore ?? 0, g.oppScore ?? 0)), 80);
        return `${Math.ceil(maxScore / 10) * 10}`;
    }
    get chartMidLabel() { return `${Math.round(Number(this.chartMaxLabel) / 2)}`; }

    get recentGamesTable() {
        if (!this.hasPerformance) return [];
        return [...this.performance.games].reverse().map((g, idx) => {
            const d = g.gameDate ? new Date(g.gameDate) : null;
            const dateStr = d ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '';
            const isCompleted = g.status === 'post';
            const loc = g.isHome ? 'vs' : '@';

            return {
                key: `row-${idx}`,
                dateDisplay: dateStr,
                resultLabel: isCompleted ? (g.isWin ? 'W' : 'L') : g.status === 'in' ? 'LIVE' : '-',
                resultClass: `gt-cell result${g.isWin ? ' win' : !isCompleted ? '' : ' loss'}`,
                oppDisplay: `${loc} ${g.opponent ?? 'TBD'}`,
                opponentLogo: g.opponentLogo ?? null,
                opponentRank: g.opponentRank,
                scoreDisplay: isCompleted ? `${g.teamScore}-${g.oppScore}` : (g.status === 'in' ? `${g.teamScore ?? 0}-${g.oppScore ?? 0}` : 'Scheduled'),
                noteDisplay: g.note ?? '',
                rowClass: `gt-row${g.isConfTourney ? ' tourney' : ''}${g.isWin ? ' win-row' : ''}`
            };
        });
    }

    async handleStatsTabActive() {
        const tid = this.effectiveTeamId;
        if (!tid || this._perfLoadedForTeam === tid) return;
        this.isLoadingPerf = true;
        this.perfError = false;
        try {
            this.performance = await getTeamPerformance({ teamId: tid });
            this._perfLoadedForTeam = tid;
        } catch (e) {
            this.perfError = true;
            console.error('Performance load error:', e);
        } finally {
            this.isLoadingPerf = false;
        }
    }

    handleLogoError(event) {
        event.target.style.display = 'none';
    }

    get teamPredictions() {
        return this.predictions.map(p => {
            const game = p.Game__r ?? {};
            const isCompleted = game.Status__c === 'Final';
            const isCorrect = !!(p.Game__r?.Winner__c && p.Predicted_Winner__c && String(p.Game__r.Winner__c) === String(p.Predicted_Winner__c));
            const team1 = game.Team_1__r?.Name ?? 'TBD';
            const team2 = game.Team_2__r?.Name ?? 'TBD';

            let cardClass = 'prediction-card';
            let resultLabel = '';
            let resultBadgeClass = '';
            if (isCompleted) {
                cardClass += isCorrect ? ' pred-correct' : ' pred-wrong';
                resultLabel = isCorrect ? 'Correct' : 'Wrong';
                resultBadgeClass = isCorrect ? 'badge-correct' : 'badge-wrong';
            }

            return {
                ...p,
                matchupDisplay: `${team1} vs ${team2}`,
                confidenceDisplay: `${Math.round(p.Confidence_Score__c ?? 0)}%`,
                predictedWinnerName: p.Predicted_Winner__r?.Name ?? 'TBD',
                cardClass,
                hasResult: isCompleted,
                resultLabel,
                resultBadgeClass
            };
        });
    }

    get hasPredictions() { return this.teamPredictions.length > 0; }

    async handleRefreshResearch() {
        const tid = this.effectiveTeamId;
        if (!tid) return;
        this.isRefreshing = true;
        try {
            await refreshTeamResearch({ teamId: tid });
            await refreshApex(this.wiredTeamResult);
            this.showToast('Success', 'Research refresh initiated', 'success');
        } catch (error) {
            this.showToast('Error', error.body?.message ?? 'Failed to refresh research', 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
