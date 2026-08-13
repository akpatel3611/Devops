import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getWorkspaceContext from '@salesforce/apex/UserStoryWorkspaceController.getWorkspaceContext';
import getMetadataTypes from '@salesforce/apex/MetadataExplorerController.getMetadataTypes';
import getMetadata from '@salesforce/apex/MetadataExplorerController.getMetadata';
import saveSelectedComponents from '@salesforce/apex/UserStoryWorkspaceController.saveSelectedComponents';
import runCommitChanges from '@salesforce/apex/UserStoryWorkspaceController.runCommitChanges';

const COLUMNS = [
    { label: 'Component Name', fieldName: 'label', type: 'text', sortable: true },
    { label: 'Type', fieldName: 'type', type: 'text', sortable: true },
    { label: 'Category', fieldName: 'objectCategory', type: 'text', sortable: true },
    { label: 'Last Modified By', fieldName: 'lastModifiedByName', type: 'text', sortable: true },
    { label: 'Last Modified Date', fieldName: 'lastModifiedDate', type: 'text', sortable: true }
];

export default class CommitChangesWizard extends LightningElement {
    @api recordId;
    @api workspaceContext;

    @track gitOperation = 'Commit Files';
    @track commitMessage = '';
    @track selectedType = '';
    @track searchKeyword = '';
    
    @track typeOptions = [];
    @track componentsList = [];
    @track filteredComponents = [];
    @track selectionsMap = new Map(); // value -> wrapper
    
    @track isLoadingTypes = true;
    @track isLoadingMetadata = false;
    @track isProcessing = false;
    
    columns = COLUMNS;

    gitOperations = [
        { label: 'Commit Files', value: 'Commit Files' },
        { label: 'Recommit Changes', value: 'Recommit Changes' },
        { label: 'Destructive Changes', value: 'Destructive Changes' }
    ];

    connectedCallback() {
        this.resetFormState();
        if (this.workspaceContext && this.workspaceContext.sourceEnvironmentId) {
            this.loadTypes(this.workspaceContext.sourceEnvironmentId);
        } else if (this.recordId) {
            this.isLoadingTypes = true;
            getWorkspaceContext({ userStoryId: this.recordId })
                .then(context => {
                    this.workspaceContext = context;
                    if (context && context.sourceEnvironmentId) {
                        this.loadTypes(context.sourceEnvironmentId);
                    } else {
                        this.isLoadingTypes = false;
                    }
                })
                .catch(error => {
                    console.error('Error fetching context in wizard:', error);
                    this.isLoadingTypes = false;
                });
        }
    }

    resetFormState() {
        this.commitMessage = '';
        this.selectedType = '';
        this.searchKeyword = '';
        this.componentsList = [];
        this.filteredComponents = [];
        this.selectionsMap = new Map();
    }

    get sourceEnvName() {
        return this.workspaceContext ? this.workspaceContext.sourceEnvironmentName : '';
    }

    get featureBranch() {
        return this.workspaceContext ? this.workspaceContext.featureBranch : '';
    }

    get selectedTabLabel() {
        return `Selected Components (${this.selectionsMap.size})`;
    }

    get selectionsList() {
        return Array.from(this.selectionsMap.values());
    }

    get hasSelections() {
        return this.selectionsMap.size > 0;
    }

    get hasComponents() {
        return this.filteredComponents && this.filteredComponents.length > 0;
    }

    get isCommitDisabled() {
        return !this.commitMessage || this.commitMessage.trim() === '' || this.selectionsMap.size === 0 || this.isProcessing;
    }

    get selectedRows() {
        return Array.from(this.selectionsMap.keys());
    }

    loadTypes(envId) {
        this.isLoadingTypes = true;
        getMetadataTypes({ sourceEnvironmentId: envId })
            .then(result => {
                this.typeOptions = result;
                this.isLoadingTypes = false;
            })
            .catch(error => {
                console.error('Error loading metadata types:', error);
                this.isLoadingTypes = false;
            });
    }

    handleGitOperationChange(event) {
        this.gitOperation = event.detail.value;
    }

    handleCommitMessageChange(event) {
        this.commitMessage = event.detail.value;
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
        this.loadComponents();
    }

    loadComponents() {
        if (!this.selectedType || !this.workspaceContext.sourceEnvironmentId) {
            return;
        }
        this.isLoadingMetadata = true;
        getMetadata({
            componentType: this.selectedType,
            sourceEnvironmentId: this.workspaceContext.sourceEnvironmentId
        })
            .then(result => {
                this.componentsList = result.map(item => ({
                    ...item,
                    label: item.label || item.fullName,
                    value: item.value || item.fullName,
                    type: item.type || this.selectedType,
                    objectCategory: item.objectCategory || (item.isCustom ? 'Custom Object' : 'Standard Object'),
                    lastModifiedByName: item.lastModifiedByName || 'System User',
                    lastModifiedDate: item.lastModifiedDate || ''
                }));
                this.applyFilter();
                this.isLoadingMetadata = false;
            })
            .catch(error => {
                console.error('Error loading components:', error);
                this.isLoadingMetadata = false;
            });
    }

    handleSearchChange(event) {
        this.searchKeyword = event.detail.value;
        this.applyFilter();
    }

    applyFilter() {
        if (!this.searchKeyword || this.searchKeyword.trim() === '') {
            this.filteredComponents = this.componentsList;
        } else {
            const term = this.searchKeyword.toLowerCase();
            this.filteredComponents = this.componentsList.filter(item => 
                item.label.toLowerCase().includes(term)
            );
        }
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const currentTypeRows = this.componentsList.map(item => item.value);
        
        currentTypeRows.forEach(val => {
            if (this.selectionsMap.has(val)) {
                this.selectionsMap.delete(val);
            }
        });

        selectedRows.forEach(row => {
            this.selectionsMap.set(row.value, {
                label: row.label,
                value: row.value,
                type: row.type
            });
        });

        this.selectionsMap = new Map(this.selectionsMap);
    }

    handleRemoveSelection(event) {
        const id = event.target.dataset.id;
        if (this.selectionsMap.has(id)) {
            this.selectionsMap.delete(id);
            this.selectionsMap = new Map(this.selectionsMap);
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCommit() {
        if (this.isCommitDisabled) return;

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
                if (result.success) {
                    this.resetFormState();
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Commit changes operation initiated successfully on GitHub.',
                            variant: 'success'
                        })
                    );
                    this.dispatchEvent(new CloseActionScreenEvent());
                    this.dispatchEvent(new CustomEvent('commit'));
                } else {
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