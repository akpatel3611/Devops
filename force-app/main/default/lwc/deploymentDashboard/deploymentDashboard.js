import { LightningElement, track } from 'lwc';

import getEnvironments
from '@salesforce/apex/EnvironmentController.getEnvironments';

import getSourceEnvironmentStatus
from '@salesforce/apex/MetadataDiscoveryService.getSourceEnvironmentStatus';

import getMetadataTypes
from '@salesforce/apex/MetadataExplorerController.getMetadataTypes';

import getMetadata
from '@salesforce/apex/MetadataExplorerController.getMetadata';

import getReleases
from '@salesforce/apex/MetadataSelectionController.getReleases';

import getUserStories
from '@salesforce/apex/MetadataSelectionController.getUserStories';

import scanAndVerifyBranch
from '@salesforce/apex/MetadataSelectionController.scanAndVerifyBranch';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

import saveMetadataSelections
from '@salesforce/apex/MetadataSaveController.saveMetadataSelections';

import commitChanges
from '@salesforce/apex/CommitChangesRuntimeService.commitChanges';

// import validateSourceEnvironment
// from '@salesforce/apex/ExternalMetadataController.validateSourceEnvironment';

import getCredentialByEnvironment
from '@salesforce/apex/DeploymentCredentialController.getCredentialByEnvironment';

import compareMetadata from '@salesforce/apex/CompareMetadataController.compareMetadata';

import validateDeployment
from '@salesforce/apex/DeploymentValidationController.validateDeployment';

export default class DeploymentDashboard extends LightningElement {

    sourceOrg;
    targetOrg;
    selectedMetadataType;

    searchKeyword = '';
    environmentStatus;
    releaseId;
    userStoryId;
    selectedSourceBranch;

    isValidating = false;
    isComparing = false;
    
    // Button visibility flags
    @track showSaveButton = true;
    @track showValidateButton = false;
    @track showDeployButton = false;

    @track compareResults = [];
    @track validationResults = [];
    
    @track releaseOptions = [];
    @track userStoryOptions = [];

    @track environmentOptions = [];
    @track metadataTypes = [];
    @track metadataList = [];
    @track filteredMetadataList = [];
    @track selectedComponents = [];
    
    // Searchable dropdown fields
    @track isMetadataDropdownOpen = false;
    @track metadataTypeSearchValue = '';
    
    // Branch scan fields
    @track showBranchSelection = false;
    @track matchingBranchOptions = [];
    @track matchingBranches = [];


    connectedCallback() {
        this.loadEnvironments();
        this.loadReleases();
        this.loadUserStories();
    }

    loadEnvironments() {

        getEnvironments()
        .then(result => {

            this.environmentOptions = result;

        })
        .catch(error => {

            console.error(error);

        });
    }

    loadReleases() {
        getReleases()
        .then(result => {
            this.releaseOptions = result;
        })
        .catch(error => {
            console.error(error);
        });
    }

    loadUserStories() {
        getUserStories()
        .then(result => {
            this.userStoryOptions = result;
        })
        .catch(error => {
            console.error(error);
        });
    }
    
    loadMetadataTypes() {

        getMetadataTypes({

            sourceEnvironmentId: this.sourceOrg
        }).then(result => {

            this.metadataTypes = result;

        })
        .catch(error => {

            console.error(error);

        });
    }

    handleSourceChange(event) {
        
        this.sourceOrg =
            event.detail.value;
        
        this.credentialId = null;
        this.credentialName = null;
        this.instanceUrl = null;
        this.sfdxAuthUrl = null;
        
        this.metadataList = [];
        this.filteredMetadataList = [];
        this.selectedComponents = [];
        
        getCredentialByEnvironment({
        
            environmentId :
                this.sourceOrg
        
        })

        .then(result => {
        
            this.credentialId =
                result.credentialId;
        
            this.credentialName =
                result.credentialName;
        
            this.instanceUrl =
                result.instanceUrl;
        
            this.sfdxAuthUrl =
                result.sfdxAuthUrl;
            
            this.loadMetadataTypes();
        
            console.log(
                'Credential Id :',
                this.credentialId
            );
        
            console.log(
                'Credential Name :',
                this.credentialName
            );
        
            console.log(
                'Instance URL :',
                this.instanceUrl
            );
        
            console.log(
                'SFDX URL :',
                this.sfdxAuthUrl
            );

            getSourceEnvironmentStatus({

                environmentId :
                    this.sourceOrg
                        
            })
            
            .then(status => {
            
                this.environmentStatus =
                    status;
            
                console.log(
                    'Environment Status :',
                    status
                );
            });
        })

    .catch(error => {

        console.error(
            'Credential Error',
            error
        );
    });
}

    handleTargetChange(event) {

        this.targetOrg = event.detail.value;
    }

    handleMetadataTypeChange(event) {

        this.selectedMetadataType = event.detail.value;

        this.loadMetadata();
    }

    handleReleaseChange(event) {
        this.releaseId = event.detail.value;
    }
    
    handleBranchChange(event) {
        this.selectedSourceBranch = event.detail.value;
        this.showSaveButton = false;
        this.showValidateButton = true;
    }
    
    handleUserStoryChange(event) {
        this.userStoryId = event.detail.value;
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
            this.isMetadataDropdownOpen ? 'slds-is-open' : ''
        }`;
    }

    get metadataTypeInputValue() {
        if (this.metadataTypeSearchValue) {
            return this.metadataTypeSearchValue;
        }
        if (this.selectedMetadataType) {
            const types = this.metadataTypes || [];
            const found = types.find(type => {
                const val = (type && type.value) ? type.value : type;
                return val === this.selectedMetadataType;
            });
            if (found) {
                return (found && found.label) ? found.label : found;
            }
            return this.selectedMetadataType;
        }
        return '';
    }

    get processedMetadataTypes() {
        const types = this.metadataTypes || [];
        const searchKey = (this.metadataTypeSearchValue || '').toLowerCase();
        
        return types
            .filter(type => {
                const label = (type && type.label) ? type.label : type;
                return !searchKey || (typeof label === 'string' && label.toLowerCase().includes(searchKey));
            })
            .map(type => {
                const label = (type && type.label) ? type.label : type;
                const value = (type && type.value) ? type.value : type;
                const isSelected = value === this.selectedMetadataType;
                return {
                    label: label,
                    value: value,
                    isSelected: isSelected,
                    optionClass: `slds-media slds-media_center slds-listbox__option slds-listbox__option_plain ${
                        isSelected ? 'slds-is-selected' : ''
                    }`
                };
            });
    }

    get hasFilteredMetadataTypes() {
        return this.processedMetadataTypes.length > 0;
    }

    handleMetadataTypeSearch(event) {
        this.metadataTypeSearchValue = event.target.value;
        this.isMetadataDropdownOpen = true;
    }

    handleMetadataTypeClick() {
        this.isMetadataDropdownOpen = !this.isMetadataDropdownOpen;
    }

    handleMetadataTypeSelect(event) {
        const selectedValue = event.currentTarget.dataset.value;
        this.selectedMetadataType = selectedValue;
        this.metadataTypeSearchValue = '';
        this.isMetadataDropdownOpen = false;
        this.loadMetadata();
    }

    loadMetadata() {

    this.metadataList = [];
    this.filteredMetadataList = [];

    getMetadata({

        componentType : this.selectedMetadataType,
        sourceEnvironmentId : this.sourceOrg
    })
        .then(result => {
                
            console.log(
                'Metadata Type:',
                this.selectedMetadataType
            );
        
            console.log(
                'Metadata Result:',
                result
            );
        
            this.metadataList = result || [];
        
            this.filteredMetadataList =
                [...this.metadataList];
        })
        .catch(error => {
        
            console.error(error);
        
            this.metadataList = [];
        
            this.filteredMetadataList = [];
        });
    }

    handleSearch(event) {

        this.searchKeyword =
            event.target.value.toLowerCase();

        this.filteredMetadataList =
            this.metadataList.filter(item =>
                item.label.toLowerCase()
                .includes(this.searchKeyword)
            );
    }

    handleMetadataSelect(event) {

        const value =
            event.currentTarget.dataset.value;

        const label =
            event.currentTarget.dataset.label;

        const exists =
            this.selectedComponents.find(
                item => item.value === value
            );

        if(!exists){

            this.selectedComponents = [
                ...this.selectedComponents,
                {
                    label,
                    value
                }
            ];
        }
    }

    handleSave() {
        if (!this.userStoryId) {
            this.showError('Please select a User Story');
            return;
        }

        if (this.selectedComponents.length === 0) {
            this.showError('Please select metadata components to save.');
            return;
        }

        const metadataNames = this.selectedComponents.map(item => item.value);

        saveMetadataSelections({
            userStoryId: this.userStoryId,
            metadataType: this.selectedMetadataType,
            metadataNames: metadataNames
        })
        .then(() => {
            const filePaths = this.selectedComponents.map(item => 
                this.getFilePath(this.selectedMetadataType, item.value)
            );

            return scanAndVerifyBranch({
                userStoryId: this.userStoryId,
                filePaths: filePaths
            });
        })
        .then(result => {
            if (result.success) {
                if (result.autoSelectedBranch) {
                    this.selectedSourceBranch = result.autoSelectedBranch;
                    this.showBranchSelection = false;
                    
                    // Transition to Validate button
                    this.showSaveButton = false;
                    this.showValidateButton = true;
                    this.showDeployButton = false;
                    
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: result.message,
                        variant: 'success'
                    }));
                } else if (result.matchingBranches && result.matchingBranches.length > 0) {
                    this.showBranchSelection = true;
                    this.matchingBranches = result.matchingBranches;
                    this.matchingBranchOptions = result.matchingBranches.map(branch => ({
                        label: branch,
                        value: branch
                    }));
                    
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Branch Selection Required',
                        message: result.message,
                        variant: 'info'
                    }));
                }
            } else {
                this.showError(result.message);
            }
        })
        .catch(error => {
            this.showError(error?.body?.message || 'Save & Scan Failed');
        });
    }

    getFilePath(metadataType, apiName) {
        let folder = '';
        let ext = '';
        
        if (metadataType === 'ApexClass') {
            folder = 'classes';
            ext = '.cls';
        } else if (metadataType === 'ApexTrigger') {
            folder = 'triggers';
            ext = '.trigger';
        } else if (metadataType === 'ApexPage') {
            folder = 'pages';
            ext = '.page';
        } else if (metadataType === 'ApexComponent') {
            folder = 'components';
            ext = '.component';
        } else if (metadataType === 'LightningComponentBundle') {
            return 'force-app/main/default/lwc/' + apiName + '/' + apiName + '.js';
        } else if (metadataType === 'AuraDefinitionBundle') {
            return 'force-app/main/default/aura/' + apiName + '/' + apiName + '.cmp';
        } else if (metadataType === 'CustomObject') {
            return 'force-app/main/default/objects/' + apiName + '/' + apiName + '.object-meta.xml';
        } else if (metadataType === 'CustomField') {
            if (apiName.includes('.')) {
                let parts = apiName.split('.');
                return 'force-app/main/default/objects/' + parts[0] + '/fields/' + parts[1] + '.field-meta.xml';
            }
        } else {
            folder = metadataType.toLowerCase() + 's';
            ext = '.' + metadataType.toLowerCase();
        }
        
        return 'force-app/main/default/' + folder + '/' + apiName + ext;
    }

    handleValidate() {
        if (!this.userStoryId) {
            this.showError('Please select a User Story');
            return;
        }

        this.validationResults = [];
        this.isValidating = true;

        const componentNames = this.selectedComponents.map(item => item.value);

        validateDeployment({
            sourceEnvironmentId: this.sourceOrg,
            targetEnvironmentId: this.targetOrg,
            metadataType: this.selectedMetadataType,
            componentNames: componentNames
        })
        .then(result => {
            this.validationResults = result;
            
            const hasFailures = result.some(item => item.status === 'Failure' || item.status === 'Error');
            if (hasFailures) {
                this.showError('Validation failed with errors. Fix conflicts before deploying.');
            } else {
                // Transition to Deploy button
                this.showSaveButton = false;
                this.showValidateButton = false;
                this.showDeployButton = true;
                
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Validation passed successfully. Ready to deploy!',
                    variant: 'success'
                }));
            }
        })
        .catch(error => {
            this.showError(error?.body?.message || 'Validation failed.');
        })
        .finally(() => {
            this.isValidating = false;
        });
    }

    handleDeploy() {
        if (!this.userStoryId) {
            this.showError('Please select a User Story');
            return;
        }

        commitChanges({
            userStoryId: this.userStoryId,
            commitMessage: 'Commit changes for story ' + this.userStoryId
        })
        .then(result => {
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'PR Created',
                    message: 'GitHub Feature Branch and PR created successfully.',
                    variant: 'success'
                }));

                if (result.pullRequestUrl) {
                    window.open(result.pullRequestUrl, '_blank');
                }
            } else {
                this.showError(result.message || 'Failed to create branch/PR on GitHub.');
            }
        })
        .catch(error => {
            this.showError(error?.body?.message || 'Deploy trigger failed.');
        });
    }

    handleRemoveComponent(event) {
        const valueToRemove = event.currentTarget.dataset.value;
        this.selectedComponents = this.selectedComponents.filter(
            item => item.value !== valueToRemove
        );
    }

    get showDeploymentSection() {

        return this.sourceOrg &&
               this.targetOrg;
    }

    showError(message){
        this.dispatchEvent(
        
            new ShowToastEvent({
            
                title : 'Error',
            
                message : message,
            
                variant : 'error'
            })
        );
    }

}