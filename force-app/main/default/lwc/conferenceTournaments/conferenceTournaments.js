import { LightningElement, api } from 'lwc';
import getConferenceTournamentSchedule from '@salesforce/apex/MarchMadnessController.getConferenceTournamentSchedule';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ConferenceTournaments extends LightningElement {
    @api tournamentId;

    result = null;
    selectedConf = '';
    isLoading = true;
    isRefreshing = false;
    filterText = '';

    async connectedCallback() {
        await this.loadData();
    }

    async loadData() {
        try {
            this.result = await getConferenceTournamentSchedule();
            this.isLoading = false;
        } catch (error) {
            this.isLoading = false;
            console.error('Conference schedule error:', error);
        }
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await this.loadData();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Schedule Updated',
                message: 'Conference tournament data refreshed from ESPN.',
                variant: 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Refresh Failed',
                message: error.body?.message ?? 'Could not refresh.',
                variant: 'error'
            }));
        } finally {
            this.isRefreshing = false;
        }
    }

    handleFilterChange(event) {
        this.filterText = event.target.value;
    }

    handleConfSelect(event) {
        this.selectedConf = event.currentTarget.dataset.confName;
    }

    // --- Getters ---

    get conferences() {
        return this.result?.conferences ?? [];
    }

    get hasConferences() { return this.conferences.length > 0; }
    get showEmpty() { return !this.isLoading && !this.hasConferences; }
    get hasSelectedConf() { return this.selectedConf !== ''; }
    get asOfTime() { return this.result?.asOfTime ?? ''; }

    get totalGames() { return this.result?.totalGames ?? 0; }
    get totalConferences() { return this.result?.totalConferences ?? 0; }

    get liveCount() {
        return this.conferences.reduce((sum, c) => sum + (c.liveGames ?? 0), 0);
    }
    get completedCount() {
        return this.conferences.reduce((sum, c) => sum + (c.completedGames ?? 0), 0);
    }
    get activeCount() {
        return this.conferences.filter(c => c.liveGames > 0 || (c.completedGames > 0 && c.scheduledGames > 0)).length;
    }
    get finishedCount() {
        return this.conferences.filter(c => c.scheduledGames === 0 && c.liveGames === 0 && c.completedGames > 0).length;
    }
    get upcomingCount() {
        return this.conferences.filter(c => c.completedGames === 0 && c.liveGames === 0).length;
    }

    get filteredConferences() {
        let confs = this.conferences.map(c => ({
            ...c,
            key: c.conferenceName,
            isSelected: c.conferenceName === this.selectedConf,
            cardClass: `conf-card${c.conferenceName === this.selectedConf ? ' selected' : ''}`,
            statusLabel: this.getConfStatus(c),
            statusClass: this.getConfStatusClass(c),
            hasLive: c.liveGames > 0,
            progressText: `${c.completedGames}/${c.totalGames} played`
        }));

        if (this.filterText && this.filterText.length >= 2) {
            const term = this.filterText.toLowerCase();
            confs = confs.filter(c => c.conferenceName.toLowerCase().includes(term));
        }

        return confs.sort((a, b) => {
            if (a.hasLive && !b.hasLive) return -1;
            if (!a.hasLive && b.hasLive) return 1;
            const aActive = a.scheduledGames > 0 && a.completedGames > 0;
            const bActive = b.scheduledGames > 0 && b.completedGames > 0;
            if (aActive && !bActive) return -1;
            if (!aActive && bActive) return 1;
            return a.conferenceName.localeCompare(b.conferenceName);
        });
    }

    get selectedConfData() {
        return this.conferences.find(c => c.conferenceName === this.selectedConf);
    }

    get selectedGames() {
        const conf = this.selectedConfData;
        if (!conf?.games) return [];

        return conf.games.map(g => {
            const isLive = g.state === 'in';
            const isFinal = g.isCompleted === true;

            let statusLabel = '';
            if (isLive) {
                statusLabel = g.displayClock && g.period
                    ? `${g.displayClock} - ${this.periodLabel(g.period)}`
                    : 'LIVE';
            } else if (isFinal) {
                statusLabel = 'Final';
            } else {
                statusLabel = g.statusShortDetail ?? 'Scheduled';
            }

            const awayRank = g.awayRank && g.awayRank <= 25 ? `${g.awayRank} ` : '';
            const homeRank = g.homeRank && g.homeRank <= 25 ? `${g.homeRank} ` : '';
            const roundFromNote = this.extractRound(g.note);

            return {
                key: g.espnId,
                ...g,
                isLive,
                isFinal,
                isScheduled: !isLive && !isFinal,
                statusLabel,
                statusClass: `game-status${isLive ? ' live' : isFinal ? ' final' : ' scheduled'}`,
                awayDisplay: awayRank + (g.awayTeam ?? 'TBD'),
                homeDisplay: homeRank + (g.homeTeam ?? 'TBD'),
                awayScoreDisplay: (isLive || isFinal) ? (g.awayScore ?? '0') : '',
                homeScoreDisplay: (isLive || isFinal) ? (g.homeScore ?? '0') : '',
                awayRowClass: `game-team${g.awayWinner ? ' winner' : ''}`,
                homeRowClass: `game-team${g.homeWinner ? ' winner' : ''}`,
                awayScoreClass: `team-score${isLive ? ' live' : ''}${g.awayWinner ? ' winner' : ''}`,
                homeScoreClass: `team-score${isLive ? ' live' : ''}${g.homeWinner ? ' winner' : ''}`,
                hasAwayLogo: g.awayLogo != null,
                hasHomeLogo: g.homeLogo != null,
                roundLabel: roundFromNote,
                hasBroadcast: g.broadcast != null,
                hasOdds: g.spreadDetail != null
            };
        });
    }

    get hasSelectedGames() { return this.selectedGames.length > 0; }

    get selectedConfStats() {
        const conf = this.selectedConfData;
        if (!conf) return null;
        return {
            total: conf.totalGames,
            completed: conf.completedGames,
            live: conf.liveGames,
            scheduled: conf.scheduledGames,
            champStatus: conf.championshipStatus
        };
    }

    // --- Helpers ---

    getConfStatus(c) {
        if (c.liveGames > 0) return 'LIVE';
        if (c.scheduledGames === 0 && c.completedGames > 0) return 'Complete';
        if (c.completedGames > 0) return 'In Progress';
        return 'Upcoming';
    }

    getConfStatusClass(c) {
        if (c.liveGames > 0) return 'status-badge live';
        if (c.scheduledGames === 0 && c.completedGames > 0) return 'status-badge complete';
        if (c.completedGames > 0) return 'status-badge active';
        return 'status-badge upcoming';
    }

    periodLabel(period) {
        if (period === 1) return '1st';
        if (period === 2) return '2nd';
        if (period > 2) return `OT${period - 2 > 1 ? period - 2 : ''}`;
        return '';
    }

    extractRound(note) {
        if (!note) return '';
        const dash = note.indexOf(' - ');
        return dash > 0 ? note.substring(dash + 3).trim() : '';
    }

    handleLogoError(event) {
        event.target.style.display = 'none';
    }
}
