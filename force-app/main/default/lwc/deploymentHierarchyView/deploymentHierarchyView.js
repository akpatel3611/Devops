import { LightningElement, api, wire, track } from 'lwc';
import getDeploymentHierarchy from '@salesforce/apex/DeploymentDetailController.getDeploymentHierarchy';

export default class DeploymentHierarchyView extends LightningElement {
    @api recordId;

    @track hierarchyData;
    @track isLoading = true;
    @track isDeploymentExpanded = true;
    @track expandedStoryIds = [];

    @wire(getDeploymentHierarchy, { deploymentId: '$recordId' })
    wiredHierarchy(result) {
        if (result.data) {
            this.processHierarchyData(result.data);
        } else if (result.error) {
            console.error('Error loading deployment hierarchy via wire:', result.error);
            this.isLoading = false;
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadHierarchyImperatively();
        }
    }

    loadHierarchyImperatively() {
        getDeploymentHierarchy({ deploymentId: this.recordId })
            .then(data => {
                if (data) {
                    this.processHierarchyData(data);
                }
            })
            .catch(error => {
                console.error('Imperative load error:', error);
                this.isLoading = false;
            });
    }

    processHierarchyData(data) {
        const stories = data.userStories || [];

        // By default, expand the first story if none are currently tracked
        if (!this.expandedStoryIds || this.expandedStoryIds.length === 0) {
            if (stories.length > 0) {
                this.expandedStoryIds = [stories[0].id];
            }
        }

        const processedStories = stories.map(s => {
            const isExp = this.expandedStoryIds.includes(s.id);
            const metadataList = (s.metadataList || []).map(m => ({
                ...m,
                actionPillClass: this.getActionPillClass(m.action),
                statusPillClass: this.getMetaStatusPillClass(m.status)
            }));

            return {
                ...s,
                isExpanded: isExp,
                toggleIcon: isExp ? 'utility:chevrondown' : 'utility:chevrondown',
                buttonSymbol: isExp ? 'v' : '+',
                hasMetadata: metadataList.length > 0,
                metadataCount: metadataList.length,
                gitButtonDisabled: !s.gitUrl,
                statusPillClass: this.getStoryStatusPillClass(s.status),
                metadataList: metadataList
            };
        });

        this.hierarchyData = {
            ...data,
            statusPillClass: this.getDeploymentStatusPillClass(data.status),
            storiesSummaryText: `${data.totalUserStories || stories.length} stories, ${data.totalComponents || 0} components`,
            userStories: processedStories
        };

        this.isLoading = false;
    }

    toggleDeployment() {
        this.isDeploymentExpanded = !this.isDeploymentExpanded;
    }

    toggleStory(event) {
        const storyId = event.currentTarget.dataset.id;
        if (!storyId) return;

        if (this.expandedStoryIds.includes(storyId)) {
            this.expandedStoryIds = this.expandedStoryIds.filter(id => id !== storyId);
        } else {
            this.expandedStoryIds = [...this.expandedStoryIds, storyId];
        }

        if (this.hierarchyData && this.hierarchyData.userStories) {
            this.hierarchyData.userStories = this.hierarchyData.userStories.map(s => {
                const isExp = this.expandedStoryIds.includes(s.id);
                return {
                    ...s,
                    isExpanded: isExp,
                    buttonSymbol: isExp ? 'v' : '+'
                };
            });
        }
    }

    get hasData() {
        return this.hierarchyData && this.hierarchyData.userStories && this.hierarchyData.userStories.length > 0;
    }

    getDeploymentStatusPillClass(status) {
        const st = (status || '').toLowerCase();
        if (st === 'completed' || st === 'success') return 'status-pill status-pill_success';
        if (st === 'in progress' || st === 'pending') return 'status-pill status-pill_inprogress';
        if (st === 'failed' || st === 'error' || st === 'cancelled') return 'status-pill status-pill_failed';
        return 'status-pill status-pill_inprogress';
    }

    getStoryStatusPillClass(status) {
        const st = (status || '').toLowerCase();
        if (st === 'ready for deployment' || st === 'completed' || st === 'success') return 'status-pill status-pill_success';
        if (st === 'in progress' || st === 'pending') return 'status-pill status-pill_inprogress';
        if (st === 'merged' || st === 'done') return 'status-pill status-pill_neutral';
        if (st === 'failed' || st === 'error') return 'status-pill status-pill_failed';
        return 'status-pill status-pill_neutral';
    }

    getActionPillClass(action) {
        const act = (action || '').toLowerCase();
        if (act === 'add' || act === 'create') return 'table-pill table-pill_neutral';
        if (act === 'modify' || act === 'edit' || act === 'update') return 'table-pill table-pill_neutral';
        if (act === 'delete' || act === 'remove') return 'table-pill table-pill_neutral';
        return 'table-pill table-pill_neutral';
    }

    getMetaStatusPillClass(status) {
        const st = (status || '').toLowerCase();
        if (st === 'success' || st === 'selected' || st === 'included' || st === 'completed') return 'table-pill table-pill_neutral';
        if (st === 'in progress' || st === 'pending') return 'table-pill table-pill_inprogress';
        if (st === 'failed' || st === 'error') return 'table-pill table-pill_failed';
        return 'table-pill table-pill_neutral';
    }

    handleOpenGit(event) {
        const gitUrl = event.currentTarget.dataset.url;
        if (gitUrl) {
            window.open(gitUrl, '_blank');
        }
    }
}