import { LightningElement, wire } from 'lwc';
import getActiveTournament from '@salesforce/apex/MarchMadnessController.getActiveTournament';
import getTopTeams from '@salesforce/apex/MarchMadnessController.getTopTeams';
import getDashboardStats from '@salesforce/apex/MarchMadnessController.getDashboardStats';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const TABS = {
    DASHBOARD: 'dashboard',
    CONFERENCES: 'conferences',
    BRACKET: 'bracket',
    SCENARIOS: 'scenarios',
    TEAMS: 'teams',
    NEWS: 'news'
};

export default class MarchMadnessApp extends LightningElement {
    tournament;
    tournamentId;
    activeTab = TABS.DASHBOARD;
    selectedGameId;
    selectedTeamId;
    teams = [];
    statsData = {};
    isLoading = true;
    error;

    @wire(getActiveTournament)
    wiredTournament({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.tournament = data;
            this.tournamentId = data.Id;
        } else if (error) {
            this.error = error.body?.message ?? 'Failed to load tournament';
        }
    }

    @wire(getTopTeams, { tournamentId: '$tournamentId', limitCount: 400 })
    wiredTeams({ data }) {
        if (data) {
            this.teams = data.map(t => {
                const hasLogo = t.Logo_URL__c != null && t.Logo_URL__c !== '';
                const color = t.Primary_Color__c ?? '003da5';
                const words = (t.Name ?? '').split(' ');
                const initials = words.length > 1
                    ? (words[0][0] + words[words.length - 1][0]).toUpperCase()
                    : (t.Name ?? '?').substring(0, 2).toUpperCase();
                return {
                    ...t,
                    hasLogo,
                    initials,
                    placeholderStyle: `background-color: #${color};`,
                    record: t.Record_Wins__c != null ? `${t.Record_Wins__c}-${t.Record_Losses__c ?? 0}` : '',
                    seedDisplay: t.Seed__c != null ? `#${t.Seed__c}` : '-',
                    powerDisplay: t.Overall_Power_Rating__c != null ? `${t.Overall_Power_Rating__c}` : '-',
                    isSelected: t.Id === this.selectedTeamId,
                    itemClass: `team-list-item${t.Id === this.selectedTeamId ? ' selected' : ''}`
                };
            });
        }
    }

    @wire(getDashboardStats, { tournamentId: '$tournamentId' })
    wiredStats({ data }) {
        if (data) {
            this.statsData = data;
        }
    }

    get hasTournament() { return this.tournament != null; }
    get showEmptyState() { return !this.isLoading && !this.hasTournament; }
    get tournamentName() { return this.tournament?.Name ?? 'March Madness'; }
    get tournamentStatus() { return this.tournament?.Status__c ?? ''; }
    get tournamentYear() { return this.tournament?.Year__c ?? new Date().getFullYear(); }

    get statusBadgeClass() {
        const status = this.tournamentStatus;
        if (status === 'Active') return 'status-badge active';
        if (status === 'Upcoming') return 'status-badge upcoming';
        return 'status-badge complete';
    }

    get totalPredictions() { return this.statsData.totalPredictions ?? 0; }
    get predictionAccuracy() { return this.statsData.predictionAccuracy ?? 0; }
    get upcomingGames() { return this.statsData.upcomingGames ?? 0; }
    get avgConfidence() { return this.statsData.avgConfidence ?? 0; }

    get isDashboardTab() { return this.activeTab === TABS.DASHBOARD; }
    get isConferencesTab() { return this.activeTab === TABS.CONFERENCES; }
    get isBracketTab() { return this.activeTab === TABS.BRACKET; }
    get isScenariosTab() { return this.activeTab === TABS.SCENARIOS; }
    get isTeamsTab() { return this.activeTab === TABS.TEAMS; }
    get isNewsTab() { return this.activeTab === TABS.NEWS; }

    get tabClass() {
        return (tab) => `tab-btn${this.activeTab === tab ? ' active' : ''}`;
    }
    get dashboardTabClass() { return `tab-btn${this.isDashboardTab ? ' active' : ''}`; }
    get conferencesTabClass() { return `tab-btn${this.isConferencesTab ? ' active' : ''}`; }
    get bracketTabClass() { return `tab-btn${this.isBracketTab ? ' active' : ''}`; }
    get scenariosTabClass() { return `tab-btn${this.isScenariosTab ? ' active' : ''}`; }
    get teamsTabClass() { return `tab-btn${this.isTeamsTab ? ' active' : ''}`; }
    get newsTabClass() { return `tab-btn${this.isNewsTab ? ' active' : ''}`; }

    get hasSelectedGame() { return this.selectedGameId != null; }
    get hasSelectedTeam() { return this.selectedTeamId != null; }
    get hasTeams() { return this.teams.length > 0; }

    get filteredTeams() {
        return this.teams.map(t => ({
            ...t,
            visible: t.visible !== false,
            isSelected: t.Id === this.selectedTeamId,
            itemClass: `team-list-item${t.Id === this.selectedTeamId ? ' selected' : ''}`
        }));
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleGameSelect(event) {
        this.selectedGameId = event.detail.gameId;
    }

    handleTeamSelect(event) {
        this.selectedTeamId = event.currentTarget.dataset.teamId;
    }

    handleTeamSearch(event) {
        const term = event.target.value?.toLowerCase() ?? '';
        if (term.length < 2) {
            this.teams = this.teams.map(t => ({ ...t, visible: true }));
            return;
        }
        this.teams = this.teams.map(t => ({
            ...t,
            visible: t.Name.toLowerCase().includes(term) || (t.Conference__c?.toLowerCase().includes(term) ?? false)
        }));
    }

    handlePredictionComplete() {
        this.showToast('Prediction Updated', 'The prediction has been refreshed.', 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
