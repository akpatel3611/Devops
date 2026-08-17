import { LightningElement, api, wire, track } from 'lwc';
import getPipelineProgress from '@salesforce/apex/UserStoryWorkspaceController.getPipelineProgress';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

export default class PipelineProgressBar extends LightningElement {
    @api recordId;
    @track pipelineName = 'Default Pipeline';
    @track sourceEnvName = 'DEV';
    @track currentStage = 'DEV';
    @track steps = [];

    wiredProgressResult;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshContainer.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshHandlerId) {
            unregisterRefreshHandler(this.refreshHandlerId);
        }
    }

    refreshContainer() {
        if (this.wiredProgressResult) {
            return refreshApex(this.wiredProgressResult);
        }
        return Promise.resolve();
    }

    @wire(getPipelineProgress, { recordId: '$recordId' })
    wiredProgress(result) {
        this.wiredProgressResult = result;
        const { error, data } = result;
        if (data) {
            this.pipelineName = data.pipelineName;
            this.sourceEnvName = data.currentEnvironmentName;
            this.currentStage = data.activeStage;
            this.steps = data.steps || [];
        } else {
            this.steps = [];
            if (error) {
                console.error('Error loading pipeline progress context:', error);
            }
        }
    }

    // Refresh dynamically when any field updates on the record page layout
    @wire(getRecord, { recordId: '$recordId', layoutTypes: ['Full'], modes: ['View'] })
    wiredRecord() {
        if (this.wiredProgressResult) {
            refreshApex(this.wiredProgressResult);
        }
    }

    get hasSteps() {
        return this.steps && this.steps.length > 0;
    }
}