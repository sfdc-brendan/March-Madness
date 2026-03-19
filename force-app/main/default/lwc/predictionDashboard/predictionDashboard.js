import { LightningElement, api, wire } from 'lwc';
import getCommandCenterStats from '@salesforce/apex/MarchMadnessController.getCommandCenterStats';
import getMultiDayScoreboard from '@salesforce/apex/MarchMadnessController.getMultiDayScoreboard';
import getLatestNews from '@salesforce/apex/MarchMadnessController.getLatestNews';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const REFRESH_MS = 30000;

export default class PredictionDashboard extends LightningElement {
    @api tournamentId;

    stats = {};
    scoreboard = null;
    recentNews = [];
    isLoading = true;
    isRefreshing = false;
    selectedConference = '';
    _refreshInterval;
    _clockInterval;
    displayTime = '';

    @wire(getCommandCenterStats, { tournamentId: '$tournamentId' })
    wiredStats({ data }) {
        if (data) {
            this.stats = data;
        }
    }

    @wire(getLatestNews, { limitCount: 6 })
    wiredNews({ data }) {
        if (data) {
            this.recentNews = data.map(a => this.enrichArticle(a));
        }
    }

    async connectedCallback() {
        this.updateClock();
        this._clockInterval = setInterval(() => this.updateClock(), 30000);
        await this.loadScoreboard();
        this._refreshInterval = setInterval(() => this.loadScoreboard(), REFRESH_MS);
    }

    disconnectedCallback() {
        if (this._refreshInterval) clearInterval(this._refreshInterval);
        if (this._clockInterval) clearInterval(this._clockInterval);
    }

    updateClock() {
        this.displayTime = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    }

    async loadScoreboard() {
        try {
            const result = await getMultiDayScoreboard();
            this.scoreboard = result;
            this.isLoading = false;
        } catch (error) {
            this.isLoading = false;
            console.error('Scoreboard error:', error);
        }
    }

    async handleRefreshScores() {
        this.isRefreshing = true;
        try {
            await this.loadScoreboard();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Scores Updated',
                message: `Live scoreboard refreshed from ESPN at ${this.scoreboard?.asOfTime ?? 'now'}.`,
                variant: 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Refresh Failed',
                message: error.body?.message ?? 'Could not refresh scores.',
                variant: 'error'
            }));
        } finally {
            this.isRefreshing = false;
        }
    }

    enrichArticle(article) {
        const pubDate = article.Article_Date__c;
        let timeAgo = '';
        if (pubDate) {
            const d = new Date(pubDate);
            const now = new Date();
            const diffHrs = Math.floor((now - d) / 3600000);
            if (diffHrs < 1) timeAgo = 'Just now';
            else if (diffHrs < 24) timeAgo = `${diffHrs}h ago`;
            else timeAgo = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        }

        const imageUrl = article.Image_URL__c ?? '';
        const hasImage = imageUrl.length > 0;

        return {
            ...article,
            key: article.Id,
            headline: article.Name,
            timeAgo,
            teamName: article.Team__r?.Name ?? '',
            teamLogo: article.Team__r?.Logo_URL__c ?? null,
            hasTeam: article.Team__r != null,
            hasImage,
            imageUrl,
            newsItemClass: `news-item${hasImage ? ' has-image' : ' no-image'}`,
            sourceBadgeClass: `news-source-badge ${(article.Source_Type__c ?? '').toLowerCase().replace(' ', '-')}`
        };
    }

    // --- Getters ---

    get isReady() { return !this.isLoading; }

    get totalTeams() { return this.stats.totalTeams ?? 0; }
    get totalGamesStored() { return this.stats.totalGames ?? 0; }
    get conferenceCount() { return this.stats.conferences ?? 0; }
    get newsCount() { return this.stats.newsArticles ?? 0; }

    get scoreboardGames() {
        return this.scoreboard?.games ?? [];
    }

    get liveGameCount() {
        return this.scoreboard?.liveGames ?? 0;
    }

    get totalScoreboardGames() {
        return this.scoreboard?.totalGames ?? 0;
    }

    get completedGames() {
        return this.scoreboard?.completedGames ?? 0;
    }

    get scheduledGames() {
        return this.scoreboard?.scheduledGames ?? 0;
    }

    get hasLiveGames() { return this.liveGameCount > 0; }
    get hasScoreboardGames() { return this.scoreboardGames.length > 0; }
    get hasNews() { return this.recentNews.length > 0; }
    get asOfTime() { return this.scoreboard?.asOfTime ?? ''; }

    get enrichedGames() {
        let games = this.scoreboardGames.map(g => {
            const isLive = g.state === 'in';
            const isFinal = g.isCompleted === true;
            const isScheduled = g.state === 'pre';

            let statusLabel = '';
            let statusClass = 'game-status-badge ';
            if (isLive) {
                statusLabel = g.displayClock && g.period
                    ? `${g.displayClock} - ${this.periodLabel(g.period)}`
                    : 'LIVE';
                statusClass += 'live';
            } else if (isFinal) {
                statusLabel = 'Final';
                statusClass += 'final';
            } else {
                statusLabel = g.statusShortDetail ?? 'Scheduled';
                statusClass += 'scheduled';
            }

            const homeRankLabel = g.homeRank && g.homeRank <= 25 ? `${g.homeRank}` : '';
            const awayRankLabel = g.awayRank && g.awayRank <= 25 ? `${g.awayRank}` : '';
            const conference = this.extractConference(g.note);
            const round = this.extractRound(g.note);

            let actionLabel = '';
            let actionClass = '';
            if (isLive && g.broadcast) {
                actionLabel = 'Watch';
                actionClass = 'action-btn watch';
            } else if (isFinal) {
                actionLabel = 'Highlights';
                actionClass = 'action-btn highlights';
            }

            return {
                key: g.espnId,
                ...g,
                isLive,
                isFinal,
                isScheduled,
                statusLabel,
                statusClass,
                homeRankLabel,
                awayRankLabel,
                homeDisplayName: (homeRankLabel ? homeRankLabel + ' ' : '') + (g.homeTeam ?? 'TBD'),
                awayDisplayName: (awayRankLabel ? awayRankLabel + ' ' : '') + (g.awayTeam ?? 'TBD'),
                homeScoreDisplay: (isLive || isFinal) ? (g.homeScore ?? '0') : '',
                awayScoreDisplay: (isLive || isFinal) ? (g.awayScore ?? '0') : '',
                homeRowClass: `sb-team-row${g.homeWinner ? ' winner' : ''}`,
                awayRowClass: `sb-team-row${g.awayWinner ? ' winner' : ''}`,
                homeScoreClass: `sb-score${isLive ? ' live' : ''}${g.homeWinner ? ' winner' : ''}`,
                awayScoreClass: `sb-score${isLive ? ' live' : ''}${g.awayWinner ? ' winner' : ''}`,
                conference,
                round,
                noteDisplay: g.note ?? '',
                hasBroadcast: g.broadcast != null && g.broadcast.length > 0,
                broadcastDisplay: g.broadcast ?? '',
                hasOdds: g.spreadDetail != null,
                oddsDisplay: g.spreadDetail ?? '',
                ouDisplay: g.overUnder != null ? `O/U: ${g.overUnder}` : '',
                actionLabel,
                actionClass,
                hasAction: actionLabel.length > 0,
                homeLogoUrl: g.homeLogo ?? '',
                awayLogoUrl: g.awayLogo ?? '',
                hasHomeLogo: g.homeLogo != null,
                hasAwayLogo: g.awayLogo != null
            };
        });

        if (this.selectedConference) {
            games = games.filter(g => g.conference === this.selectedConference);
        }

        return games.sort((a, b) => {
            if (a.isLive && !b.isLive) return -1;
            if (!a.isLive && b.isLive) return 1;
            if (a.isScheduled && !b.isScheduled) return 1;
            if (!a.isScheduled && b.isScheduled) return -1;
            return 0;
        });
    }

    get conferenceFilterOptions() {
        const confs = new Set();
        this.scoreboardGames.forEach(g => {
            const conf = this.extractConference(g.note);
            if (conf) confs.add(conf);
        });
        const options = [{ label: `All (${this.scoreboardGames.length})`, value: '' }];
        [...confs].sort().forEach(c => {
            const count = this.scoreboardGames.filter(g => this.extractConference(g.note) === c).length;
            options.push({ label: `${c} (${count})`, value: c });
        });
        return options;
    }

    get todayDate() {
        return new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
    }

    // --- Helpers ---

    periodLabel(period) {
        if (period === 1) return '1st';
        if (period === 2) return '2nd';
        if (period > 2) return `OT${period - 2 > 1 ? period - 2 : ''}`;
        return '';
    }

    extractConference(note) {
        if (!note) return '';
        const dash = note.indexOf(' - ');
        return dash > 0 ? note.substring(0, dash).trim() : note.trim();
    }

    extractRound(note) {
        if (!note) return '';
        const dash = note.indexOf(' - ');
        return dash > 0 ? note.substring(dash + 3).trim() : '';
    }

    handleConferenceFilter(event) {
        this.selectedConference = event.detail.value;
    }

    handleLogoError(event) {
        event.target.style.display = 'none';
    }

    handleNewsImageError(event) {
        event.target.closest('.news-item-image-wrap')?.classList.add('slds-hide');
    }
}
