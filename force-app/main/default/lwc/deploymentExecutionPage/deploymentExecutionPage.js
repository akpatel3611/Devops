import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getDeploymentDetails from '@salesforce/apex/UserStoryWorkspaceController.getDeploymentDetails';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';
import approveAndMergePullRequest from '@salesforce/apex/DeploymentRequestActionController.approveAndMergePullRequest';
import getBuildTabGitDetails from '@salesforce/apex/UserStoryWorkspaceController.getBuildTabGitDetails';
import deployRequest from '@salesforce/apex/DeploymentRequestActionController.deployRequest';
import validateRequest from '@salesforce/apex/DeploymentRequestActionController.validateRequest';
import getPRDetails from '@salesforce/apex/DeploymentRequestActionController.getPRDetails';
import approvePullRequest from '@salesforce/apex/DeploymentRequestActionController.approvePullRequest';
import confirmAndMergePullRequest from '@salesforce/apex/DeploymentRequestActionController.confirmAndMergePullRequest';

const DEBUG_PREFIX = '[deploymentExecutionPage]';

export default class DeploymentExecutionPage extends NavigationMixin(LightningElement) {
    @api recordId;

    @track status = 'Draft';
    @track steps = [];

    // Validation Modal Property
    @track showValidationModal = false;

    // PR Management Properties
    @track prNumber = 12;
    @track prUrl = '';
    @track isApproved = false;
    @track isMerged = false;
    @track hasConflict = false;
    @track isMergeable = true;
    @track featureBranchName = 'feature/US-0029';
    @track showPRControls = true;
    
    // Details (Left Column)
    @track userStoryName = '';
    @track userStoryTitle = '';
    @track projectName = '';
    @track releaseName = '';
    @track credentialName = '';
    @track sourceEnvName = 'DEV';
    @track targetEnvName = 'QA';
    @track userStoryId = '';
    @track gitBranchUrl = '';
    @track gitBranchName = '';

    // Multi-Story Release Support
    @track isMultiStory = false;
    @track headerTitle = '';
    @track linkedStoriesCount = 0;
    @track linkedStoryNames = [];

    _pollingInterval;
    wiredDetailsResult;

    @wire(getDeploymentDetails, { deploymentRequestId: '$recordId' })
    wiredDetails(result) {
        this.wiredDetailsResult = result;
        const { error, data } = result;
        console.debug(`${DEBUG_PREFIX} getDeploymentDetails wire response`, {
            recordId: this.recordId,
            hasData: !!data,
            hasError: !!error
        });
        if (data) {
            this.isMultiStory = !!data.isMultiStory;
            this.headerTitle = data.headerTitle || data.userStoryName || 'Deployment Execution';
            this.userStoryName = data.userStoryName || this.headerTitle;
            this.userStoryTitle = data.userStoryTitle || 'Metadata Selection';
            this.projectName = data.projectName || 'Default Project';
            this.releaseName = data.releaseName || 'Default Release';
            this.credentialName = data.credentialName || 'Default Cred';
            this.sourceEnvName = data.sourceEnvName || 'DEV';
            this.targetEnvName = data.targetEnvName || 'QA';
            this.userStoryId = data.userStoryId;
            this.linkedStoriesCount = data.linkedStoriesCount || 0;
            this.linkedStoryNames = data.linkedStoryNames || [];

            if (data.userStoryId) {
                this.loadGitDetails(data.userStoryId);
            }

            // Start polling as soon as details are retrieved
            this.startPolling();
        } else if (error) {
            console.error(`${DEBUG_PREFIX} Error fetching enqueued deployment details`, this.normalizeError(error), error);
        }
    }

    connectedCallback() {
        if (this.recordId) {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
    }

    get headerDisplayTitle() {
        return this.headerTitle || this.userStoryName || 'Deployment Execution Console';
    }

    loadGitDetails(storyId) {
        getBuildTabGitDetails({ userStoryId: storyId })
            .then(res => {
                if (res) {
                    this.gitBranchName = res.gitBranchName || ('feature/' + this.userStoryName);
                    this.gitBranchUrl = res.gitBranchUrl || '';
                }
            })
            .catch(err => {
                console.error('Error fetching git details:', err);
                this.gitBranchName = 'feature/' + this.userStoryName;
            });
    }

    startPolling() {
        this.stopPolling();
        console.debug(`${DEBUG_PREFIX} start polling deployment status`, { recordId: this.recordId });
        this.pollStatus(); // Immediate first fetch
        this.fetchPRInfo(); // Immediate first PR info fetch
        this._pollingInterval = setInterval(() => {
            this.pollStatus();
            this.fetchPRInfo();
        }, 3000); // Poll database every 3 seconds
    }

    stopPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
            console.debug(`${DEBUG_PREFIX} stop polling deployment status`, { recordId: this.recordId, status: this.status });
        }
    }

    async pollStatus() {
        try {
            console.debug(`${DEBUG_PREFIX} poll status request`, { recordId: this.recordId });
            const result = await getDeploymentStatus({ requestId: this.recordId });
            this.status = result.status || 'Draft';
            console.debug(`${DEBUG_PREFIX} poll status response`, {
                recordId: this.recordId,
                status: this.status,
                logCount: result.logs ? result.logs.length : 0,
                startedOn: result.startedOn,
                completedOn: result.completedOn
            });
            
            // Map the actual Deployment_Log__c records to UI steps
            if (result.logs && result.logs.length > 0) {
                const totalLogs = result.logs.length;
                this.steps = result.logs.map((log, idx) => {
                    const isLast = (idx === totalLogs - 1);
                    const isFailed = (this.status === 'Failed');
                    const isDone = (this.status === 'Completed' || this.status === 'Completed Successfully');
                    
                    let iconClass = 'check-icon';
                    let iconSymbol = '✓';
                    
                    if (isLast && !isDone && !isFailed) {
                        iconClass = 'spinner-icon';
                        iconSymbol = '';
                    } else if (isLast && isFailed) {
                        iconClass = 'error-icon';
                        iconSymbol = '❌';
                    }

                    return {
                        id: log.Id || idx,
                        name: log.Message__c,
                        iconClass: iconClass,
                        iconSymbol: iconSymbol
                    };
                });
            } else {
                const isDone = ['Completed', 'Completed Successfully', 'Validated'].includes(this.status);
                if (isDone) {
                    this.steps = [
                        {
                            id: 'done',
                            name: 'Deployment & Branch Sync Completed Successfully',
                            iconClass: 'check-icon',
                            iconSymbol: '✓'
                        }
                    ];
                } else {
                    this.steps = [
                        {
                            id: 'init',
                            name: 'Initializing deployment connection...',
                            iconClass: 'spinner-icon',
                            iconSymbol: ''
                        }
                    ];
                }
            }

            // Stop polling and Auto-Redirect to User_Story__c record when deployment completes
            if (['Completed', 'Completed Successfully', 'Validated'].includes(this.status)) {
                this.stopPolling();
                this.status = 'Completed Successfully';
                
                const targetRedirectId = this.userStoryId || result.completedDeploymentId;
                const targetObjectApiName = this.userStoryId ? 'User_Story__c' : 'Deployment__c';

                if (targetRedirectId && !this._isRedirecting) {
                    this._isRedirecting = true;
                    console.debug(`${DEBUG_PREFIX} Deployment completed. Auto-redirecting to ${targetObjectApiName} in 3 seconds...`, { targetRedirectId });
                    setTimeout(() => {
                        this[NavigationMixin.Navigate]({
                            type: 'standard__recordPage',
                            attributes: {
                                recordId: targetRedirectId,
                                objectApiName: targetObjectApiName,
                                actionName: 'view'
                            }
                        });
                    }, 3000);
                }
            } else if (['Failed', 'Cancelled'].includes(this.status)) {
                this.stopPolling();
            }
        } catch (error) {
            console.error(`${DEBUG_PREFIX} Error polling deployment status`, this.normalizeError(error), error);
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    get showApproveButton() {
        return this.status === 'Waiting For Pull Request Approval';
    }

    get isFailed() {
        return this.status === 'Failed' || this.status === 'Cancelled' || this.status === 'Validation Failed';
    }

    get failedErrorMessage() {
        if (!this.steps || this.steps.length === 0) return 'Deployment encountered an error during execution.';
        const lastStep = this.steps[this.steps.length - 1];
        return lastStep ? lastStep.name : 'Deployment encountered an unexpected failure.';
    }

    connectedCallback() {
        this.fetchPRInfo();
        this.startPolling();
    }

    fetchPRInfo() {
        if (!this.recordId) return;

        getPRDetails({ deploymentRequestId: this.recordId })
            .then(res => {
                if (res && res.success) {
                    this.prNumber = res.prNumber || 12;
                    this.prUrl = res.prUrl || '';
                    this.isApproved = res.isApproved || false;
                    this.isMerged = res.isMerged || false;
                    this.hasConflict = res.hasConflict || false;
                    this.isMergeable = res.isMergeable !== false;
                    if (res.featureBranch) this.featureBranchName = res.featureBranch;
                }
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} Error fetching PR details:`, err);
            });
    }

    handleOpenPRUrl() {
        if (this.prUrl && this.prUrl.startsWith('http')) {
            window.open(this.prUrl, '_blank');
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Pull Request Link',
                    message: 'GitHub Pull Request is being created or link is unavailable.',
                    variant: 'info'
                })
            );
        }
    }

    @track showTopBanner = true;

    handleDismissBanner() {
        this.showTopBanner = false;
    }

    get bannerClass() {
        if ((this.status === 'Failed' && !this.showValidationModal) || this.status === 'Validation Failed') {
            return 'copado-banner banner-danger';
        }
        if (this.isApproved && this.hasConflict) {
            return 'copado-banner banner-danger';
        }
        if (this.status === 'Completed' || this.status === 'Validated' || this.isMerged || (this.isApproved && !this.hasConflict)) {
            return 'copado-banner banner-success';
        }
        return 'copado-banner banner-warning';
    }

    get bannerMessage() {
        if (this.status === 'Failed' && !this.showValidationModal) {
            return `Deployment Failed! Check the root cause details in the console.`;
        }
        if (this.status === 'Validation Failed') {
            return `Dry-Run Validation Failed! Click "Validate" to run validation check again.`;
        }
        if (this.status === 'Completed') {
            return `Deployment completed successfully! Target environment updated.`;
        }
        if (this.status === 'Validated') {
            return `Dry-Run Validation Passed! Click "Deploy" to execute real deployment into ${this.targetEnvName}.`;
        }
        if (this.isMerged || this.status === 'Merged') {
            return `PR #${this.prNumber} Merged Successfully on GitHub! Click "Deploy" to execute target org deployment into ${this.targetEnvName}.`;
        }
        if (this.isApproved) {
            if (this.hasConflict) {
                return `Merge Conflict Detected in GitHub PR #${this.prNumber}! Please resolve conflicts on GitHub.`;
            }
            return `PR Approved & Clean! Merge Conflict Check Passed. Waiting for final Merge on GitHub.`;
        }
        return `PR Approval Pending: Pull Request #${this.prNumber} is waiting for approval on GitHub.`;
    }

    get isValidatingDisabled() {
        return !this.isMerged || this.hasConflict || this.status === 'Validating' || this.status === 'Deploying' || this.status === 'Completed' || this.status === 'In Progress';
    }

    get isValidated() {
        return this.status === 'Validated';
    }

    get isValidationFailed() {
        return this.status === 'Validation Failed';
    }

    get isRealDeploymentFailed() {
        return this.status === 'Failed';
    }

    get isDeployDisabled() {
        return (!this.isMerged && this.status !== 'Merged' && this.status !== 'Validated') || this.status === 'Deploying' || this.status === 'Completed' || this.status === 'In Progress';
    }

    handleConfirmAndMergePR() {
        if (!this.recordId) return;

        this.steps = [
            {
                id: 'merging',
                name: 'Confirm signal received. Merging PR on GitHub...',
                iconClass: 'spinner-icon',
                iconSymbol: ''
            }
        ];

        confirmAndMergePullRequest({ deploymentRequestId: this.recordId })
            .then(res => {
                if (res && res.success) {
                    this.isMerged = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'PR Merged Successfully',
                            message: 'GitHub Pull Request merged into target branch. Dry-Run Validation is now unlocked!',
                            variant: 'success'
                        })
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Merge Failed',
                            message: res ? res.message : 'Failed to merge PR on GitHub.',
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX} Error merging PR:`, error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Merge Error',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleValidateChanges() {
        if (!this.recordId) return;

        this.showValidationModal = true;
        this.status = 'Validating';
        this.steps = [
            {
                id: 'validating',
                name: 'Initiating Real-Time Dry-Run Check-Only Validation in Target Org...',
                iconClass: 'spinner-icon',
                iconSymbol: ''
            }
        ];

        validateRequest({ requestId: this.recordId })
            .then(res => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Dry-Run Validation Initiated',
                        message: 'Real-time check-only validation queued in Target Org. Target data will not be mutated.',
                        variant: 'info'
                    })
                );
                this.startPolling();
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} Error initiating dry-run validation:`, err);
                this.status = 'Failed';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Validation Trigger Failed',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleCloseValidationModal() {
        this.showValidationModal = false;
    }

    handleDeployRequest() {
        if (!this.recordId) return;

        this.status = 'Deploying';
        this.steps = [
            {
                id: 'starting',
                name: 'Deployment execution request initiated in Target Org...',
                iconClass: 'spinner-icon',
                iconSymbol: ''
            }
        ];

        deployRequest({ requestId: this.recordId })
            .then(res => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Deployment Initiated',
                        message: 'Deployment execution enqueued successfully in Target Org.',
                        variant: 'success'
                    })
                );
                this.startPolling();
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX} Error initiating deployment:`, error);
                this.status = 'Failed';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Deployment Failed',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleGoBack() {
        console.debug(`${DEBUG_PREFIX} close requested`, {
            recordId: this.recordId,
            userStoryId: this.userStoryId
        });
        this.dispatchEvent(new CustomEvent('close', {
            detail: { userStoryId: this.userStoryId }
        }));
    }

    handleRetryDeployment() {
        this.status = 'Deploying';
        this.steps = [
            { id: 'retry', name: 'Re-initiating deployment execution request...', iconClass: 'spinner-icon', iconSymbol: '' }
        ];

        deployRequest({ requestId: this.recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Retry Initiated',
                        message: 'Deployment execution re-queued successfully.',
                        variant: 'info'
                    })
                );
                this.startPolling();
            })
            .catch(err => {
                this.status = 'Failed';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Retry Failed',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleFixAndRecommit() {
        if (this.userStoryId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: {
                    componentName: 'c__userStoryCommitAura'
                },
                state: {
                    c__recordId: this.userStoryId
                }
            });
        } else {
            this.handleGoBack();
        }
    }

    get showGitLink() {
        const isDone = ['Completed', 'Completed Successfully', 'Validated'].includes(this.status);
        return isDone && !!this.gitBranchUrl;
    }

    normalizeError(error) {
        return {
            message: error?.body?.message || error?.message || 'Unknown error',
            status: error?.status,
            statusText: error?.statusText,
            errorType: error?.body?.errorType || error?.errorType
        };
    }
}