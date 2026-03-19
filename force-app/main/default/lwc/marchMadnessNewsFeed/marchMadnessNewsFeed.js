import { LightningElement, api, wire } from 'lwc';
import getLatestNews from '@salesforce/apex/MarchMadnessController.getLatestNews';
import getNewsForTeam from '@salesforce/apex/MarchMadnessController.getNewsForTeam';
import refreshTeamResearch from '@salesforce/apex/MarchMadnessController.refreshTeamResearch';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const PAGE_SIZE = 10;

export default class MarchMadnessNewsFeed extends LightningElement {
    @api teamId;
    @api limitCount = 20;

    articles = [];
    displayCount = PAGE_SIZE;
    searchTerm = '';
    sentimentFilter = '';
    categoryFilter = '';
    isLoading = true;
    isRefreshing = false;
    wiredNewsResult;

    get useTeamFilter() {
        return this.teamId != null;
    }

    @wire(getLatestNews, { limitCount: '$effectiveLimit' })
    wiredAllNews(result) {
        if (this.useTeamFilter) return;
        this.wiredNewsResult = result;
        this.handleWireResult(result);
    }

    @wire(getNewsForTeam, { teamId: '$teamId' })
    wiredTeamNews(result) {
        if (!this.useTeamFilter) return;
        this.wiredNewsResult = result;
        this.handleWireResult(result);
    }

    handleWireResult({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.articles = data.map(a => this.enrichArticle(a));
        } else if (error) {
            this.articles = [];
            this.showToast('Error', error.body?.message ?? 'Failed to load news', 'error');
        }
    }

    get effectiveLimit() {
        return this.limitCount ?? 20;
    }

    enrichArticle(article) {
        const score = article.Sentiment_Score__c ?? 0;
        const isPositive = score > 30;
        const isNegative = score < -30;
        let sentimentLabel = 'Neutral';
        if (isPositive) sentimentLabel = 'Positive';
        if (isNegative) sentimentLabel = 'Negative';

        const pubDate = article.Article_Date__c;
        let formattedDate = '';
        if (pubDate) {
            const d = new Date(pubDate);
            formattedDate = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
        }

        const isVerified = article.Is_Verified__c === true;
        const sourceType = article.Source_Type__c ?? 'AI Analysis';

        const imageUrl = article.Image_URL__c ?? '';
        const hasImage = imageUrl.length > 0;

        return {
            ...article,
            headline: article.Name,
            hasTeam: article.Team__r != null,
            teamName: article.Team__r?.Name ?? '',
            teamLogo: article.Team__r?.Logo_URL__c ?? '',
            hasImage,
            imageUrl,
            isPositive,
            isNegative,
            isNeutral: !isPositive && !isNegative,
            sentimentLabel,
            sentimentValue: score,
            formattedDate,
            relevanceDisplay: article.Relevance_Score__c != null ? `${Math.round(article.Relevance_Score__c)}` : '',
            isVerified,
            sourceType,
            sourceTypeClass: `source-badge ${sourceType === 'ESPN' ? 'espn' : sourceType === 'Google Search' ? 'google' : 'ai'}`,
            verifiedTitle: isVerified ? 'Verified real-world source' : 'AI-generated analysis'
        };
    }

    get filteredArticles() {
        let result = [...this.articles];

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            result = result.filter(a =>
                (a.headline ?? '').toLowerCase().includes(term) ||
                (a.Summary__c ?? '').toLowerCase().includes(term) ||
                (a.teamName ?? '').toLowerCase().includes(term)
            );
        }

        if (this.sentimentFilter) {
            result = result.filter(a => a.sentimentLabel === this.sentimentFilter);
        }

        if (this.categoryFilter) {
            result = result.filter(a => a.Category__c === this.categoryFilter);
        }

        return result;
    }

    get visibleArticles() {
        return this.filteredArticles.slice(0, this.displayCount);
    }

    get hasArticles() {
        return this.filteredArticles.length > 0;
    }

    get canLoadMore() {
        return this.displayCount < this.filteredArticles.length;
    }

    get sentimentOptions() {
        return [
            { label: 'All Sentiments', value: '' },
            { label: 'Positive', value: 'Positive' },
            { label: 'Neutral', value: 'Neutral' },
            { label: 'Negative', value: 'Negative' }
        ];
    }

    get categoryOptions() {
        const cats = new Set(this.articles.map(a => a.Category__c).filter(Boolean));
        const options = [{ label: 'All Categories', value: '' }];
        [...cats].sort().forEach(c => options.push({ label: c, value: c }));
        return options;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.displayCount = PAGE_SIZE;
    }

    handleSentimentChange(event) {
        this.sentimentFilter = event.detail.value;
        this.displayCount = PAGE_SIZE;
    }

    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
        this.displayCount = PAGE_SIZE;
    }

    handleLoadMore() {
        this.displayCount += PAGE_SIZE;
    }

    handleImageError(event) {
        event.target.closest('.card-image-container')?.classList.add('slds-hide');
    }

    handleArticleClick(event) {
        const articleId = event.currentTarget.dataset.articleId;
        const article = this.articles.find(a => a.Id === articleId);
        if (article?.Source_URL__c) {
            window.open(article.Source_URL__c, '_blank', 'noopener');
        }
    }

    async handleRefreshNews() {
        if (!this.teamId) {
            this.showToast('Info', 'Select a team to refresh research', 'info');
            return;
        }
        this.isRefreshing = true;
        try {
            await refreshTeamResearch({ teamId: this.teamId });
            await refreshApex(this.wiredNewsResult);
            this.showToast('Success', 'News refresh initiated', 'success');
        } catch (error) {
            this.showToast('Error', error.body?.message ?? 'Failed to refresh news', 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
