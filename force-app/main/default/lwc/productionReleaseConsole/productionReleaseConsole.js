import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDeploymentDetails from '@salesforce/apex/UserStoryWorkspaceController.getDeploymentDetails';
import getPRDetails from '@salesforce/apex/DeploymentRequestActionController.getPRDetails';
import completeDeployment from '@salesforce/apex/UserStoryWorkspaceController.completeDeployment';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';

export default class ProductionReleaseConsole extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track isMultiStory = true;
    @track linkedStoriesCount = 0;
    @track linkedStoryNames = [];
    @track projectName = '';
    @track releaseName = '';
    @track promotionId = null;
    @track promotionName = '';
    @track deploymentId = null;
    @track deploymentName = '';
    @track sourceEnvName = '';
    @track targetEnvName = '';

    // PR & Approval state
    @track prNumber = null;
    @track prUrl = '';
    @track isApproved = false;
    @track isMerged = false;
    @track hasConflict = false;
    @track isPRClosed = false;
    @track hasChangesRequested = false;
    @track wasConflictDetected = false;
    @track mergeableState = '';
    @track showApprovalPhase = false;
    @track showConflictResolvedPhase = false;
    @track isDeploymentComplete = false;

    // Log & Step console state
    @track statusText = 'Waiting for PR Approval';
    @track steps = [
        { id: 'step-1', name: 'Step 1: Waiting for GitHub PR Review & Approval', isComplete: false, isRunning: true },
        { id: 'step-2', name: 'Step 2: Target Production Credentials Verification', isComplete: false, isRunning: false },
        { id: 'step-3', name: 'Step 3: Preparing Deployment Package Payload', isComplete: false, isRunning: false },
        { id: 'step-4', name: 'Step 4: Deploying Metadata Package to Production Org', isComplete: false, isRunning: false },
        { id: 'step-5', name: 'Step 5: Updating User Story Locations & Statuses', isComplete: false, isRunning: false }
    ];
    @track logs = [];

    _pollingInterval;
    _hasTriggeredAutoDeploy = false;

    @wire(getDeploymentDetails, { deploymentRequestId: '$recordId' })
    wiredDetails({ error, data }) {
        if (data) {
            this.isLoading = false;
            this.isMultiStory = !!data.isMultiStory;
            this.linkedStoriesCount = data.linkedStoriesCount || (data.linkedStoryNames ? data.linkedStoryNames.length : 0);
            this.linkedStoryNames = data.linkedStoryNames || [];
            this.sourceEnvName = data.sourceEnvName || 'UAT';
            this.targetEnvName = data.targetEnvName || 'Production';
            if (data.projectName) this.projectName = data.projectName;
            if (data.releaseName) this.releaseName = data.releaseName;
            if (data.promotionId) this.promotionId = data.promotionId;
            if (data.promotionName) this.promotionName = data.promotionName;
            if (data.deploymentId) this.deploymentId = data.deploymentId;
            if (data.deploymentName) this.deploymentName = data.deploymentName;

            this.fetchPRStatus();
            this.startPolling();
        } else if (error) {
            console.error('Error fetching release details:', error);
            this.isLoading = false;
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.fetchPRStatus();
            this.startPolling();
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    fetchPRStatus() {
        if (!this.recordId) return;
        getPRDetails({ deploymentRequestId: this.recordId })
            .then(data => {
                if (data && data.success) {
                    const hadConflict = this.hasConflict;
                    const wasApproved = this.isApproved;
                    this.hasConflict = data.hasConflict || false;
                    this.isApproved = data.isApproved || false;
                    this.isMerged = data.isMerged || false;
                    this.isPRClosed = data.state === 'closed' && !this.isMerged;
                    this.hasChangesRequested = data.changesRequested || false;
                    this.mergeableState = data.mergeableState || '';
                    if (data.prNumber) this.prNumber = data.prNumber;
                    if (data.prUrl) this.prUrl = data.prUrl;
                    if (this.hasConflict) this.wasConflictDetected = true;
                    if (!wasApproved && this.isApproved) {
                        this.showApprovalPhase = true;
                        setTimeout(() => { this.showApprovalPhase = false; }, 3500);
                    }
                    if (hadConflict && !this.hasConflict) {
                        this.showConflictResolvedPhase = true;
                        setTimeout(() => { this.showConflictResolvedPhase = false; }, 3500);
                    }

                    this.updateLifecycle();
                    if (this.isMerged && !this._hasTriggeredAutoDeploy) {
                        this._hasTriggeredAutoDeploy = true;
                        this.triggerRealTimeProductionDeployment();
                    }
                }
            })
            .catch(err => {
                console.warn('Error fetching PR details:', err);
            });
    }

    updateLifecycle() {
        if (this.isDeploymentComplete) {
            this.statusText = 'Phase 7: Deployment Completed Successfully';
        } else if (this.isMerged) {
            this.statusText = 'Phase 7: Pull Request Merged - Deployment Initiated';
        } else if (this.isPRClosed) {
            this.statusText = 'Pull Request Closed or Reverted on GitHub';
        } else if (!this.hasPullRequest) {
            this.statusText = 'Phase 1: Verifying Pull Request Creation';
        } else if (!this.isApproved) {
            this.statusText = 'Phase 2: Awaiting Pull Request Approval';
        } else if (this.showApprovalPhase) {
            this.statusText = 'Phase 3: Pull Request Approved';
        } else if (this.hasConflict) {
            this.statusText = 'Phase 4: Merge Conflict Detected - Action Required';
        } else if (this.showConflictResolvedPhase) {
            this.statusText = 'Phase 5: Merge Conflict Resolved Successfully';
        } else {
            this.statusText = 'Phase 6: Awaiting Final Merge Approval';
        }
    }

    triggerRealTimeProductionDeployment() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'GitHub PR Merged!',
                message: 'Production Deployment automatically started in real-time. Streaming live logs...',
                variant: 'success'
            })
        );

        completeDeployment({ deploymentRequestId: this.recordId })
            .then(() => {
                this.startPolling();
            })
            .catch(err => {
                console.error('Error triggering production deployment:', err);
            });
    }

    startPolling() {
        this.stopPolling();
        this._pollingInterval = setInterval(() => {
            this.fetchPRStatus();
            this.fetchDeploymentLogs();
        }, 3500);
    }

    stopPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
        }
    }

    fetchDeploymentLogs() {
        if (!this.recordId) return;
        getDeploymentStatus({ requestId: this.recordId })
            .then(res => {
                if (res && res.logs && res.logs.length > 0) {
                    this.logs = res.logs.map((log, idx) => {
                        const logType = log.Log_Type__c || log.type || 'Info';
                        let cssClass = 'log-info';
                        const lowerType = logType.toLowerCase();
                        if (lowerType.includes('error') || lowerType.includes('fail')) {
                            cssClass = 'log-error';
                        } else if (lowerType.includes('warn')) {
                            cssClass = 'log-warn';
                        } else if (lowerType.includes('success') || lowerType.includes('complete')) {
                            cssClass = 'log-success';
                        }
                        
                        return {
                            id: log.Id || log.id || 'log-' + idx,
                            text: this.formatLog(log),
                            class: cssClass
                        };
                    });
                }
                if (res && (res.status === 'Completed' || res.status === 'Completed Successfully')) {
                    this.isDeploymentComplete = true;
                    this.updateLifecycle();
                }
            })
            .catch(err => {
                console.warn('Error fetching deployment logs:', err);
            });
    }

    formatLog(log) {
        if (typeof log === 'string') return log;
        const timestamp = log.Timestamp__c || log.timestamp || '';
        const logType = log.Log_Type__c || log.type || 'Info';
        let message = log.Message__c || log.message || '';

        // Shorten verbose deployment logs dynamically
        if (message.includes('Successfully deployed component:')) {
            message = message.replace('Successfully deployed component:', 'Deployed ➔');
        } else if (message.includes('Started deployment validation for request')) {
            message = 'Initializing dry-run validation check...';
        }

        if (timestamp) {
            try {
                const date = new Date(timestamp);
                const timeStr = date.toTimeString().split(' ')[0];
                return `[${timeStr}] [${logType.toUpperCase()}] ${message}`;
            } catch (e) {
                // Fallback
            }
        }
        return `[${logType.toUpperCase()}] ${message}`;
    }

    // Dynamic Banner computed getters (7-Phase PR & Merge Lifecycle)
    get bannerClass() {
        if (this.isDeploymentComplete || this.isMerged) return 'copado-banner banner-green';
        if (this.isPRClosed || this.hasConflict) return 'copado-banner banner-red';
        if (this.showConflictResolvedPhase) return 'copado-banner banner-teal';
        if (this.isApproved) return 'copado-banner banner-indigo';
        return 'copado-banner banner-blue';
    }

    get bannerIcon() {
        if (this.isMerged || this.isApproved) return '✓';
        if (this.hasConflict || this.isPRClosed) return '✖';
        return 'ℹ';
    }

    get bannerMessage() {
        if (this.isDeploymentComplete) {
            return 'Phase 7: Deployment Completed Successfully';
        }
        if (this.isMerged) {
            return 'Phase 7: Pull Request Merged - Deployment Initiated';
        }
        if (this.isPRClosed) {
            return 'Pull Request Closed or Reverted on GitHub';
        }
        if (this.hasConflict) {
            return 'Phase 4: Merge Conflict Detected - Action Required';
        }
        if (this.isApproved) {
            if (this.showApprovalPhase) return 'Phase 3: Pull Request Approved';
            if (this.showConflictResolvedPhase) return 'Phase 5: Merge Conflict Resolved Successfully';
            return 'Phase 6: Awaiting Final Merge Approval';
        }
        if (this.hasPullRequest) {
            return 'Phase 2: Awaiting Pull Request Approval';
        }
        return 'Phase 1: Verifying Pull Request Creation';
    }

    get hasPullRequest() {
        return !!(this.prNumber || (this.prUrl && this.prUrl.includes('/pull/')));
    }

    get pullRequestLinkText() {
        return this.prNumber ? 'View Pull Request #' + this.prNumber + ' ↗' : 'View Pull Request ↗';
    }

    get pullRequestDetailText() {
        const label = this.prNumber ? '#' + this.prNumber : 'Pull Request';
        return label + ': ' + this.sourceEnvName + ' ➔ main ↗';
    }

    get headerDisplayTitle() {
        return 'Release: ' + this.releaseName + ' (' + this.linkedStoriesCount + ' User Stories)';
    }

    get hasLogs() {
        return this.logs && this.logs.length > 0;
    }

    handleOpenPromotion() {
        if (this.promotionId) window.open('/' + this.promotionId, '_blank');
    }

    handleOpenDeployment() {
        if (this.deploymentId) window.open('/' + this.deploymentId, '_blank');
    }

    handleReturnToPdCreator() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}