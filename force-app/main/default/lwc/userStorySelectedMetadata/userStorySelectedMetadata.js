import { LightningElement, api, wire, track } from 'lwc';
import getSelectedMetadata from '@salesforce/apex/UserStoryWorkspaceController.getSelectedMetadata';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

const DEBUG_PREFIX = '[userStorySelectedMetadata]';

const COLUMNS = [
    { label: 'Name', fieldName: 'Metadata_API_Name__c', type: 'text' },
    { label: 'Type', fieldName: 'Metadata_Type__c', type: 'text' },
    { label: 'Git Operation', fieldName: 'Action__c', type: 'text' },
    { label: 'File Path', fieldName: 'File_Path__c', type: 'text' },
    { label: 'Last Modified', fieldName: 'LastModifiedDate', type: 'date', typeAttributes: {
        year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
    }}
];

export default class UserStorySelectedMetadata extends LightningElement {
    @api recordId;
    @track columns = COLUMNS;
    @track metadataList = [];
    @track isLoading = true;

    wiredMetadataResult;
    refreshHandlerId;

    connectedCallback() {
        this.metadataList = [];
        this.isLoading = true;
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshContainer.bind(this));
        if (this.wiredMetadataResult) {
            refreshApex(this.wiredMetadataResult);
        }
    }

    disconnectedCallback() {
        if (this.refreshHandlerId) {
            unregisterRefreshHandler(this.refreshHandlerId);
        }
    }

    refreshContainer() {
        if (this.wiredMetadataResult) {
            return refreshApex(this.wiredMetadataResult);
        }
        return Promise.resolve();
    }

    @wire(getSelectedMetadata, { userStoryId: '$recordId' })
    wiredMetadata(result) {
        this.wiredMetadataResult = result;
        this.isLoading = true;
        console.debug(`${DEBUG_PREFIX} getSelectedMetadata wire response`, {
            recordId: this.recordId,
            hasData: !!result.data,
            hasError: !!result.error
        });
        if (result.data) {
            this.metadataList = result.data;
            console.debug(`${DEBUG_PREFIX} selected metadata loaded`, {
                recordId: this.recordId,
                count: this.metadataList.length
            });
            this.isLoading = false;
        } else if (result.error) {
            console.error(`${DEBUG_PREFIX} Error fetching selected metadata`, this.normalizeError(result.error), result.error);
            this.isLoading = false;
        }
    }

    @wire(getRecord, { recordId: '$recordId', layoutTypes: ['Full'], modes: ['View'] })
    wiredRecord() {
        if (this.wiredMetadataResult) {
            refreshApex(this.wiredMetadataResult);
        }
    }

    get hasMetadata() {
        return this.metadataList && this.metadataList.length > 0;
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