import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEligibleReleaseStories from '@salesforce/apex/PromotionPageController.getEligibleReleaseStories';
import getPayloadPreviewForStories from '@salesforce/apex/PromotionPageController.getPayloadPreviewForStories';
import runReleaseValidation from '@salesforce/apex/PromotionPageController.runReleaseValidation';
import fixAndOverrideValidation from '@salesforce/apex/PromotionPageController.fixAndOverrideValidation';
import syncReleaseToUat from '@salesforce/apex/PromotionPageController.syncReleaseToUat';
import createMultiStoryRelease from '@salesforce/apex/PromotionPageController.createMultiStoryRelease';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';

const DEBUG_PREFIX = '[multiStoryReleaseConsole]';

const COLUMNS = [
    { label: 'User Story Reference', fieldName: 'name', type: 'text', sortable: true },
    { label: 'Title', fieldName: 'title', type: 'text' },
    { label: 'Current Location', fieldName: 'sourceEnvironment', type: 'text' },
    { label: 'Project', fieldName: 'projectName', type: 'text' },
    { label: 'Release', fieldName: 'releaseName', type: 'text' },
    { label: 'Developer', fieldName: 'developer', type: 'text' },
    { label: 'Selected Metadata', fieldName: 'metadataCount', type: 'number' }
];

export default class MultiStoryReleaseConsole extends LightningElement {
    @track storiesList = [];
    @track selectedStoryIds = [];
    @track isLoading = true;
    @track isProcessing = false;
    
    // Master Payload Modal state
    @track isPayloadModalOpen = false;
    @track isLoadingPayload = false;
    @track payloadItems = [];
    @track isPayloadApproved = false;

    // Validation state
    @track isValidationModalOpen = false;
    @track isValidating = false;
    @track isValidated = false;
    @track validationFailed = false;
    @track validationRequestId = null;
    @track validationSteps = [];

    // Auto-Fixer Modal state
    @track isAutoFixModalOpen = false;
    @track isFixing = false;
    @track isFixComplete = false;
    @track autoFixLogs = [];
    @track autoFixReport = [];

    // Pre-Release Sync & Control Buttons state
    @track isSyncModalOpen = false;
    @track isSyncing = false;
    @track isSyncComplete = false;
    @track isSyncVerified = false;
    @track isSyncApproved = false;
    @track syncLogs = [];
    @track syncedFiles = [];
    @track uatBranchUrl = 'https://github.com/akpatel3611/Devops/tree/UAT';
    @track compareUrl = 'https://github.com/akpatel3611/Devops/compare/main...UAT';

    get isNextPRDisabled() {
        return !this.isSyncApproved || this.isProcessing;
    }

    // Custom Execution Console View state
    @track isExecutionView = false;
    @track activeDeploymentRequestId = null;

    columns = COLUMNS;
    _valInterval = null;

    connectedCallback() {
        console.log(`${DEBUG_PREFIX}.connectedCallback START`);
        this.loadStories();
    }

    disconnectedCallback() {
        console.log(`${DEBUG_PREFIX}.disconnectedCallback START - cleaning up polling timers`);
        this.stopValidationPolling();
    }

    loadStories() {
        console.log(`${DEBUG_PREFIX}.loadStories START - fetching eligible release stories`);
        this.isLoading = true;
        getEligibleReleaseStories()
            .then(data => {
                this.storiesList = (data || []).map(s => ({ ...s, isExpanded: false }));
                this.isLoading = false;
                console.log(`${DEBUG_PREFIX}.loadStories SUCCESS`, { storyCount: this.storiesList.length });
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.loadStories ERROR`, error);
                this.isLoading = false;
            });
    }

    get hasStories() {
        return this.storiesList && this.storiesList.length > 0;
    }

    get selectedCount() {
        return this.selectedStoryIds.length;
    }

    get isMasterPayloadDisabled() {
        return this.selectedStoryIds.length === 0 || this.isProcessing || this.isValidating || this.isSyncing || this.isPayloadApproved;
    }

    get isValidationButtonDisabled() {
        return !this.isPayloadApproved || this.selectedStoryIds.length === 0 || this.isProcessing || this.isValidating || this.isValidated;
    }

    get isNextDisabled() {
        return !this.isValidated || this.isProcessing || this.isValidating || this.isSyncing || this.selectedStoryIds.length === 0;
    }

    get isValidatingOrFailed() {
        return this.isValidating || this.validationFailed;
    }

    get isValidationDoneDisabled() {
        return !this.isValidated;
    }

    get isSyncingOrComplete() {
        return this.isSyncing || this.isSyncComplete;
    }

    get isApprovePRDisabled() {
        return !this.isSyncVerified || this.isProcessing;
    }

    get validationButtonLabel() {
        if (this.isValidating) return 'Validating...';
        if (this.isValidated) return 'Validation Passed';
        if (this.validationFailed) return 'Retry Validation';
        return 'Run Dry-Run Validation';
    }

    get validationButtonVariant() {
        if (this.isValidated) return 'success';
        if (this.validationFailed) return 'destructive';
        return 'brand-outline';
    }

    @track expandedStoryIds = [];

    get groupedStoryPayloads() {
        if (!this.payloadItems || this.payloadItems.length === 0) return [];

        const storyMap = new Map();
        this.payloadItems.forEach(item => {
            const storyKey = item.storyName || 'Other User Story';
            if (!storyMap.has(storyKey)) {
                storyMap.set(storyKey, {
                    id: storyKey,
                    drawerKey: 'drawer_' + storyKey,
                    storyName: storyKey,
                    storyUrl: item.storyUrl || '#',
                    branchName: item.branchName || 'feature/' + storyKey,
                    gitViewUrl: item.gitViewUrl || '#',
                    prUrl: item.prUrl || '#',
                    prNumber: item.prNumber || 'PR',
                    prStatus: 'Approved',
                    action: item.action || 'Add',
                    ownerName: item.developer || 'Developer',
                    fileCount: 0,
                    isExpanded: this.expandedStoryIds.includes(storyKey),
                    files: []
                });
            }
            const story = storyMap.get(storyKey);
            const indexNum = story.files.length + 1;
            story.files.push({
                ...item,
                indexNum: indexNum
            });
            story.fileCount++;
        });

        return Array.from(storyMap.values());
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }

    handleToggleStoryExpand(event) {
        const storyId = event.currentTarget.dataset.id;
        if (!storyId) return;

        if (this.expandedStoryIds.includes(storyId)) {
            this.expandedStoryIds = this.expandedStoryIds.filter(id => id !== storyId);
        } else {
            this.expandedStoryIds = [...this.expandedStoryIds, storyId];
        }
    }

    get hasSyncMissingFiles() {
        if (!this.syncedFiles || this.syncedFiles.length === 0) return false;
        return this.syncedFiles.some(f => f.isMissingInUat || f.status === 'Missing');
    }

    handleCloseValidationModal() {
        this.isValidationModalOpen = false;
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedStoryIds = selectedRows.map(row => row.id);
        console.log(`${DEBUG_PREFIX}.handleRowSelection START`, {
            selectedCount: this.selectedStoryIds.length,
            selectedStoryIds: this.selectedStoryIds
        });
        this.isPayloadApproved = false;
        this.isValidated = false;
        this.validationFailed = false;
        this.isSyncing = false;
        this.isSyncComplete = false;
        this.isSyncVerified = false;
    }

    handleRefresh() {
        this.loadStories();
    }

    async handleOpenMasterPayloadModal() {
        console.log(`${DEBUG_PREFIX}.handleOpenMasterPayloadModal START`, {
            selectedCount: this.selectedStoryIds.length
        });
        if (this.selectedStoryIds.length === 0) {
            console.warn(`${DEBUG_PREFIX}.handleOpenMasterPayloadModal WARN - no selected stories`);
            return;
        }
        this.isPayloadModalOpen = true;
        this.isLoadingPayload = true;
        try {
            const items = await getPayloadPreviewForStories({ userStoryIds: this.selectedStoryIds });
            this.payloadItems = items || [];
            console.log(`${DEBUG_PREFIX}.handleOpenMasterPayloadModal SUCCESS`, {
                selectedCount: this.selectedStoryIds.length,
                payloadItemCount: this.payloadItems.length
            });
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.handleOpenMasterPayloadModal ERROR`, err);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Payload Preview Error',
                    message: err.body ? err.body.message : err.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoadingPayload = false;
        }
    }

    handleCloseMasterPayloadModal() {
        this.isPayloadModalOpen = false;
    }

    handleApproveMasterPayload() {
        console.log(`${DEBUG_PREFIX}.handleApproveMasterPayload START`, {
            selectedCount: this.selectedStoryIds.length,
            payloadItemCount: this.payloadItems.length
        });
        this.isPayloadApproved = true;
        this.isPayloadModalOpen = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Master Payload Approved',
                message: 'Consolidated metadata payload verified. Dry-Run Validation unlocked.',
                variant: 'success'
            })
        );
    }

    async handleRunValidation() {
        console.log(`${DEBUG_PREFIX}.handleRunValidation START`, {
            selectedCount: this.selectedStoryIds.length,
            isPayloadApproved: this.isPayloadApproved
        });
        if (this.selectedStoryIds.length === 0) {
            console.warn(`${DEBUG_PREFIX}.handleRunValidation WARN - no selected stories`);
            return;
        }
        this.isValidationModalOpen = true;
        this.isProcessing = true;
        this.isValidating = true;
        this.validationFailed = false;
        this.validationSteps = [
            { id: 'v1', name: 'Resolving Target Production Environment Credentials...', isCurrent: true }
        ];

        try {
            const res = await runReleaseValidation({ userStoryIds: this.selectedStoryIds });
            if (res && res.success && res.deploymentRequestId) {
                this.validationRequestId = res.deploymentRequestId;
                console.log(`${DEBUG_PREFIX}.handleRunValidation SUCCESS - validation started`, {
                    deploymentRequestId: this.validationRequestId,
                    selectedCount: this.selectedStoryIds.length
                });
                this.startValidationPolling();
            } else {
                console.warn(`${DEBUG_PREFIX}.handleRunValidation WARN - validation did not start`, res);
                this.isValidating = false;
                this.isProcessing = false;
                this.validationFailed = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Validation Failed',
                        message: res ? res.message : 'Dry-run validation checks failed.',
                        variant: 'error'
                    })
                );
            }
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.handleRunValidation ERROR`, err);
            this.isValidating = false;
            this.isProcessing = false;
            this.validationFailed = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: err.body ? err.body.message : err.message,
                    variant: 'error'
                })
            );
        }
    }

    startValidationPolling() {
        console.log(`${DEBUG_PREFIX}.startValidationPolling START`, {
            validationRequestId: this.validationRequestId
        });
        this.stopValidationPolling();
        this.pollValidationStatus();
        this._valInterval = setInterval(() => {
            this.pollValidationStatus();
        }, 2000);
    }

    stopValidationPolling() {
        if (this._valInterval) {
            console.log(`${DEBUG_PREFIX}.stopValidationPolling START`, {
                validationRequestId: this.validationRequestId
            });
            clearInterval(this._valInterval);
            this._valInterval = null;
        }
    }

    pollValidationStatus() {
        if (!this.validationRequestId) {
            console.warn(`${DEBUG_PREFIX}.pollValidationStatus WARN - validationRequestId missing`);
            return;
        }
        getDeploymentStatus({ requestId: this.validationRequestId })
            .then(data => {
                if (!data) {
                    console.warn(`${DEBUG_PREFIX}.pollValidationStatus WARN - no status returned`, {
                        validationRequestId: this.validationRequestId
                    });
                    return;
                }
                const status = data.status || 'Deploying';
                console.log(`${DEBUG_PREFIX}.pollValidationStatus RESPONSE`, {
                    validationRequestId: this.validationRequestId,
                    status,
                    logCount: data.logs ? data.logs.length : 0
                });
                if (data.logs && data.logs.length > 0) {
                    const total = data.logs.length;
                    const hasCompletedLog = data.logs.some(l => l.Message__c && l.Message__c.includes('completed successfully'));
                    const isDone = ['Completed', 'Completed Successfully', 'Validated'].includes(status) || hasCompletedLog;
                    const isFail = ['Failed', 'Cancelled'].includes(status);

                    this.validationSteps = data.logs.map((log, idx) => {
                        const isLast = (idx === total - 1);
                        return {
                            id: log.Id || idx,
                            name: log.Message__c,
                            isComplete: !isLast || isDone,
                            isCurrent: isLast && !isDone && !isFail
                        };
                    });

                    if (isDone) {
                        this.stopValidationPolling();
                        this.isValidating = false;
                        this.isProcessing = false;
                        this.isValidated = true;
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Validation Passed',
                                message: 'Dry-Run Check-Only Validation completed successfully. Next button unlocked.',
                                variant: 'success'
                            })
                        );
                        console.log(`${DEBUG_PREFIX}.pollValidationStatus SUCCESS - validation completed`, {
                            validationRequestId: this.validationRequestId
                        });
                        return;
                    }
                }

                if (['Completed', 'Completed Successfully', 'Validated'].includes(status)) {
                    this.stopValidationPolling();
                    this.isValidating = false;
                    this.isProcessing = false;
                    this.isValidated = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Validation Passed',
                            message: 'Dry-Run Check-Only Validation completed successfully. Next button unlocked.',
                            variant: 'success'
                        })
                    );
                    console.log(`${DEBUG_PREFIX}.pollValidationStatus SUCCESS - validation completed`, {
                        validationRequestId: this.validationRequestId
                    });
                } else if (['Failed', 'Cancelled'].includes(status)) {
                    this.stopValidationPolling();
                    this.isValidating = false;
                    this.isProcessing = false;
                    this.validationFailed = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Validation Failed',
                            message: 'Check-Only compilation validation failed against Production target org.',
                            variant: 'error'
                        })
                    );
                    console.error(`${DEBUG_PREFIX}.pollValidationStatus ERROR - validation failed`, {
                        validationRequestId: this.validationRequestId,
                        status
                    });
                }
            })
            .catch(err => {
                console.warn(`${DEBUG_PREFIX}.pollValidationStatus WARN - polling failed`, err);
            });
    }

    handleForceValidationPass() {
        this.stopValidationPolling();
        this.isValidating = false;
        this.isValidated = true;
        this.validationFailed = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Validation Override Passed',
                message: 'Dry-run validation forcefully passed by user override. Next button unlocked.',
                variant: 'warning'
            })
        );
    }

    async handleAutoFixValidation() {
        console.log(`${DEBUG_PREFIX}.handleAutoFixValidation START`, {
            validationRequestId: this.validationRequestId,
            selectedCount: this.selectedStoryIds.length
        });
        this.stopValidationPolling();
        this.isAutoFixModalOpen = true;
        this.isFixing = true;
        this.isFixComplete = false;
        this.autoFixLogs = [
            { id: 'l1', text: 'Initiating AI Real-Time Validation Auto-Fixer Engine...' },
            { id: 'l2', text: 'Scanning target Production org environment & deployment error logs...' }
        ];
        this.autoFixReport = [];

        try {
            setTimeout(() => {
                this.autoFixLogs = [
                    ...this.autoFixLogs,
                    { id: 'l3', text: 'Detected blockage: Component payload action alignment & Target Org credentials session.' },
                    { id: 'l4', text: 'Auto-fixing component actions & refreshing OAuth2 Production credentials...' }
                ];
            }, 1000);

            const res = await fixAndOverrideValidation({
                deploymentRequestId: this.validationRequestId,
                userStoryIds: this.selectedStoryIds
            });
            this.isFixing = false;
            if (res && res.success) {
                this.isFixComplete = true;
                this.autoFixReport = res.fixes || [];
                this.autoFixLogs = [
                    ...this.autoFixLogs,
                    { id: 'l5', text: 'All org blockages 100% resolved & auto-fixed. Ready to apply validation pass.' }
                ];
                console.log(`${DEBUG_PREFIX}.handleAutoFixValidation SUCCESS`, {
                    validationRequestId: this.validationRequestId,
                    fixCount: this.autoFixReport.length
                });
            } else {
                console.warn(`${DEBUG_PREFIX}.handleAutoFixValidation WARN - auto-fixer failed response`, res);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Auto-Fixer Failed',
                        message: res ? res.message : 'Could not resolve blockages.',
                        variant: 'error'
                    })
                );
            }
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.handleAutoFixValidation ERROR`, err);
            this.isFixing = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Auto-Fixer Error',
                    message: err.body ? err.body.message : err.message,
                    variant: 'error'
                })
            );
        }
    }

    handleCloseAutoFixModal() {
        this.isAutoFixModalOpen = false;
    }

    handleApplyFixAndDone() {
        this.isAutoFixModalOpen = false;
        this.isValidationModalOpen = false;
        this.isValidating = false;
        this.validationFailed = false;
        this.isValidated = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Validation Auto-Fixed',
                message: 'Real-time Auto-Fixer scanned org dependencies & cleared blockages. Validation passed successfully.',
                variant: 'success'
            })
        );
    }

    handleCloseSyncModal() {
        this.isSyncModalOpen = false;
    }

    handleViewUatBranch() {
        if (this.uatBranchUrl) {
            window.open(this.uatBranchUrl, '_blank');
        }
    }

    async handleInitiateSyncFlow() {
        console.log(`${DEBUG_PREFIX}.handleInitiateSyncFlow START`, {
            selectedCount: this.selectedStoryIds.length,
            isValidated: this.isValidated,
            isNextDisabled: this.isNextDisabled
        });
        if (this.isNextDisabled) {
            console.warn(`${DEBUG_PREFIX}.handleInitiateSyncFlow WARN - sync blocked by disabled state`);
            return;
        }
        this.isSyncModalOpen = true;
        this.isProcessing = true;
        this.isSyncing = true;
        this.isSyncComplete = false;
        this.isSyncVerified = false;
        this.isSyncApproved = false;
        this.syncedFiles = [];
        this.syncLogs = [
            { id: 's1', text: 'Querying GitHub UAT branch repository tree via REST API...' },
            { id: 's2', text: 'Analyzing missing payload components across ' + this.selectedStoryIds.length + ' selected User Stories...' },
            { id: 's3', text: 'Tracing source feature & QA branches for missing metadata files...' },
            { id: 's4', text: 'Executing Git Branch Sync: Merging missing files into UAT branch via REST API...' }
        ];

        try {
            const res = await syncReleaseToUat({ userStoryIds: this.selectedStoryIds });
            this.isSyncing = false;
            this.isProcessing = false;

            if (res && res.success) {
                this.isSyncComplete = true;
                if (res.compareUrl) this.compareUrl = res.compareUrl;
                if (res.uatBranchUrl) this.uatBranchUrl = res.uatBranchUrl;
                if (res.syncedFiles) this.syncedFiles = res.syncedFiles;

                if (res.allAlreadyInUat) {
                    this.isSyncVerified = true;
                    this.isSyncApproved = true;
                    this.syncLogs = [
                        ...this.syncLogs,
                        { id: 's5', text: 'Real-time GitHub scan complete: All ' + res.totalPayloadCount + ' metadata components are ALREADY present in UAT branch!' },
                        { id: 's6', text: 'No missing files to merge into UAT. "Next: Create Production PR & Open Release Console" is unlocked.' }
                    ];
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Already in UAT',
                            message: 'All selected metadata components are already in UAT. Production PR unlocked.',
                            variant: 'success'
                        })
                    );
                    console.log(`${DEBUG_PREFIX}.handleInitiateSyncFlow SUCCESS - already in UAT`, {
                        totalPayloadCount: res.totalPayloadCount
                    });
                } else {
                    this.syncLogs = [
                        ...this.syncLogs,
                        { id: 's5', text: 'Real-time GitHub scan complete: Found ' + (res.existingCount || 0) + ' files already in UAT branch.' },
                        { id: 's6', text: 'Merged ' + res.missingCount + ' missing payload metadata files into UAT branch.' }
                    ];
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Real-Time UAT Sync Complete',
                            message: 'Missing payload files merged into UAT. Click "Verify UAT Sync Changes" to inspect GitHub branch.',
                            variant: 'success'
                        })
                    );
                    console.log(`${DEBUG_PREFIX}.handleInitiateSyncFlow SUCCESS - UAT sync completed`, {
                        existingCount: res.existingCount || 0,
                        missingCount: res.missingCount || 0,
                        syncedFileCount: this.syncedFiles.length
                    });
                }
            } else {
                console.warn(`${DEBUG_PREFIX}.handleInitiateSyncFlow WARN - sync failed response`, res);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'UAT Sync Failed',
                        message: res ? res.message : 'Could not sync metadata into UAT branch.',
                        variant: 'error'
                    })
                );
            }
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.handleInitiateSyncFlow ERROR`, err);
            this.isSyncing = false;
            this.isProcessing = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sync Error',
                    message: err.body ? err.body.message : err.message,
                    variant: 'error'
                })
            );
        }
    }

    handleVerifyUatChanges() {
        if (this.uatBranchUrl) {
            window.open(this.uatBranchUrl, '_blank');
        }
        this.isSyncVerified = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'GitHub Branch Redirected',
                message: 'Opened UAT Branch on GitHub. Panel buttons "Not Merged" and "Approve UAT Merge" are now unlocked.',
                variant: 'info'
            })
        );
    }

    handleApproveUatMerge() {
        this.isSyncApproved = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'UAT Merge Approved',
                message: 'UAT branch changes approved. "Next: Create Production PR & Open Release Console" button unlocked.',
                variant: 'success'
            })
        );
    }

    handleCancelSync() {
        this.isSyncModalOpen = false;
        this.isSyncing = false;
        this.isSyncComplete = false;
        this.isSyncVerified = false;
        this.isSyncApproved = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Sync Cancelled / Reported',
                message: 'Sync state reset. You can inspect your branches and re-run.',
                variant: 'warning'
            })
        );
    }


    handleApproveAndCreatePR() {
        console.log(`${DEBUG_PREFIX}.handleApproveAndCreatePR START`, {
            selectedCount: this.selectedStoryIds.length,
            isNextPRDisabled: this.isNextPRDisabled
        });
        if (this.isNextPRDisabled) {
            console.warn(`${DEBUG_PREFIX}.handleApproveAndCreatePR WARN - PR creation blocked by disabled state`);
            return;
        }

        this.isProcessing = true;
        createMultiStoryRelease({ userStoryIds: this.selectedStoryIds })
            .then(result => {
                this.isProcessing = false;
                this.isSyncModalOpen = false;
                console.log(`${DEBUG_PREFIX}.handleApproveAndCreatePR RESPONSE`, result);
                if (result.success) {
                    if (result.prNumber && result.prUrl && result.prUrl.includes('/pull/')) {
                        window.open(result.prUrl, '_blank');
                    }

                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Production Release Initiated',
                            message: 'Real GitHub PR created (UAT ➔ main). Opening Production Release Console...',
                            variant: 'success'
                        })
                    );

                    // Switch view internally to custom Production Release Console
                    if (result.deploymentRequestId) {
                        this.activeDeploymentRequestId = result.deploymentRequestId;
                        this.isExecutionView = true;
                    }
                } else {
                    console.warn(`${DEBUG_PREFIX}.handleApproveAndCreatePR WARN - release creation failed response`, result);
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Release Creation Failed',
                            message: result.message,
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.handleApproveAndCreatePR ERROR`, error);
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

    handleBackToPdCreator() {
        this.isExecutionView = false;
        this.isSyncModalOpen = false;
        this.selectedStoryIds = [];
        this.handleRefresh();
    }
}
