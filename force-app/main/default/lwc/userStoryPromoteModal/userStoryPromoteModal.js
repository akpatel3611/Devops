import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import promoteStoryToNextStage from '@salesforce/apex/UserStoryWorkspaceController.promoteStoryToNextStage';
import getPromotionActionContext from '@salesforce/apex/UserStoryWorkspaceController.getPromotionActionContext';
import getDeploymentDetails from '@salesforce/apex/UserStoryWorkspaceController.getDeploymentDetails';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';
import getPRDetails from '@salesforce/apex/DeploymentRequestActionController.getPRDetails';
import getPayloadPreview from '@salesforce/apex/CommitChangesRuntimeService.getPayloadPreview';
import completeDeployment from '@salesforce/apex/UserStoryWorkspaceController.completeDeployment';

export default class UserStoryPromoteModal extends LightningElement {
    @api recordId;
    
    @track isLoading = true;
    @track isProcessing = false;
    @track isExecuting = false;
    @track isPromoteAvailable = true;
    @track currentEnv = 'QA';
    @track targetEnv = 'UAT';
    @track headerText = 'QA ➔ UAT Staging';
    @track buttonLabel = 'Confirm Merge & Deploy to UAT';
    @track deploymentRequestId = '';

    // Inspect Payload state
    @track isPayloadConsoleOpen = false;
    @track isLoadingPayload = false;
    @track payloadPreviewItems = [];
    @track isPayloadInspected = false;

    // PR & Conflict state
    @track prUrl = 'https://github.com/akpatel3611/Devops/compare/uat...qa';
    @track baseBranch = 'qa';
    @track targetBranch = 'uat';
    @track isCheckingConflicts = true;
    @track hasConflict = false;
    @track wasConflictDetected = false;
    @track isConflictClean = true;
    @track isMergedOnGithub = false;
    @track isClosedOnGithub = false;
    @track prNumber = null;
    @track conflictMessage = '';

    // Live Execution Console state
    @track executionStatus = 'Initializing';
    @track steps = [];
    @track failedErrorMessage = '';
    
    _pollingInterval;

    connectedCallback() {
        if (this.recordId) {
            this.loadActionContext();
        }
    }

    disconnectedCallback() {
        console.log('[userStoryPromoteModal.disconnectedCallback] START - stopping polling for recordId:', this.recordId);
        this.stopPolling();
    }

    loadActionContext() {
        console.log('[userStoryPromoteModal.loadActionContext] START - recordId:', this.recordId);
        this.isLoading = true;
        getPromotionActionContext({ userStoryId: this.recordId })
            .then(ctx => {
                this.isLoading = false;
                if (ctx) {
                    this.isPromoteAvailable = ctx.isPromoteAvailable;
                    this.currentEnv = ctx.currentEnvironment || 'DEV';
                    this.targetEnv = ctx.targetEnvironment || 'QA';
                    this.headerText = ctx.headerText || `${this.currentEnv} ➔ ${this.targetEnv}`;
                    this.buttonLabel = ctx.buttonLabel || `Confirm Merge & Deploy to ${this.targetEnv}`;
                    this.baseBranch = (this.currentEnv || 'QA').toUpperCase();
                    this.targetBranch = (this.targetEnv || 'UAT').toUpperCase();
                    this.prUrl = `https://github.com/akpatel3611/Devops/compare/${this.targetBranch}...${this.baseBranch}`;
                    console.log('[userStoryPromoteModal.loadActionContext] SUCCESS - Context:', ctx);
                }
            })
            .catch(err => {
                console.error('[userStoryPromoteModal.loadActionContext] Error loading promotion context:', err);
                this.isLoading = false;
            });
    }

    async handleInspectPayload() {
        console.log('[userStoryPromoteModal.handleInspectPayload] START - recordId:', this.recordId);
        this.isPayloadConsoleOpen = true;
        this.isLoadingPayload = true;
        try {
            const items = await getPayloadPreview({ userStoryId: this.recordId });
            this.payloadPreviewItems = items || [];
            console.log('[userStoryPromoteModal.handleInspectPayload] SUCCESS - Items count:', this.payloadPreviewItems.length);
        } catch (err) {
            console.error('[userStoryPromoteModal.handleInspectPayload] Error fetching payload preview:', err);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Payload Error',
                    message: err.body ? err.body.message : err.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoadingPayload = false;
        }
    }

    handleApprovePayload() {
        console.log('[userStoryPromoteModal.handleApprovePayload] START - approving payload. itemCount:', this.payloadFileCount);
        this.isPayloadInspected = true;
        this.isPayloadConsoleOpen = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Payload Approved!',
                message: 'Target promotion payload has been verified and approved.',
                variant: 'success'
            })
        );
        console.log('[userStoryPromoteModal.handleApprovePayload] SUCCESS - payload approved for recordId:', this.recordId);
    }

    handleClosePayloadConsole() {
        console.log('[userStoryPromoteModal.handleClosePayloadConsole] START - closing payload console for recordId:', this.recordId);
        this.isPayloadConsoleOpen = false;
    }

    get isInspectPayloadDisabled() {
        return this.isProcessing;
    }

    get isDeployDisabled() {
        return !this.isPayloadInspected || this.isProcessing;
    }

    _hasTriggeredDeployment = false;

    handleConfirmPromote() {
        console.log('[userStoryPromoteModal.handleConfirmPromote] START - recordId:', this.recordId, 'isPromoteAvailable:', this.isPromoteAvailable, 'payloadInspected:', this.isPayloadInspected);
        if (!this.recordId || !this.isPromoteAvailable) {
            console.warn('[userStoryPromoteModal.handleConfirmPromote] Warning: Promotion blocked by missing recordId or unavailable action.', {
                recordId: this.recordId,
                isPromoteAvailable: this.isPromoteAvailable
            });
            return;
        }

        this.isProcessing = true;
        this._hasTriggeredDeployment = false;
        promoteStoryToNextStage({ userStoryId: this.recordId })
            .then(result => {
                this.isProcessing = false;
                console.log('[userStoryPromoteModal.handleConfirmPromote] promoteStoryToNextStage response:', result);
                if (result.success && result.deploymentRequestId) {
                    this.deploymentRequestId = result.deploymentRequestId;
                    this.isExecuting = true;
                    this.isCheckingConflicts = true;
                    this.hasConflict = false;
                    this.wasConflictDetected = false;
                    this.isMergedOnGithub = false;
                    this.isClosedOnGithub = false;
                    this.executionStatus = 'Deploying';
                    console.log('[userStoryPromoteModal.handleConfirmPromote] SUCCESS - promotion initiated:', {
                        recordId: this.recordId,
                        deploymentRequestId: this.deploymentRequestId,
                        prUrl: result.prUrl
                    });
                    
                    if (result.prUrl) {
                        this.prUrl = result.prUrl;
                        window.open(result.prUrl, '_blank');
                    }

                    // Initial fetch for PR & Conflict details
                    getPRDetails({ deploymentRequestId: this.deploymentRequestId })
                        .then(prInfo => {
                            if (prInfo) {
                                this.hasConflict = prInfo.hasConflict || false;
                                this.isMergedOnGithub = prInfo.isMerged || false;
                                if (prInfo.prUrl) this.prUrl = prInfo.prUrl;
                            }
                        })
                        .catch(prErr => {
                            console.warn('Error fetching PR details:', prErr);
                        });

                    this.startPollingExecutionDetails();
                } else {
                    console.warn('[userStoryPromoteModal.handleConfirmPromote] Warning: Promotion did not initiate successfully:', result);
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Promotion Failed',
                            message: result.message || 'Could not initiate promotion.',
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(error => {
                console.error('[userStoryPromoteModal.handleConfirmPromote] Imperative call failed:', error);
                this.isProcessing = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    startPollingExecutionDetails() {
        console.log('[userStoryPromoteModal.startPollingExecutionDetails] START - deploymentRequestId:', this.deploymentRequestId);
        this.pollDeploymentDetails();
        this._pollingInterval = setInterval(() => {
            this.pollDeploymentDetails();
        }, 2500);
    }

    pollDeploymentDetails() {
        if (!this.deploymentRequestId) {
            console.warn('[userStoryPromoteModal.pollDeploymentDetails] Warning: deploymentRequestId missing. Poll skipped.');
            return;
        }

        // Poll live GitHub PR & conflict status
        getPRDetails({ deploymentRequestId: this.deploymentRequestId })
            .then(prInfo => {
                if (prInfo) {
                    console.log('[userStoryPromoteModal.pollDeploymentDetails] PR status received:', {
                        deploymentRequestId: this.deploymentRequestId,
                        prNumber: prInfo.prNumber,
                        state: prInfo.state,
                        isMerged: prInfo.isMerged,
                        hasConflict: prInfo.hasConflict
                    });
                    this.isMergedOnGithub = prInfo.isMerged || false;
                    this.isClosedOnGithub = prInfo.state === 'closed' && !this.isMergedOnGithub;
                    if (prInfo.prUrl) this.prUrl = prInfo.prUrl;
                    if (prInfo.prNumber) this.prNumber = prInfo.prNumber;

                    if (prInfo.mergeable === null && !this.isMergedOnGithub && !this.isClosedOnGithub) {
                        this.isCheckingConflicts = true;
                    } else {
                        this.isCheckingConflicts = false;
                        this.hasConflict = prInfo.hasConflict || false;
                        if (this.hasConflict) {
                            this.wasConflictDetected = true;
                        }
                    }

                    if (this.isClosedOnGithub) {
                        console.warn('[userStoryPromoteModal.pollDeploymentDetails] Warning: Pull Request closed without merge.', {
                            deploymentRequestId: this.deploymentRequestId,
                            prNumber: this.prNumber
                        });
                        this.stopPolling();
                        this.executionStatus = 'Failed';
                        this.failedErrorMessage = 'Pull Request was closed or declined on GitHub without merging. Promotion cancelled.';
                        this.steps = [
                            ...this.steps,
                            { id: 'closed', name: '✕ Pull Request closed/declined on GitHub without merge.', isFailed: true }
                        ];
                    }

                    // Trigger target org deployment ONLY AFTER PR is merged on GitHub
                    if (this.isMergedOnGithub && !this._hasTriggeredDeployment) {
                        this._hasTriggeredDeployment = true;
                        console.log('[userStoryPromoteModal.pollDeploymentDetails] START - completing deployment after GitHub merge:', this.deploymentRequestId);
                        completeDeployment({ deploymentRequestId: this.deploymentRequestId })
                            .then(() => {
                                console.log('[userStoryPromoteModal.pollDeploymentDetails] SUCCESS - completeDeployment invoked:', this.deploymentRequestId);
                            })
                            .catch(err => console.error('[userStoryPromoteModal.pollDeploymentDetails] Error completing deployment:', err));
                    }
                }
            })
            .catch(prErr => {
                console.warn('[userStoryPromoteModal.pollDeploymentDetails] Warning: Error fetching PR details in poll:', prErr);
            });

        getDeploymentStatus({ requestId: this.deploymentRequestId })
            .then(data => {
                if (!data) {
                    console.warn('[userStoryPromoteModal.pollDeploymentDetails] Warning: No deployment status returned.', {
                        deploymentRequestId: this.deploymentRequestId
                    });
                    return;
                }
                this.executionStatus = data.status || 'Deploying';
                console.log('[userStoryPromoteModal.pollDeploymentDetails] Deployment status received:', {
                    deploymentRequestId: this.deploymentRequestId,
                    status: this.executionStatus,
                    logCount: data.logs ? data.logs.length : 0
                });

                if (data.logs && data.logs.length > 0) {
                    const total = data.logs.length;
                    const isDone = ['Completed', 'Completed Successfully', 'Validated'].includes(this.executionStatus);
                    const isFail = ['Failed', 'Cancelled'].includes(this.executionStatus);

                    this.steps = data.logs.map((log, idx) => {
                        const isLast = (idx === total - 1);
                        return {
                            id: log.Id || idx,
                            name: log.Message__c,
                            isComplete: !isLast || isDone,
                            isCurrent: isLast && !isDone && !isFail,
                            isFailed: isLast && isFail
                        };
                    });
                } else {
                    if (this.isMergedOnGithub) {
                        this.steps = [
                            { id: 'merged', name: '✓ Pull Request Merged on GitHub. Starting UAT Org Deployment...', isComplete: true }
                        ];
                    } else {
                        this.steps = [
                            { id: 'init', name: 'Waiting for Pull Request merge on GitHub...', isCurrent: true }
                        ];
                    }
                }

                if (['Completed', 'Completed Successfully', 'Validated'].includes(data.status)) {
                    this.stopPolling();
                    this.executionStatus = 'Completed';
                    console.log('[userStoryPromoteModal.pollDeploymentDetails] SUCCESS - deployment completed:', {
                        recordId: this.recordId,
                        deploymentRequestId: this.deploymentRequestId
                    });

                    // Trigger Platform LWC Record Cache Refresh
                    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Stage Promotion Succeeded!',
                            message: `Successfully promoted to ${this.targetEnv} Environment.`,
                            variant: 'success'
                        })
                    );

                    // Notify parent workspace LWC to refresh
                    this.dispatchEvent(new CustomEvent('workspacechange', { bubbles: true, composed: true }));

                    // Auto-close modal after 2.5 seconds
                    setTimeout(() => {
                        this.handleCloseConsole();
                    }, 2500);

                } else if (['Failed', 'Cancelled'].includes(data.status)) {
                    this.stopPolling();
                    this.executionStatus = 'Failed';
                    const lastStep = this.steps.length > 0 ? this.steps[this.steps.length - 1] : null;
                    this.failedErrorMessage = lastStep ? lastStep.name : 'Deployment encountered a failure during execution.';
                    console.error('[userStoryPromoteModal.pollDeploymentDetails] Deployment failed or cancelled:', {
                        deploymentRequestId: this.deploymentRequestId,
                        status: data.status,
                        failedErrorMessage: this.failedErrorMessage
                    });
                }
            })
            .catch(err => {
                console.error('[userStoryPromoteModal.pollDeploymentDetails] Error polling in-modal deployment execution:', err);
            });
    }

    stopPolling() {
        if (this._pollingInterval) {
            console.log('[userStoryPromoteModal.stopPolling] START - clearing polling interval for deploymentRequestId:', this.deploymentRequestId);
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
            console.log('[userStoryPromoteModal.stopPolling] SUCCESS - polling stopped for deploymentRequestId:', this.deploymentRequestId);
        }
    }

    get bannerConfig() {
        if (this.isClosedOnGithub) {
            return {
                style: 'background: #fef2f2; border: 1.5px solid #fca5a5; color: #991b1b; padding: 10px 14px; border-radius: 6px; display: flex; align-items: center; justify-content: space-between;',
                title: '🔴 Pull Request closed/declined on GitHub without merge.',
                subtitle: 'Promotion has been cancelled. Please reopen or create a new PR to retry.',
                showLink: true,
                linkLabel: 'View Closed PR ↗'
            };
        }
        if (this.isMergedOnGithub) {
            return {
                style: 'background: #f0fdf4; border: 1.5px solid #86efac; color: #166534; padding: 10px 14px; border-radius: 6px; display: flex; align-items: center; justify-content: space-between;',
                title: '🟢 Now Deployment Started.',
                subtitle: 'Branch merge complete. Live metadata deployment to ' + this.targetEnv + ' Staging in progress...',
                showLink: true,
                linkLabel: 'View Merged PR ↗'
            };
        }
        if (this.hasConflict) {
            const prLabel = this.prNumber ? `PR #${this.prNumber}` : 'PR';
            return {
                style: 'background: #fef2f2; border: 1.5px solid #fca5a5; color: #991b1b; padding: 10px 14px; border-radius: 6px; display: flex; align-items: center; justify-content: space-between;',
                title: `🔴 ⚠️ Merge Conflict detected on ${prLabel} link, please resolve it.`,
                subtitle: 'Resolve conflicts directly on GitHub to resume UAT promotion.',
                showLink: true,
                linkLabel: 'Resolve Conflicts on GitHub ↗'
            };
        }
        if (this.wasConflictDetected && !this.hasConflict) {
            return {
                style: 'background: #fdfbef; border: 1.5px solid #fde047; color: #713f12; padding: 10px 14px; border-radius: 6px; display: flex; align-items: center; justify-content: space-between;',
                title: '🟡 Merge Conflict Resolved, now waiting for final merge.',
                subtitle: 'Merge conflict has been cleared. Waiting for the PR to be merged on GitHub.',
                showLink: true,
                linkLabel: 'Confirm Merge on GitHub ↗'
            };
        }
        // Default waiting state
        return {
            style: 'background: #f0f9ff; border: 1.5px solid #7dd3fc; color: #075985; padding: 10px 14px; border-radius: 6px; display: flex; align-items: center; justify-content: space-between;',
            title: '🔵 Waiting for final merge.',
            subtitle: 'No conflicts detected. Review bypassed. Confirm the merge on GitHub to initiate deployment.',
            showLink: true,
            linkLabel: 'Confirm Merge on GitHub ↗'
        };
    }

    get isExecutingInProgress() {
        return this.isExecuting && !['Completed', 'Failed', 'Cancelled'].includes(this.executionStatus);
    }

    get payloadFileCount() {
        return this.payloadPreviewItems ? this.payloadPreviewItems.length : 0;
    }

    get isExecutionSuccess() {
        return this.executionStatus === 'Completed' || this.executionStatus === 'Completed Successfully';
    }

    get isExecutionFailed() {
        return this.executionStatus === 'Failed' || this.executionStatus === 'Cancelled';
    }

    get executionStatusText() {
        if (this.isExecutionSuccess) return 'Deployment Completed Successfully!';
        if (this.isExecutionFailed) return 'Deployment Execution Failed';
        return 'Deploying Metadata to ' + this.targetEnv + '...';
    }

    handleCloseConsole() {
        console.log('[userStoryPromoteModal.handleCloseConsole] START - closing execution console for recordId:', this.recordId);
        this.stopPolling();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel() {
        console.log('[userStoryPromoteModal.handleCancel] START - cancel requested for recordId:', this.recordId);
        this.stopPolling();
        this.dispatchEvent(new CustomEvent('close'));
    }
}
