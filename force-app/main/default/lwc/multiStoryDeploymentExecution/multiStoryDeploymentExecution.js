import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDeploymentDetails from '@salesforce/apex/UserStoryWorkspaceController.getDeploymentDetails';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';
import approveAndMergePullRequest from '@salesforce/apex/DeploymentRequestActionController.approveAndMergePullRequest';
import deployRequest from '@salesforce/apex/DeploymentRequestActionController.deployRequest';
import getPRDetails from '@salesforce/apex/DeploymentRequestActionController.getPRDetails';
import approvePullRequest from '@salesforce/apex/DeploymentRequestActionController.approvePullRequest';
import confirmAndMergePullRequest from '@salesforce/apex/DeploymentRequestActionController.confirmAndMergePullRequest';

export default class MultiStoryDeploymentExecution extends NavigationMixin(LightningElement) {
    @api recordId;

    @track status = 'Draft';
    @track steps = [];

    // PR Management Properties
    @track prNumber = 12;
    @track prUrl = '';
    @track isApproved = false;
    @track hasConflict = false;
    @track isMergeable = true;
    @track isMultiStory = true;
    @track headerTitle = 'Multi-Story Production Release';
    @track sourceEnvName = 'UAT';
    @track targetEnvName = 'PROD';
    @track projectName = '';
    @track releaseName = '';
    @track credentialName = '';
    @track userStoryName = '';
    @track userStoryTitle = '';
    @track deploymentRequestId = '';
    @track isProcessing = false;
    @track isApproveLoading = false;
    @track isDeployLoading = false;

    _pollingInterval;
    wiredDetailsResult;

    @wire(getDeploymentDetails, { deploymentRequestId: '$recordId' })
    wiredDetails(result) {
        this.wiredDetailsResult = result;
        const { error, data } = result;
        if (data) {
            this.deploymentRequestId = data.recordId || data.deploymentRequestId || this.recordId;
            this.isMultiStory = true;
            this.headerTitle = data.headerTitle || 'Multi-Story Production Release';
            this.sourceEnvName = data.sourceEnvName || 'UAT';
            this.targetEnvName = data.targetEnvName || 'PROD';
            this.projectName = data.projectName || '';
            this.releaseName = data.releaseName || '';
            this.credentialName = data.credentialName || '';
            this.userStoryName = data.userStoryName || '';
            this.userStoryTitle = data.userStoryTitle || '';
            this.linkedStoriesCount = data.linkedStoriesCount || 0;
            this.linkedStoryNames = data.linkedStoryNames || [];
            
            if (data.status) {
                this.status = data.status;
            }
        } else if (error) {
            console.error('Error fetching deployment details:', error);
        }
    }

    connectedCallback() {
        this.fetchStatus();
        this.startPolling();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    startPolling() {
        this.stopPolling();
        this._pollingInterval = setInterval(() => {
            this.fetchStatus();
        }, 3000);
    }

    stopPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
        }
    }

    fetchStatus() {
        const targetReqId = this.deploymentRequestId || this.recordId;
        if (!targetReqId) return;

        getDeploymentStatus({ deploymentRequestId: targetReqId })
            .then(data => {
                if (data) {
                    this.status = data.status || this.status;
                    this.steps = data.steps || [];

                    const isInProgress = (
                        this.status === 'In Progress' ||
                        this.status === 'Deploying' ||
                        this.status === 'Queued' ||
                        this.status === 'Waiting For Pull Request Approval'
                    );

                    if (!isInProgress && this.status !== 'Draft') {
                        this.stopPolling();
                    }
                }
            })
            .catch(err => {
                console.error('Error polling deployment status:', err);
            });
    }

    get isWaitingPR() {
        return this.status === 'Waiting For Pull Request Approval' || this.status === 'Draft' || this.status === 'Pending';
    }

    get isDeploying() {
        return this.status === 'In Progress' || this.status === 'Deploying' || this.status === 'Queued';
    }

    get isCompleted() {
        return this.status === 'Completed';
    }

    get isFailed() {
        return this.status === 'Failed';
    }

    get isDeployDisabled() {
        return this.isProcessing || this.isDeploying || this.isCompleted;
    }

    get isConfirmMergeDisabled() {
        return !this.isApproved || this.hasConflict || this.isProcessing || this.isDeploying || this.isCompleted;
    }

    get overallPercent() {
        if (!this.steps || this.steps.length === 0) return 0;
        let total = 0;
        let comp = 0;
        this.steps.forEach(st => {
            total++;
            if (st.status === 'Completed') comp++;
            else if (st.status === 'In Progress') comp += 0.5;
        });
        return Math.round((comp / total) * 100);
    }

    get progressBarStyle() {
        return `width: ${this.overallPercent}%;`;
    }

    handleApprovePR() {
        const targetReqId = this.deploymentRequestId || this.recordId;
        if (!targetReqId) return;

        approvePullRequest({ deploymentRequestId: targetReqId })
            .then(res => {
                if (res && res.success) {
                    this.isApproved = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'PR Approved',
                            message: res.message || 'Pull Request approved successfully.',
                            variant: 'success'
                        })
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Approval Failed',
                            message: res ? res.message : 'Unknown error',
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(err => {
                console.error('Error approving PR:', err);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleConfirmAndMergePR() {
        const targetReqId = this.deploymentRequestId || this.recordId;
        if (!targetReqId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Loading Context',
                    message: 'Deployment details are loading. Please wait a moment and try again.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isProcessing = true;
        this.isApproveLoading = true;

        confirmAndMergePullRequest({ deploymentRequestId: targetReqId })
            .then(res => {
                this.isProcessing = false;
                this.isApproveLoading = false;
                if (res && res.success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Merge & Deploy Initiated',
                            message: res.message || 'Production deployment initiated successfully.',
                            variant: 'success'
                        })
                    );
                    this.startPolling();
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Merge Failed',
                            message: res ? res.message : 'Unknown error',
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(error => {
                this.isProcessing = false;
                this.isApproveLoading = false;
                console.error('Error during Confirm & Merge PR:', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleApproveAndDeploy() {
        const targetReqId = this.deploymentRequestId || this.recordId;
        if (!targetReqId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Loading Context',
                    message: 'Deployment details are loading. Please wait a moment and try again.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isProcessing = true;
        this.isApproveLoading = true;

        approveAndMergePullRequest({ deploymentRequestId: targetReqId })
            .then(() => {
                this.isProcessing = false;
                this.isApproveLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Deployment Initiated',
                        message: 'Production deployment initiated successfully.',
                        variant: 'success'
                    })
                );
                this.startPolling();
            })
            .catch(error => {
                this.isProcessing = false;
                this.isApproveLoading = false;
                console.error('Error during Approve & Deploy:', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleRefresh() {
        this.fetchStatus();
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Refreshed',
                message: 'Status refreshed successfully.',
                variant: 'info'
            })
        );
    }

    handleBackToReleaseConsole() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Multi_Story_Release_Console'
            }
        });
    }
}