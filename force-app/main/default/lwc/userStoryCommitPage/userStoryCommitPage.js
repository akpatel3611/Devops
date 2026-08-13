import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspaceContext from '@salesforce/apex/UserStoryWorkspaceController.getWorkspaceContext';
import getMetadataTypes from '@salesforce/apex/MetadataExplorerController.getMetadataTypes';
import getMetadata from '@salesforce/apex/MetadataExplorerController.getMetadata';
import saveSelectedComponents from '@salesforce/apex/UserStoryWorkspaceController.saveSelectedComponents';
import runCommitChanges from '@salesforce/apex/UserStoryWorkspaceController.runCommitChanges';
import validatePreCommitQualityGate from '@salesforce/apex/UserStoryTestService.validatePreCommitQualityGate';
import getPayloadPreview from '@salesforce/apex/CommitChangesRuntimeService.getPayloadPreview';
import validatePreCommit from '@salesforce/apex/CommitChangesRuntimeService.validatePreCommit';
import getDeploymentStatus from '@salesforce/apex/DeploymentRequestActionController.getDeploymentStatus';

const DEBUG_PREFIX = '[userStoryCommitPage]';

export default class UserStoryCommitPage extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.loadWorkspaceContext();
        } else {
            this._recordId = value;
        }
    }

    @track gitOperation = 'Commit Files';
    @track commitMessage = '';
    
    // Context details
    @track userStoryName = '';
    @track sourceEnvName = '';
    @track projectName = '';
    @track workspaceContext = {};
    @track rawMetadataTypes = [];
    @track isMetadataDropdownOpen = false;
    @track filterTypeSearchKey = '';

    // Tables & Options
    @track typeOptions = [];
    @track componentsList = [];
    @track filteredComponents = [];
    @track selectionsMap = new Map(); // value -> wrapper

    // Filters
    @track filterName = '';
    @track filterType = 'CustomObject';
    @track filterUser = '';
    @track filterDate = '';

    // Status flags
    @track isLoadingMetadata = false;
    @track isProcessing = false;
    @track isAlreadyDeployed = false;        // true when 1st deployment is done (Promotion linked)
    @track existingDeploymentRequestId = null; // for redirect to deploy page

    // Quality Gate Validation state
    @track qualityGateWarnings = [];
    @track missingTestClasses = [];
    @track isQualityGateModalOpen = false;
    @track isQualityGatePassed = false;
    @track isScanning = false;
    @track suggestedAutoSelections = [];
    @track isCommitWarningModalOpen = false;
    @track hasScanBeenRun = false;
    lastScannedSelectionString = '';
    cachedScanResult = null;

    // Payload Inspector Console state
    @track isPayloadConsoleOpen = false;
    @track isLoadingPayload = false;
    @track isPayloadInspected = false;
    @track payloadPreviewItems = [];

    // Pre-Commit Validation state
    @track isValidating = false;
    @track isValidated = false;
    @track isValidationFailed = false;
    @track showValidationConsoleModal = false;
    @track isValidationErrorModalOpen = false;
    @track validationErrorMessage = '';
    @track validationLogs = [];
    _validationRequestId = null;
    _validationPollingInterval = null;

    gitOperations = [
        { label: 'Commit Files', value: 'Commit Files' },
        { label: 'Recommit Changes', value: 'Recommit Changes' },
        { label: 'Destructive Changes', value: 'Destructive Changes' }
    ];

    resetState() {
        this.gitOperation = 'Commit Files';
        this.commitMessage = '';
        this.userStoryName = '';
        this.sourceEnvName = '';
        this.projectName = '';
        this.workspaceContext = {};
        this.rawMetadataTypes = [];
        this.typeOptions = [];
        this.componentsList = [];
        this.filteredComponents = [];
        this.selectionsMap = new Map();
        this.filterName = '';
        this.filterType = 'CustomObject';
        this.filterUser = '';
        this.filterDate = '';
        this.isLoadingMetadata = false;
        this.isProcessing = false;
        this.isAlreadyDeployed = false;
        this.existingDeploymentRequestId = null;
        this.qualityGateWarnings = [];
        this.missingTestClasses = [];
        this.isQualityGateModalOpen = false;
        this.isQualityGatePassed = false;
        this.isScanning = false;
        this.suggestedAutoSelections = [];
        this.isCommitWarningModalOpen = false;
        this.hasScanBeenRun = false;
        this.lastScannedSelectionString = '';
        this.cachedScanResult = null;
    }

    connectedCallback() {
        console.log(`${DEBUG_PREFIX}.connectedCallback START - resetting local state`, { recordId: this.recordId });
        this.resetState();
    }

    loadWorkspaceContext() {
        console.log(`${DEBUG_PREFIX}.loadWorkspaceContext START`, { recordId: this.recordId });
        this.isLoadingMetadata = true;
        getWorkspaceContext({ userStoryId: this.recordId })
            .then(context => {
                this.workspaceContext = context;
                console.log(`${DEBUG_PREFIX}.loadWorkspaceContext SUCCESS`, {
                    recordId: this.recordId,
                    hasContext: !!context,
                    sourceEnvironmentId: context?.sourceEnvironmentId,
                    targetEnvironmentId: context?.targetEnvironmentId,
                    isAlreadyDeployed: context?.isAlreadyDeployed
                });
                if (context) {
                    this.userStoryName = context.userStoryName || 'US-0000000';
                    this.sourceEnvName = context.sourceEnvironmentName || 'DEV';
                    this.projectName = context.projectName || 'Default Project';

                    // Check if already deployed (Promotion exists = 1st deployment done)
                    this.isAlreadyDeployed = !!context.isAlreadyDeployed;
                    this.existingDeploymentRequestId = context.deploymentRequestId || null;
                    
                    // Load types
                    if (context.sourceEnvironmentId) {
                        this.loadMetadataTypes(context.sourceEnvironmentId);
                        // Initial query for metadata (e.g. Layout, ApexClass)
                        this.loadAllMetadataComponents(context.sourceEnvironmentId);
                    }
                }
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.loadWorkspaceContext ERROR`, error);
                this.isLoadingMetadata = false;
            });
    }

    loadMetadataTypes(envId) {
        console.log(`${DEBUG_PREFIX}.loadMetadataTypes START`, { envId });
        getMetadataTypes({ sourceEnvironmentId: envId })
            .then(result => {
                this.rawMetadataTypes = result.map(item => item.value);
                const options = [];
                result.forEach(item => {
                    options.push({ label: item.label, value: item.value });
                });
                this.typeOptions = options;
                console.log(`${DEBUG_PREFIX}.loadMetadataTypes SUCCESS`, { envId, typeCount: this.typeOptions.length });
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.loadMetadataTypes ERROR`, error);
            });
    }

    loadAllMetadataComponents(envId) {
        console.log(`${DEBUG_PREFIX}.loadAllMetadataComponents START`, { envId, componentType: 'CustomObject' });
        this.filterType = 'CustomObject';
        this.isLoadingMetadata = true;
        // Query custom components for default metadata type first (e.g. CustomObject or CustomField)
        getMetadata({
            componentType: 'CustomObject',
            sourceEnvironmentId: envId
        })
            .then(result => {
                this.componentsList = result.map(item => ({
                    label: item.label || item.fullName,
                    value: item.value || item.fullName,
                    type: item.displayType || item.type || 'CustomObject',
                    lastModifiedBy: item.lastModifiedByName || 'System User',
                    lastModifiedDate: item.lastModifiedDate || '',
                    selected: false,
                    retrieveOnly: false
                }));
                this.applyFilters();
                this.isLoadingMetadata = false;
                console.log(`${DEBUG_PREFIX}.loadAllMetadataComponents SUCCESS`, {
                    envId,
                    componentCount: this.componentsList.length,
                    filteredCount: this.filteredComponents.length
                });
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.loadAllMetadataComponents ERROR`, error);
                this.isLoadingMetadata = false;
            });
    }

    get selectedTabLabel() {
        return `Selected Metadata (${this.selectionsMap.size})`;
    }

    get selectionsList() {
        return Array.from(this.selectionsMap.values());
    }

    get categorizedSelections() {
        const selections = Array.from(this.selectionsMap.values());
        if (selections.length === 0) return [];

        const categoryMap = new Map();
        const categoryDefinitions = [
            { id: 'code', name: 'Apex & Code Components', icon: 'standard:apex', types: ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent'] },
            { id: 'ui', name: 'User Interface & Lightning', icon: 'standard:lightning_component', types: ['LightningComponentBundle', 'AuraDefinitionBundle', 'FlexiPage', 'WebLink', 'CustomPageWebLink'] },
            { id: 'schema', name: 'Objects & Schema', icon: 'standard:custom_notification', types: ['CustomObject', 'CustomField', 'RecordType', 'ValidationRule', 'FieldSet', 'Index'] },
            { id: 'automation', name: 'Automations & Workflows', icon: 'standard:flow', types: ['Flow', 'WorkflowRule', 'WorkflowAction', 'AssignmentRule'] },
            { id: 'security', name: 'Security & Settings', icon: 'standard:person_account', types: ['PermissionSet', 'Profile', 'SharingReason', 'CustomMetadata', 'CustomSetting'] }
        ];

        categoryDefinitions.forEach(cat => {
            categoryMap.set(cat.id, {
                id: cat.id,
                name: cat.name,
                icon: cat.icon,
                count: 0,
                items: []
            });
        });

        const otherCategory = {
            id: 'other',
            name: 'Other Metadata Components',
            icon: 'standard:generic_loading',
            count: 0,
            items: []
        };

        selections.forEach(item => {
            let placed = false;
            for (const catDef of categoryDefinitions) {
                if (catDef.types.includes(item.type)) {
                    const cat = categoryMap.get(catDef.id);
                    cat.items.push(item);
                    cat.count++;
                    placed = true;
                    break;
                }
            }
            if (!placed) {
                let catId = 'other';
                if (item.type && item.type.toLowerCase().includes('apex')) catId = 'code';
                else if (item.type && (item.type.toLowerCase().includes('component') || item.type.toLowerCase().includes('aura') || item.type.toLowerCase().includes('lwc'))) catId = 'ui';
                else if (item.type && (item.type.toLowerCase().includes('object') || item.type.toLowerCase().includes('field'))) catId = 'schema';
                else if (item.type && item.type.toLowerCase().includes('flow')) catId = 'automation';

                if (categoryMap.has(catId)) {
                    const cat = categoryMap.get(catId);
                    cat.items.push(item);
                    cat.count++;
                } else {
                    otherCategory.items.push(item);
                    otherCategory.count++;
                }
            }
        });

        const result = [];
        categoryMap.forEach(cat => {
            if (cat.count > 0) {
                result.push(cat);
            }
        });
        if (otherCategory.count > 0) {
            result.push(otherCategory);
        }

        return result;
    }

    get hasSelections() {
        return this.selectionsMap.size > 0;
    }

    get qualityGateMessage() {
        return "Our deep pre-commit quality gate scanner has analyzed your selections. We've detected missing dependencies and test coverage issues that could block your deployment. Click 'Auto-Fix & Add Missing Files' to automatically add these components to your commit selection list.";
    }

    get isQualityGateButtonDisabled() {
        return this.selectionsMap.size === 0 || this.isScanning || this.isProcessing || this.isQualityGatePassed;
    }

    get isPayloadDisabled() {
        return this.selectionsMap.size === 0 || !this.isQualityGatePassed || this.isScanning || this.isProcessing || this.isPayloadInspected;
    }

    get isValidateDisabled() {
        return this.selectionsMap.size === 0 || !this.isPayloadInspected || !this.isQualityGatePassed || this.isValidating || this.isProcessing || this.isValidated;
    }

    get isCommitDisabled() {
        return this.selectionsMap.size === 0 || 
               !this.commitMessage || 
               this.commitMessage.trim() === '' || 
               this.isProcessing || 
               !this.hasScanBeenRun || 
               !this.isQualityGatePassed || 
               !this.isPayloadInspected ||
               !this.isValidated;
    }

    get payloadFileCount() {
        return this.payloadPreviewItems ? this.payloadPreviewItems.length : 0;
    }

    get isCommitHidden() {
        return false;
    }

    handleViewDeployment() {
        if (this.existingDeploymentRequestId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: 'c__userStoryDeployAura' },
                state: { c__recordId: this.existingDeploymentRequestId }
            });
        }
    }

    // Handles header-level select all checkbox
    handleSelectAll(event) {
        const checked = event.target.checked;
        console.log(`${DEBUG_PREFIX}.handleSelectAll`, { checked, filteredCount: this.filteredComponents.length });
        this.filteredComponents = this.filteredComponents.map(item => {
            const updated = { ...item, selected: checked };
            this.updateSelectionMap(updated, checked);
            return updated;
        });
        console.log(`${DEBUG_PREFIX}.handleSelectAll COMPLETE`, { totalSelectionsCount: this.selectionsMap.size });
    }

    // Handles header-level retrieve all checkbox
    handleRetrieveAll(event) {
        const checked = event.target.checked;
        console.log(`${DEBUG_PREFIX}.handleRetrieveAll`, { checked, filteredCount: this.filteredComponents.length });
        this.filteredComponents = this.filteredComponents.map(item => {
            const updated = { ...item, retrieveOnly: checked };
            if (item.selected) {
                this.updateSelectionMap(updated, true);
            }
            return updated;
        });
    }

    handleRowSelect(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        console.log(`${DEBUG_PREFIX}.handleRowSelect`, { id, checked, currentSelectionsCount: this.selectionsMap.size });
        
        this.componentsList = this.componentsList.map(item => {
            if (item.value === id) {
                const updated = { ...item, selected: checked };
                this.updateSelectionMap(updated, checked);
                return updated;
            }
            return item;
        });
        this.applyFilters();
        console.log(`${DEBUG_PREFIX}.handleRowSelect COMPLETE`, { id, newSelectionsCount: this.selectionsMap.size });
    }

    handleRowRetrieveOnly(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        console.log(`${DEBUG_PREFIX}.handleRowRetrieveOnly`, { id, checked });

        this.componentsList = this.componentsList.map(item => {
            if (item.value === id) {
                const updated = { ...item, retrieveOnly: checked };
                if (item.selected) {
                    this.updateSelectionMap(updated, true);
                }
                return updated;
            }
            return item;
        });
        this.applyFilters();
    }

    handleSelectionRetrieveOnlyToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        if (this.selectionsMap.has(id)) {
            const existing = this.selectionsMap.get(id);
            existing.retrieveOnly = checked;
            this.selectionsMap.set(id, { ...existing });
            this.selectionsMap = new Map(this.selectionsMap);
            this.isQualityGatePassed = false;
        }
    }

    updateSelectionMap(item, checked) {
        if (checked) {
            this.selectionsMap.set(item.value, {
                label: item.label,
                value: item.value,
                type: item.type,
                action: item.retrieveOnly ? 'Retrieve Only' : (this.gitOperation === 'Destructive Changes' ? 'Delete' : 'Add'),
                retrieveOnly: item.retrieveOnly
            });
        } else {
            if (this.selectionsMap.has(item.value)) {
                this.selectionsMap.delete(item.value);
            }
        }
        this.selectionsMap = new Map(this.selectionsMap);
        this.isQualityGatePassed = false;
        this.isPayloadInspected = false;
        this.isValidated = false;
        this.checkQualityGate();
    }

    handleRemoveSelection(event) {
        const id = event.target.dataset.id;
        if (this.selectionsMap.has(id)) {
            this.selectionsMap.delete(id);
            this.selectionsMap = new Map(this.selectionsMap);
            this.isQualityGatePassed = false;
            
            // Uncheck in All Metadata list
            this.componentsList = this.componentsList.map(item => {
                if (item.value === id) {
                    return { ...item, selected: false };
                }
                return item;
            });
            this.applyFilters();
            this.checkQualityGate();
        }
    }

    get hasQualityGateWarnings() {
        return this.qualityGateWarnings && this.qualityGateWarnings.length > 0;
    }

    checkQualityGate() {
        const selections = Array.from(this.selectionsMap.values());
        const selectedNames = new Set(selections.map(s => s.value.toLowerCase()));
        
        const missingTests = [];
        const warnings = [];

        selections.forEach(item => {
            const isApexClass = item.type === 'ApexClass';
            const name = item.value;
            const isTestClass = name.endsWith('Test') || name.startsWith('Test') || name.includes('_Test');

            if (isApexClass && !isTestClass) {
                const candidate1 = (name + 'Test').toLowerCase();
                const candidate2 = ('Test' + name).toLowerCase();
                
                if (!selectedNames.has(candidate1) && !selectedNames.has(candidate2)) {
                    missingTests.push(name + 'Test');
                    warnings.push(`Apex Class "${name}" does not have a Test Class selected in this commit.`);
                }
            }
        });

        this.missingTestClasses = missingTests;
        this.qualityGateWarnings = warnings;
    }

    handleRunQualityGateScan() {
        console.log(`${DEBUG_PREFIX}.handleRunQualityGateScan START`, {
            recordId: this.recordId,
            selectedCount: this.selectionsMap.size
        });
        if (this.selectionsMap.size === 0) {
            console.warn(`${DEBUG_PREFIX}.handleRunQualityGateScan WARN - no selected metadata`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Selection',
                    message: 'Please select at least one component to run the Quality Gate Scan.',
                    variant: 'warning'
                })
            );
            return;
        }

        const selections = this.selectionsList;
        const currentSelectionString = selections.map(s => s.value).sort().join(',');

        // 1. Return cached results instantly if selections have not changed
        if (currentSelectionString === this.lastScannedSelectionString && this.cachedScanResult) {
            console.log(`${DEBUG_PREFIX}.handleRunQualityGateScan CACHE_HIT`, {
                selectedCount: selections.length,
                passed: this.cachedScanResult.passed
            });
            this.qualityGateWarnings = this.cachedScanResult.warnings;
            this.suggestedAutoSelections = this.cachedScanResult.suggestedAutoSelections;
            this.missingTestClasses = this.cachedScanResult.missingTestClasses;
            this.isQualityGatePassed = this.cachedScanResult.passed;
            this.hasScanBeenRun = true;

            if (this.isQualityGatePassed) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Quality Gate Cache Hits',
                        message: 'All selected metadata verified successfully (cached)! You can now commit changes.',
                        variant: 'success'
                    })
                );
            } else {
                this.isQualityGateModalOpen = true;
            }
            return;
        }

        this.isScanning = true;
        const componentNames = selections.map(s => s.value);
        const componentTypes = selections.map(s => s.type);

        validatePreCommitQualityGate({
            userStoryId: this.recordId,
            selectedComponentNames: componentNames,
            selectedComponentTypes: componentTypes
        })
            .then(result => {
                this.isScanning = false;
                this.qualityGateWarnings = result.warnings || [];
                this.suggestedAutoSelections = result.suggestedAutoSelections || [];
                this.missingTestClasses = result.missingTestClasses || [];
                this.isQualityGatePassed = result.passed;
                this.hasScanBeenRun = true;

                // Cache scan result
                this.lastScannedSelectionString = currentSelectionString;
                this.cachedScanResult = {
                    passed: result.passed,
                    warnings: result.warnings || [],
                    suggestedAutoSelections: result.suggestedAutoSelections || [],
                    missingTestClasses: result.missingTestClasses || []
                };
                console.log(`${DEBUG_PREFIX}.handleRunQualityGateScan SUCCESS`, {
                    selectedCount: selections.length,
                    warningCount: this.qualityGateWarnings.length,
                    suggestedAutoSelectionCount: this.suggestedAutoSelections.length,
                    passed: this.isQualityGatePassed
                });

                if (result.passed) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Quality Gate Passed',
                            message: 'All selected metadata verified successfully! You can now commit changes.',
                            variant: 'success'
                        })
                    );
                } else {
                    this.isQualityGateModalOpen = true;
                }
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.handleRunQualityGateScan ERROR`, error);
                this.isScanning = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Quality Gate Scan Failed',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleAutoSelectTestClasses() {
        let addedCount = 0;
        
        // Auto-select missing test classes & objects if suggested
        const targetsToSelect = new Set();
        if (this.suggestedAutoSelections && this.suggestedAutoSelections.length > 0) {
            this.suggestedAutoSelections.forEach(s => {
                if (s) targetsToSelect.add(String(s).trim());
            });
        }
        if (this.missingTestClasses && this.missingTestClasses.length > 0) {
            this.missingTestClasses.forEach(m => {
                if (m) targetsToSelect.add(String(m).trim());
            });
        }

        targetsToSelect.forEach(origCompName => {
            const compNameLower = origCompName.toLowerCase();
            let matchedName = origCompName;
            let matchedType = '';

            const foundComp = this.componentsList.find(c => c.value.toLowerCase() === compNameLower);
            if (foundComp) {
                matchedName = foundComp.value;
                matchedType = foundComp.type;
            } else {
                if (compNameLower.endsWith('__c')) {
                    matchedType = 'CustomObject';
                } else if (compNameLower.endsWith('flow')) {
                    matchedType = 'Flow';
                } else if (!compNameLower.includes('_') && compNameLower.length > 3 && /^[a-zA-Z0-9]+$/.test(origCompName)) {
                    matchedType = 'ApexClass';
                }
            }

            if (matchedType && !this.selectionsMap.has(matchedName)) {
                this.selectionsMap.set(matchedName, {
                    label: matchedName,
                    value: matchedName,
                    type: matchedType,
                    action: this.gitOperation === 'Destructive Changes' ? 'Delete' : 'Add',
                    retrieveOnly: false
                });
                addedCount++;
            }
        });

        this.selectionsMap = new Map(this.selectionsMap);

        // Update selected state checkbox in the components list table!
        this.componentsList = this.componentsList.map(item => {
            const isMatch = Array.from(targetsToSelect).some(t => t.toLowerCase() === item.value.toLowerCase());
            if (isMatch) {
                return { ...item, selected: true };
            }
            return item;
        });

        this.isQualityGateModalOpen = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Quality Gate Auto-Select',
                message: `Auto-selected ${addedCount} missing file(s) and dependencies successfully.`,
                variant: 'success'
            })
        );
    }

    handleGitOperationChange(event) {
        this.gitOperation = event.detail.value;
        // Recalculate actions in selections list
        this.selectionsList.forEach(item => {
            this.updateSelectionMap(item, true);
        });
    }

    handleCommitMessageChange(event) {
        this.commitMessage = event.detail.value;
    }

    get filterTypeInputVal() {
        if (this.isMetadataDropdownOpen) {
            return this.filterTypeSearchKey;
        }
        return this.filterType;
    }

    get processedMetadataTypes() {
        const searchKey = this.filterTypeSearchKey.toLowerCase();
        return this.typeOptions.filter(type => {
            const label = type.label || '';
            return !searchKey || label.toLowerCase().includes(searchKey);
        });
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${this.isMetadataDropdownOpen ? 'slds-is-open' : ''}`;
    }

    handleMetadataTypeSearch(event) {
        this.filterTypeSearchKey = event.target.value;
        this.isMetadataDropdownOpen = true;
    }

    handleMetadataTypeClick() {
        this.isMetadataDropdownOpen = !this.isMetadataDropdownOpen;
        if (this.isMetadataDropdownOpen) {
            this.filterTypeSearchKey = '';
        }
    }

    handleMetadataTypeBlur() {
        setTimeout(() => {
            this.isMetadataDropdownOpen = false;
        }, 300);
    }

    handleMetadataTypeSelect(event) {
        const selectedValue = event.currentTarget.dataset.value;
        console.log(`${DEBUG_PREFIX}.handleMetadataTypeSelect START`, {
            recordId: this.recordId,
            selectedValue,
            sourceEnvironmentId: this.workspaceContext.sourceEnvironmentId
        });
        this.filterType = selectedValue;
        this.filterTypeSearchKey = '';
        this.isMetadataDropdownOpen = false;
        
        // Fetch metadata components for this type dynamically!
        this.isLoadingMetadata = true;
        getMetadata({
            componentType: selectedValue,
            sourceEnvironmentId: this.workspaceContext.sourceEnvironmentId
        })
            .then(result => {
                this.componentsList = result.map(item => {
                    const isSelected = this.selectionsMap.has(item.value);
                    const isRetrieve = isSelected ? this.selectionsMap.get(item.value).retrieveOnly : false;
                    return {
                        label: item.label || item.fullName,
                        value: item.value || item.fullName,
                        type: item.displayType || item.type || selectedValue,
                        lastModifiedBy: item.lastModifiedByName || 'System User',
                        lastModifiedDate: item.lastModifiedDate || '',
                        selected: isSelected,
                        retrieveOnly: isRetrieve
                    };
                });
                this.applyFilters();
                this.isLoadingMetadata = false;
                console.log(`${DEBUG_PREFIX}.handleMetadataTypeSelect SUCCESS`, {
                    selectedValue,
                    componentCount: this.componentsList.length,
                    filteredCount: this.filteredComponents.length
                });
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.handleMetadataTypeSelect ERROR`, error);
                this.componentsList = [];
                this.applyFilters();
                this.isLoadingMetadata = false;
            });
    }

    // Handles inline nested filter search inputs
    handleFilterChange(event) {
        const name = event.target.name;
        const val = event.target.value;
        this[name] = val;
        this.applyFilters();
    }

    applyFilters() {
        let list = this.componentsList;
        if (this.filterName) {
            const nameSearch = this.filterName.toLowerCase();
            list = list.filter(item => item.label.toLowerCase().includes(nameSearch));
        }
        if (this.filterUser) {
            const userSearch = this.filterUser.toLowerCase();
            list = list.filter(item => item.lastModifiedBy.toLowerCase().includes(userSearch));
        }
        if (this.filterDate) {
            list = list.filter(item => item.lastModifiedDate === this.filterDate);
        }
        this.filteredComponents = list;
    }

    handleRefreshAll() {
        if (this.workspaceContext.sourceEnvironmentId && this.filterType) {
            this.isLoadingMetadata = true;
            this.loadAllMetadataComponents(this.workspaceContext.sourceEnvironmentId);
        }
    }

    handleRefreshRecent() {
        this.handleRefreshAll();
    }

    handleAutoSelect(event) {
        const mode = event.detail.value;
        // Auto-select all filtered items
        this.filteredComponents = this.filteredComponents.map(item => {
            const updated = { ...item, selected: true };
            this.updateSelectionMap(updated, true);
            return updated;
        });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    saveCurrentSelections() {
        return saveSelectedComponents({
            userStoryId: this.recordId,
            components: this.selectionsList,
            sourceEnvironmentId: this.workspaceContext.sourceEnvironmentId,
            targetEnvironmentId: this.workspaceContext.targetEnvironmentId,
            releaseId: this.workspaceContext.releaseId
        });
    }

    expandMetadataItemsForPreview(selections) {
        const expanded = [];
        selections.forEach(item => {
            const type = item.type;
            const val = item.value;
            const action = item.action || 'Add';

            if (type === 'ApexClass') {
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/classes/${val}.cls`,
                    deploymentAction: action
                });
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/classes/${val}.cls-meta.xml`,
                    deploymentAction: action
                });
            } else if (type === 'ApexTrigger') {
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/triggers/${val}.trigger`,
                    deploymentAction: action
                });
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/triggers/${val}.trigger-meta.xml`,
                    deploymentAction: action
                });
            } else if (type === 'LightningComponentBundle') {
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/lwc/${val}/${val}.js`,
                    deploymentAction: action
                });
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/lwc/${val}/${val}.html`,
                    deploymentAction: action
                });
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: `force-app/main/default/lwc/${val}/${val}.js-meta.xml`,
                    deploymentAction: action
                });
            } else {
                expanded.push({
                    metadataType: type,
                    apiName: val,
                    filePath: item.filePath || `force-app/main/default/${val}`,
                    deploymentAction: action
                });
            }
        });
        return expanded;
    }

    async handleInspectPayload() {
        console.log(`${DEBUG_PREFIX}.handleInspectPayload START`, {
            recordId: this.recordId,
            selectedCount: this.selectionsMap.size
        });
        this.isPayloadConsoleOpen = true;
        this.isLoadingPayload = true;

        try {
            if (this.selectionsMap.size > 0) {
                try {
                    await this.saveCurrentSelections();
                } catch (saveErr) {
                    console.warn(`${DEBUG_PREFIX}.handleInspectPayload WARN - saveCurrentSelections failed during preview`, saveErr);
                }
            }
            const items = await getPayloadPreview({ userStoryId: this.recordId });
            if (items && items.length > 0) {
                this.payloadPreviewItems = items;
            } else if (this.selectionsMap.size > 0) {
                this.payloadPreviewItems = this.expandMetadataItemsForPreview(Array.from(this.selectionsMap.values()));
            } else {
                this.payloadPreviewItems = [];
            }
            console.log(`${DEBUG_PREFIX}.handleInspectPayload SUCCESS`, {
                recordId: this.recordId,
                payloadFileCount: this.payloadPreviewItems.length
            });
        } catch (err) {
            console.warn(`${DEBUG_PREFIX}.handleInspectPayload WARN - Apex payload preview failed, using fallback when available`, err);
            if (this.selectionsMap.size > 0) {
                this.payloadPreviewItems = this.expandMetadataItemsForPreview(Array.from(this.selectionsMap.values()));
            } else {
                this.payloadPreviewItems = [];
            }
        } finally {
            this.isLoadingPayload = false;
        }
    }

    handleApprovePayload() {
        console.log(`${DEBUG_PREFIX}.handleApprovePayload START`, {
            recordId: this.recordId,
            payloadFileCount: this.payloadFileCount
        });
        this.isPayloadInspected = true;
        this.isPayloadConsoleOpen = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Payload Verified',
                message: 'Payload inspected & verified successfully. Target Org Validation button is now unlocked.',
                variant: 'success'
            })
        );
    }

    handleClosePayloadConsole() {
        this.isPayloadConsoleOpen = false;
    }

    async handleValidateChanges() {
        console.log(`${DEBUG_PREFIX}.handleValidateChanges START`, {
            recordId: this.recordId,
            selectedCount: this.selectionsMap.size,
            isPayloadInspected: this.isPayloadInspected
        });
        if (this.selectionsMap.size === 0) {
            console.warn(`${DEBUG_PREFIX}.handleValidateChanges WARN - no selected metadata`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Warning',
                    message: 'Please select at least one component to validate.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.showValidationConsoleModal = true;
        this.isValidating = true;
        this.isValidated = false;
        this.isValidationFailed = false;

        try {
            await this.saveCurrentSelections();
            const res = await validatePreCommit({ userStoryId: this.recordId });
            
            if (res && res.success) {
                this._validationRequestId = res.requestId;
                console.log(`${DEBUG_PREFIX}.handleValidateChanges SUCCESS - validation started`, {
                    recordId: this.recordId,
                    requestId: this._validationRequestId
                });
                this.startValidationPolling();
            } else {
                console.warn(`${DEBUG_PREFIX}.handleValidateChanges WARN - validation did not start`, res);
                this.isValidating = false;
                this.isValidationFailed = true;
                this.validationErrorMessage = res ? res.message : 'Validation failed to initiate.';
            }
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.handleValidateChanges ERROR`, err);
            this.isValidating = false;
            this.isValidationFailed = true;
            this.validationErrorMessage = err.body ? err.body.message : err.message;
        }
    }

    handleCloseValidationConsoleModal() {
        this.showValidationConsoleModal = false;
    }

    startValidationPolling() {
        console.log(`${DEBUG_PREFIX}.startValidationPolling START`, { requestId: this._validationRequestId });
        this.stopValidationPolling();
        this._validationPollingInterval = setInterval(() => {
            this.checkValidationStatus();
        }, 3000);
    }

    stopValidationPolling() {
        if (this._validationPollingInterval) {
            console.log(`${DEBUG_PREFIX}.stopValidationPolling START`, { requestId: this._validationRequestId });
            clearInterval(this._validationPollingInterval);
            this._validationPollingInterval = null;
        }
    }

    async checkValidationStatus() {
        if (!this._validationRequestId) {
            console.warn(`${DEBUG_PREFIX}.checkValidationStatus WARN - requestId missing`);
            return;
        }
        try {
            const statusRes = await getDeploymentStatus({ requestId: this._validationRequestId });
            const status = statusRes ? statusRes.status : '';
            const logs = statusRes ? statusRes.logs : [];
            console.log(`${DEBUG_PREFIX}.checkValidationStatus RESPONSE`, {
                requestId: this._validationRequestId,
                status,
                logCount: logs.length
            });

            if (logs && logs.length > 0) {
                this.validationLogs = logs.map((log, idx) => {
                    const isLast = idx === logs.length - 1;
                    let iconClass = 'check-icon';
                    let iconSymbol = '✓';
                    if (isLast && (status === 'Validating' || status === 'Draft' || status === 'In Progress')) {
                        iconClass = 'spinner-icon';
                        iconSymbol = '⏳';
                    } else if (isLast && (status === 'Validation Failed' || status === 'Failed')) {
                        iconClass = 'error-icon';
                        iconSymbol = '✕';
                    }
                    return {
                        id: log.Id || idx,
                        name: log.Message__c,
                        iconClass: iconClass,
                        iconSymbol: iconSymbol
                    };
                });
            } else {
                if (status === 'Validated') {
                    this.validationLogs = [
                        { id: 'v1', name: 'Check-Only Deployment Connection Established', iconClass: 'check-icon', iconSymbol: '✓' },
                        { id: 'v2', name: 'Metadata & Class Compilation Validation Passed', iconClass: 'check-icon', iconSymbol: '✓' }
                    ];
                } else if (status === 'Validation Failed' || status === 'Failed') {
                    this.validationLogs = [
                        { id: 'v1', name: 'Check-Only Deployment Connection Established', iconClass: 'check-icon', iconSymbol: '✓' },
                        { id: 'v2', name: 'Compilation Errors Encountered in Target Org', iconClass: 'error-icon', iconSymbol: '✕' }
                    ];
                } else {
                    this.validationLogs = [
                        { id: 'v1', name: 'Initializing check-only deployment connection...', iconClass: 'spinner-icon', iconSymbol: '⏳' }
                    ];
                }
            }

            if (status === 'Validated') {
                this.stopValidationPolling();
                this.isValidating = false;
                this.isValidated = true;
                this.isValidationFailed = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Validation Successful',
                        message: 'Target Org dry-run validation passed! You can now commit your changes.',
                        variant: 'success'
                    })
                );
                console.log(`${DEBUG_PREFIX}.checkValidationStatus SUCCESS - validation passed`, {
                    requestId: this._validationRequestId
                });
            } else if (status === 'Validation Failed' || status === 'Failed') {
                this.stopValidationPolling();
                this.isValidating = false;
                this.isValidated = false;
                this.isValidationFailed = true;
                this.validationErrorMessage = statusRes.logOutput || statusRes.errorMessage || 'Target Org validation encountered compilation errors.';
                console.error(`${DEBUG_PREFIX}.checkValidationStatus ERROR - validation failed`, {
                    requestId: this._validationRequestId,
                    validationErrorMessage: this.validationErrorMessage
                });
            }
        } catch (err) {
            console.error(`${DEBUG_PREFIX}.checkValidationStatus ERROR`, err);
        }
    }

    handleCloseValidationErrorModal() {
        this.isValidationErrorModalOpen = false;
    }

    handleCommit() {
        if (this.isCommitDisabled) return;

        if (this.isQualityGatePassed) {
            this.executeCommitProcess();
        } else {
            this.isCommitWarningModalOpen = true;
        }
    }

    handleCloseCommitWarningModal() {
        this.isCommitWarningModalOpen = false;
    }

    handleAutoFixFromCommitWarning() {
        this.isCommitWarningModalOpen = false;
        this.handleAutoSelectTestClasses();
        // Run scan again to verify
        this.handleRunQualityGateScan();
    }

    handleConfirmCommitAnyway() {
        this.isCommitWarningModalOpen = false;
        this.executeCommitProcess();
    }

    handleCloseQualityGateModal() {
        this.isQualityGateModalOpen = false;
    }

    handleAutoFixAndCommit() {
        this.handleAutoSelectTestClasses();
        this.isQualityGateModalOpen = false;
        // Automatically run scan again to verify fix
        this.handleRunQualityGateScan();
    }

    handleProceedAnyway() {
        this.isQualityGateModalOpen = false;
        this.isQualityGatePassed = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Quality Gate Override',
                message: 'Quality Gate scan bypassed. You can now click Commit Changes.',
                variant: 'info'
            })
        );
    }

    executeCommitProcess() {
        console.log(`${DEBUG_PREFIX}.executeCommitProcess START`, {
            recordId: this.recordId,
            selectedCount: this.selectionsMap.size,
            hasCommitMessage: !!(this.commitMessage && this.commitMessage.trim())
        });
        this.isProcessing = true;
        const selectedComponents = this.selectionsList;

        saveSelectedComponents({
            userStoryId: this.recordId,
            components: selectedComponents,
            sourceEnvironmentId: this.workspaceContext.sourceEnvironmentId,
            targetEnvironmentId: this.workspaceContext.targetEnvironmentId,
            releaseId: this.workspaceContext.releaseId
        })
            .then(() => {
                return runCommitChanges({
                    userStoryId: this.recordId,
                    commitMessage: this.commitMessage
                });
            })
            .then(result => {
                this.isProcessing = false;
                console.log(`${DEBUG_PREFIX}.executeCommitProcess RESPONSE`, result);
                if (result.success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Commit changes enqueued successfully.',
                            variant: 'success'
                        })
                    );
                    
                    // Open GitHub PR URL in new browser tab
                    if (result.pullRequestUrl && result.pullRequestUrl.startsWith('http')) {
                        try {
                            window.open(result.pullRequestUrl, '_blank');
                        } catch (e) {
                            console.warn(`${DEBUG_PREFIX}.executeCommitProcess WARN - browser popup blocked opening PR tab`, e);
                        }
                    }

                    if (result.deploymentRequestId) {
                        this[NavigationMixin.Navigate]({
                            type: 'standard__component',
                            attributes: {
                                componentName: 'c__userStoryDeployAura'
                            },
                            state: {
                                c__recordId: result.deploymentRequestId
                            }
                        });
                    } else {
                        this.dispatchEvent(new CustomEvent('close'));
                    }
                } else {
                    console.warn(`${DEBUG_PREFIX}.executeCommitProcess WARN - commit failed response`, result);
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Commit Failed',
                            message: result.message,
                            variant: 'error'
                        })
                    );
                }
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX}.executeCommitProcess ERROR`, error);
                this.isProcessing = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Operation Failed',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }
}
