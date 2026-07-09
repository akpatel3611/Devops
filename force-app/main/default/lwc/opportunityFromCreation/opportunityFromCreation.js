import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveOpportunityRecord from '@salesforce/apex/OpportunityController.saveOpportunityRecord';

export default class OpportunityFromCreation extends NavigationMixin(LightningElement) {

    @track OppName = '';
    @track OppAmount = '';
    @track OppCloseDate = '';
    @track stageName = '';
    @track Type = '';
    @track isLoading = false;
    // @track opportunityId;

    get stageOption() {
        return [
            { label: 'Prospecting', value: 'Prospecting' },
            { label: 'Qualification', value: 'Qualification' },
            { label: 'Needs Analysis', value: 'Needs Analysis' },
            { label: 'Proposal/Quote', value: 'Proposal/Quote' },
            { label: 'Demonstration', value: 'Demonstration' },
            { label: 'Decision/Milestone', value: 'Decision/Milestone' }
        ];
    }

    get Types() {
        return [
            { label: 'New Business', value: 'New Business' },
            { label: 'Existing Business', value: 'Existing Business' },
            { label: 'Referral', value: 'Referral' },
            { label: 'Partner', value: 'Partner' },
            { label: 'Other', value: 'Other' }
        ];
    }

    handleInputChange(event) {
        console.log('input changed');
        const field = event.target.dataset.id;
        this[field] = event.target.value;
    }

    handleSave() {
        console.log('save button clicked');
        
        // Form validation
        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;

        const opportunityData = {
            Name: this.OppName,
            Amount: this.OppAmount ? parseFloat(this.OppAmount) : 0,
            CloseDate: this.OppCloseDate,
            StageName: this.stageName,
            Type: this.Type
        };

        saveOpportunityRecord({ opportunityData: JSON.stringify(opportunityData) })
            .then(result => {
                this.opportunityId = result;
                this.showToast('Success', 'Opportunity created successfully!', 'success');
                
                // Navigate to the newly created record
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.opportunityId,
                        objectApiName: 'Opportunity',
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                console.error('Error saving opportunity:', error);
                this.showToast('Error', 'Failed to create opportunity. Please try again.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    validateForm() {
        const requiredFields = [
            { field: 'OppName', label: 'Name' },
            { field: 'OppCloseDate', label: 'Close Date' },
            { field: 'stageName', label: 'Stage' }
        ];

        for (let field of requiredFields) {
            if (!this[field.field]) {
                this.showToast('Error', `${field.label} is required.`, 'error');
                return false;
            }
        }

        return true;
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}