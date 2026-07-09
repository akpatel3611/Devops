import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEnvironments
from '@salesforce/apex/EnvironmentController.getEnvironments';

import getSourceEnvironmentStatus
from '@salesforce/apex/MetadataDiscoveryService.getSourceEnvironmentStatus';

import getMetadataTypes
from '@salesforce/apex/MetadataExplorerController.getMetadataTypes';

import getMetadata
from '@salesforce/apex/MetadataExplorerController.getMetadata';

import getProjects
from '@salesforce/apex/MetadataSelectionController.getProjects';

import getUserStories
from '@salesforce/apex/MetadataSelectionController.getUserStories';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

import getCredentialByEnvironment
from '@salesforce/apex/DeploymentCredentialController.getCredentialByEnvironment';

import compareMetadata from '@salesforce/apex/CompareMetadataController.compareMetadata';

import validateDeployment
from '@salesforce/apex/DeploymentValidationController.validateDeployment';

import getLivePipeline from '@salesforce/apex/DeploymentDashboardController.getLivePipeline';
import getLiveDeployments from '@salesforce/apex/DeploymentDashboardController.getLiveDeployments';
import getActivityFeed from '@salesforce/apex/DeploymentDashboardController.getActivityFeed';
import getStats from '@salesforce/apex/DeploymentDashboardController.getStats';
import getRecordsForObject from '@salesforce/apex/DeploymentDashboardController.getRecordsForObject';
import getLivePromotions from '@salesforce/apex/DeploymentDashboardController.getLivePromotions';
import getLiveReleases from '@salesforce/apex/DeploymentDashboardController.getLiveReleases';




export default class DeploymentDashboardLocal extends NavigationMixin(LightningElement) {

    sourceOrg;
    targetOrg;
    selectedMetadataType;

    searchKeyword = '';
    environmentStatus;
    projectId = null;
    userStoryId = null;
    selectedObjectApiName = '';

    isValidating = false;
    isComparing = false;
    isSidebarCollapsed = false;

    get sidebarClass() {
        return this.isSidebarCollapsed 
            ? 'slds-col slds-size_1-of-12 sidebar-collapsed' 
            : 'slds-col slds-size_2-of-12 sidebar-expanded';
    }

    get centerClass() {
        return this.isSidebarCollapsed 
            ? 'slds-col slds-size_8-of-12' 
            : 'slds-col slds-size_7-of-12';
    }

    get sidebarToggleIcon() {
        return this.isSidebarCollapsed ? 'utility:right' : 'utility:left';
    }

    toggleSidebar() {
        this.isSidebarCollapsed = !this.isSidebarCollapsed;
    }

    activeTab = 'dashboard';

    get currentTabLabel() {
        const item = this.navItems.find(nav => nav.name === this.activeTab);
        return item ? item.label : 'DevOps Command Center';
    }

    get isDashboardOrDeployment() {
        return this.activeTab === 'dashboard' || this.activeTab === 'deployment';
    }
    
    @track stats = {
        repository: 'N/A',
        currentReleaseVersion: 'N/A',
        currentReleaseStatus: 'N/A',
        pipelineStatus: 'All Green',
        lastRunText: 'No runs',
        openPrCount: 0,
        openDeploymentCount: 0
    };

    @track navItems = [
        { name: 'dashboard', label: 'Dashboard', icon: 'utility:home', liClass: 'nav-item active' },
        { name: 'deployment', label: 'Deployment Center', icon: 'utility:send', liClass: 'nav-item' },
        { name: 'credentials', label: 'Credentials', icon: 'utility:key', liClass: 'nav-item' },
        { name: 'environment', label: 'Environment', icon: 'utility:database', liClass: 'nav-item' },
        { name: 'pipeline', label: 'Pipeline', icon: 'utility:flow', liClass: 'nav-item' },
        { name: 'userstory', label: 'User Story', icon: 'utility:description', liClass: 'nav-item' },
        { name: 'release', label: 'Release', icon: 'utility:package', liClass: 'nav-item' },
        { name: 'promotion', label: 'Promotion', icon: 'utility:forward', liClass: 'nav-item' },
        { name: 'snapshot', label: 'Git Snapshot', icon: 'utility:save', liClass: 'nav-item' },
        { name: 'repository', label: 'Git Repository', icon: 'utility:opened_folder', liClass: 'nav-item' },
        { name: 'properties', label: 'System Properties', icon: 'utility:settings', liClass: 'nav-item' },
        { name: 'stages', label: 'Stages', icon: 'utility:layers', liClass: 'nav-item' }
    ];

    @track pipelineSteps = [];
    @track liveDeployments = [];
    @track livePromotions = [];
    @track liveReleases = [];
    @track activityFeed = [];
    
    currentPipelineBranch = 'N/A';
    pipelineStartedBy = 'System';
    listViewTitle = '';

    @track compareResults = [];
    @track validationResults = [];
    
    @track projectOptions = [];
    @track userStoryOptions = [];

    @track environmentOptions = [];
    @track metadataTypes = [];
    @track metadataList = [];
    @track filteredMetadataList = [];
    @track selectedComponents = [];

    @wire(getLivePipeline, { projectId: '$projectId' })
    wiredPipeline({ error, data }) {
        if (data) {
            this.processPipelineData(data);
        } else {
            this.pipelineSteps = [];
            this.currentPipelineBranch = 'N/A';
        }
    }

    @wire(getLiveDeployments, { projectId: '$projectId' })
    wiredDeployments({ error, data }) {
        if (data) {
            this.processDeploymentData(data);
        } else {
            this.liveDeployments = [];
        }
    }

    @wire(getActivityFeed, { projectId: '$projectId' })
    wiredActivities({ error, data }) {
        if (data) {
            this.processActivityData(data);
        } else {
            this.activityFeed = [];
        }
    }

    @wire(getStats, { projectId: '$projectId' })
    wiredStats({ error, data }) {
        if (data) {
            this.stats = {
                repository: data.repository || 'N/A',
                currentReleaseVersion: data.currentReleaseVersion || 'N/A',
                currentReleaseStatus: data.currentReleaseStatus || 'N/A',
                pipelineStatus: data.pipelineStatus || 'All Green',
                lastRunText: data.lastRunText || 'No runs',
                openPrCount: data.openPrCount || 0,
                openDeploymentCount: data.openDeploymentCount || 0
            };
        }
    }

    @wire(getLivePromotions, { projectId: '$projectId' })
    wiredPromotions({ error, data }) {
        if (data) {
            this.processPromotionData(data);
        } else {
            this.livePromotions = [];
        }
    }

    @wire(getLiveReleases, { projectId: '$projectId' })
    wiredReleases({ error, data }) {
        if (data) {
            this.processReleaseData(data);
        } else {
            this.liveReleases = [];
        }
    }
    @track genericRecords = [];

    @wire(getRecordsForObject, { objectApiName: '$selectedObjectApiName' })
    wiredGenericRecords({ error, data }) {
        console.log('wiredGenericRecords: selectedObjectApiName = ' + this.selectedObjectApiName);
        if (data) {
            console.log('wiredGenericRecords data retrieved:', JSON.stringify(data));
            this.genericRecords = data.map(rec => {
                const cols = [];
                const headers = this.genericHeaders;
                
                // We loop through the display columns (index 1 to headers.length - 1)
                for (let i = 1; i < headers.length; i++) {
                    const headerName = headers[i];
                    const colKey = `col${i}`;
                    const val = rec[colKey];
                    
                    const isBadge = (headerName === 'Status' || headerName === 'Connection Status');
                    const cleanVal = (val !== undefined && val !== null && val !== 'null' && val !== '') ? val : 'N/A';
                    
                    if (isBadge) {
                        let badgeClass = 'badge queued';
                        if (cleanVal === 'Completed' || cleanVal === 'Approved' || cleanVal === 'Success' || cleanVal === 'Succeeded' || cleanVal === 'Active') {
                            badgeClass = 'badge success';
                        } else if (cleanVal === 'In Progress' || cleanVal === 'Running') {
                            badgeClass = 'badge progress';
                        } else if (cleanVal === 'Failed') {
                            badgeClass = 'badge failed';
                        } else if (cleanVal === 'Pending Approval' || cleanVal === 'Pending') {
                            badgeClass = 'badge pending';
                        } else if (cleanVal === 'Rollback') {
                            badgeClass = 'badge rollback';
                        }
                        cols.push({ key: `c${i}`, value: cleanVal, isBadge: true, badgeClass: badgeClass });
                    } else {
                        cols.push({ key: `c${i}`, value: cleanVal, isBadge: false });
                    }
                }
                
                return {
                    ...rec,
                    displayColumns: cols
                };
            });
        } else if (error) {
            console.error('wiredGenericRecords error:', JSON.stringify(error));
            this.genericRecords = [];
        } else {
            this.genericRecords = [];
        }
    }

    get hasGenericRecords() {
        return this.genericRecords && this.genericRecords.length > 0;
    }

    get genericHeaders() {
        const headersMap = {
            credentials: ['Credential Name', 'Environment', 'Instance URL'],
            environment: ['Environment Name', 'Environment Type', 'Org URL', 'Connection Status'],
            pipeline: ['Pipeline Name', 'Project', 'Branch', 'Target Environment', 'Status'],
            userstory: ['Story Number', 'Story Title', 'Status'],
            release: ['Release Name', 'Version', 'Status'],
            promotion: ['Promotion Name', 'Source', 'Target', 'Status'],
            deployment: ['Deployment Name', 'Source', 'Target', 'Status'],
            snapshot: ['Snapshot Name', 'Branch Name', 'Author'],
            repository: ['Repository Name', 'Repo Display Name', 'Git Provider'],
            properties: ['Property Name', 'Key', 'Value'],
            stages: ['Stage Name', 'Order', 'Status']
        };
        return headersMap[this.activeTab] || ['Name', 'Details'];
    }

    handleMenuSelect(event) {
        const actionName = event.detail.value;
        const recordId = event.currentTarget.dataset.id;
        
        if (actionName === 'edit') {
            this.showToast('Edit Record', 'Clicked Edit for record ID: ' + recordId, 'info');
        } else if (actionName === 'delete') {
            this.showToast('Delete Record', 'Clicked Delete for record ID: ' + recordId, 'warning');
        } else if (actionName === 'sync') {
            this.showToast('Sync Record', 'Syncing record ID: ' + recordId, 'success');
        }
    }

    handleRecordNavigate(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
                }
            });
        }
    }

    handleDashboardRecordNavigate(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;
        if (recordId && objectApiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
                }
            });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }


    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleNavSelect(event) {
        const selectedName = event.currentTarget.dataset.name;
        this.activeTab = selectedName;
        
        const mapping = {
            credentials: 'Credentials__c',
            environment: 'Deployment_Environment__c',
            pipeline: 'Pipeline__c',
            userstory: 'User_Story__c',
            release: 'Release__c',
            promotion: 'Promotion__c',
            deployment: 'Deployment_Request__c',
            snapshot: 'Git_Snapshot__c',
            repository: 'Git_Repository__c',
            properties: 'System_Property__c',
            stages: 'Stage__c'
        };
        this.selectedObjectApiName = mapping[selectedName] || '';
        
        this.navItems = this.navItems.map(item => {
            return {
                ...item,
                liClass: item.name === selectedName ? 'nav-item active' : 'nav-item'
            };
        });

        // Set generic list view title
        const matchedItem = this.navItems.find(item => item.name === selectedName);
        if (matchedItem) {
            this.listViewTitle = matchedItem.label;
        }
    }

    get showDashboardView() {
        return this.activeTab === 'dashboard';
    }

    get showDeploymentView() {
        return this.activeTab === 'deployment';
    }

    get showGenericListView() {
        return this.activeTab !== 'dashboard' && this.activeTab !== 'deployment';
    }

    get hasPipeline() {
        return this.pipelineSteps && this.pipelineSteps.length > 0;
    }

    get hasDeployments() {
        return this.liveDeployments && this.liveDeployments.length > 0;
    }

    get hasPromotions() {
        return this.livePromotions && this.livePromotions.length > 0;
    }

    get hasReleases() {
        return this.liveReleases && this.liveReleases.length > 0;
    }

    get hasActivities() {
        return this.activityFeed && this.activityFeed.length > 0;
    }

    processPipelineData(data) {
        if (data && data.stages && data.stages.length > 0) {
            const currentStageId = data.pipeline.Current_Stage__c;
            this.currentPipelineBranch = data.pipeline.Current_Branch__c || 'N/A';
            this.pipelineStartedBy = 'System';
            
            this.pipelineSteps = data.stages.map((stage, index) => {
                const isCurrent = stage.Id === currentStageId;
                const isCompleted = stage.Status__c === 'Completed' || stage.Status__c === 'Success';
                const isRunning = stage.Status__c === 'Running' || stage.Status__c === 'In Progress';
                
                let itemClass = 'p-step';
                if (isCompleted) {
                    itemClass += ' done';
                } else if (isRunning || isCurrent) {
                    itemClass += ' active';
                }
                
                return {
                    name: stage.Id,
                    label: stage.Name,
                    status: isCompleted ? 'Completed' : (isRunning || isCurrent ? 'Running…' : 'Pending'),
                    isCompleted: isCompleted,
                    isRunning: isRunning || isCurrent,
                    orderIndex: index + 1,
                    class: itemClass
                };
            });
        } else {
            this.pipelineSteps = [];
            this.currentPipelineBranch = 'N/A';
        }
    }

    processDeploymentData(data) {
        if (data && data.length > 0) {
            this.liveDeployments = data.map(dep => {
                const status = dep.Deployment_Status__c;
                let progress = 0;
                let badgeClass = 'badge queued';
                let progressColor = 'var(--queued)';
                let progressText = 'Waiting';
                let statusText = status;
                
                if (status === 'Completed' || status === 'Success') {
                    progress = 100;
                    badgeClass = 'badge success';
                    progressColor = 'var(--success)';
                    progressText = '100%';
                    statusText = 'Succeeded';
                } else if (status === 'Running' || status === 'In Progress') {
                    progress = 64;
                    badgeClass = 'badge progress';
                    progressColor = 'var(--inprogress)';
                    progressText = '64%';
                    statusText = 'In Progress';
                } else if (status === 'Failed') {
                    progress = 38;
                    badgeClass = 'badge failed';
                    progressColor = 'var(--failed)';
                    progressText = '38%';
                    statusText = 'Failed';
                }
                
                const env = dep.Target_Environment__r ? dep.Target_Environment__r.Name__c : 'Sandbox';
                
                return {
                    Id: dep.Id,
                    Name: dep.Deployment_Number__c || dep.Name,
                    envName: env,
                    statusText,
                    customBadgeClass: badgeClass,
                    progressFillStyle: `width: ${progress}%; background: ${progressColor};`,
                    progressText,
                    Started_By__c: dep.Triggered_By__c || 'System'
                };
            });
        } else {
            this.liveDeployments = [];
        }
    }

    processPromotionData(data) {
        if (data && data.length > 0) {
            this.livePromotions = data.map(promo => {
                const status = promo.Status__c;
                let badgeClass = 'badge queued';
                if (status === 'Approved' || status === 'Completed') {
                    badgeClass = 'badge success';
                } else if (status === 'Pending Approval') {
                    badgeClass = 'badge pending';
                }
                
                return {
                    Id: promo.Id,
                    Name: promo.Promotion_Name__c || promo.Name,
                    sourceEnv: promo.Source_Environment__r ? promo.Source_Environment__r.Name__c : 'N/A',
                    targetEnv: promo.Target_Environment__r ? promo.Target_Environment__r.Name__c : 'N/A',
                    Triggered_By__c: promo.Triggered_By__c || 'System',
                    Status__c: status,
                    customBadgeClass: badgeClass
                };
            });
        } else {
            this.livePromotions = [];
        }
    }

    processReleaseData(data) {
        if (data && data.length > 0) {
            this.liveReleases = data.map(rel => {
                const status = rel.Status__c;
                let badgeClass = 'badge completed';
                if (status === 'Rollback') {
                    badgeClass = 'badge rollback';
                }
                
                return {
                    Id: rel.Id,
                    Version__c: rel.Version__c || 'N/A',
                    Release_Name__c: rel.Release_Name__c || rel.Name,
                    Status__c: status,
                    customBadgeClass: badgeClass,
                    releaseDateFormatted: rel.Release_Date__c ? new Date(rel.Release_Date__c).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'
                };
            });
        } else {
            this.liveReleases = [];
        }
    }

    processActivityData(data) {
        if (data && data.length > 0) {
            this.activityFeed = data.map(event => {
                let customIconClass = 'act-icon ';
                let iconText = '●';
                
                if (event.badgeColor === 'badge-purple') {
                    customIconClass += 'icon-purple-bg';
                    iconText = 'PR';
                } else if (event.badgeColor === 'badge-blue') {
                    customIconClass += 'icon-blue-bg';
                    iconText = '▶';
                } else if (event.badgeColor === 'badge-red') {
                    customIconClass += 'icon-red-bg';
                    iconText = '✕';
                } else if (event.badgeColor === 'badge-green') {
                    customIconClass += 'icon-green-bg';
                    iconText = '✓';
                } else if (event.badgeColor === 'badge-teal') {
                    customIconClass += 'icon-teal-bg';
                    iconText = '↩';
                } else {
                    customIconClass += 'icon-orange-bg';
                    iconText = '!';
                }
                
                return {
                    Id: event.eventDate + '-' + event.type,
                    title: event.title,
                    description: event.description,
                    timeText: event.eventDate ? new Date(event.eventDate).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + ' • ' + new Date(event.eventDate).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A',
                    customIconClass,
                    iconText
                };
            });
        } else {
            this.activityFeed = [];
        }
    }

    connectedCallback() {
        this.loadEnvironments();
        this.loadProjects();
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

    loadProjects() {

        getProjects()

        .then(result => {

            this.projectOptions = result;

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

    handleProjectChange(event) {

        this.projectId = event.detail.value;
    }
    
    handleUserStoryChange(event) {
    
        this.userStoryId = event.detail.value;
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

    handleValidate(){
        
        this.validationResults = [];
        const componentNames =

            this.selectedComponents.map(
                item => item.value
            );

        validateDeployment({

            sourceEnvironmentId:
                this.sourceOrg,

            targetEnvironmentId:
                this.targetOrg,

            metadataType:
                this.selectedMetadataType,

            componentNames:
                componentNames
        })

        .then(result => {

            this.validationResults =
                result;
        })

        .catch(error => {

            this.dispatchEvent(

                new ShowToastEvent({

                    title : 'Error',

                    message :
                        error.body.message,

                    variant : 'error'
                })
            );
        });
    }

handleDeploy(){

    this.dispatchEvent(

        new ShowToastEvent({

            title : 'Success',

            message : 'Deployment started successfully',

            variant : 'success'

        })
    );
}

// handleSave(){

//     if(!this.userStoryId){

//         this.dispatchEvent(

//             new ShowToastEvent({

//                 title : 'Error',

//                 message : 'Please select User Story',

//                 variant : 'error'

//             })
//         );

//         return;
//     }

//     if(this.selectedComponents.length === 0){

//         this.dispatchEvent(

//             new ShowToastEvent({

//                 title : 'Error',

//                 message : 'Please select metadata',

//                 variant : 'error'

//             })
//         );

//         return;
//     }

//     const metadataNames =
//         this.selectedComponents.map(
//             item => item.value
//         );

//     saveMetadataSelections({

//         userStoryId :
//             this.userStoryId,

//         metadataType :
//             this.selectedMetadataType,

//         metadataNames :
//             metadataNames
//     })

//     .then(() => {

//         this.dispatchEvent(

//             new ShowToastEvent({

//                 title : 'Success',

//                 message : 'Metadata saved successfully',

//                 variant : 'success'

//             })
//         );

//         this.selectedComponents = [];
//     })

//     .catch(error => {

//         this.dispatchEvent(

//             new ShowToastEvent({

//                 title : 'Error',

//                 message :
//                     error.body.message,

//                 variant : 'error'

//             })
//         );
//     });
// }

handleRemoveComponent(event){

    const valueToRemove =
        event.currentTarget.dataset.value;

    this.selectedComponents =
        this.selectedComponents.filter(

            item =>
                item.value !== valueToRemove
        );
}

    handleCompare(){
        this.compareResults = [];
        if(
            !this.selectedMetadataType
        ){
            this.showError(
                'Please select Metadata Type'
            );
            return;
        }

        if(
            this.selectedComponents.length === 0
        ){
            this.showError(
                'Please select Metadata'
            );
            return;
        }

        const componentNames =

            this.selectedComponents.map(

                item => item.value
            );

        this.isComparing = true;

        compareMetadata({

            targetEnvironmentId:
                this.targetOrg,

            metadataType:
                this.selectedMetadataType,

            componentNames:
                componentNames
        })

        .then(result => {

            this.compareResults =
                result;
        })

        .catch(error => {

            this.showError(

                error?.body?.message ||
                'Compare Failed'
            );
        })

        .finally(() => {

            this.isComparing = false;
        });
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