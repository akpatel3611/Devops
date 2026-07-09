import { LightningElement, track, api } from 'lwc';
import searchContacts from '@salesforce/apex/contactformcontroller.searchContacts';
import linkContactsToOpportunity from '@salesforce/apex/contactformcontroller.linkContactsToOpportunity';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class createMultiForm extends LightningElement {
    @api recordId; // Current Opportunity Id
    @track searchResults;
    @track selectedContacts = [];

    columns = [
        { label: 'Name', fieldName: 'Name' },
        { label: 'Email', fieldName: 'Email' },
        { label: 'Phone', fieldName: 'Phone' }
    ];

    // Search contacts
    handleSearch(event) {
        let searchKey = event.target.value;
        if (searchKey && searchKey.length >= 2) {
            searchContacts({ searchKey })
                .then(result => {
                    this.searchResults = result;
                })
                .catch(error => {
                    this.showToast('Error', error.body.message, 'error');
                });
        } else {
            this.searchResults = [];
        }
    }

    // Track selected contacts
    handleRowSelection(event) {
        this.selectedContacts = event.detail.selectedRows;
    }

    // Save selected contacts
    handleSave() {
        let contactIds = this.selectedContacts.map(c => c.Id);
        if (contactIds.length === 0) {
            this.showToast('Error', 'Please select at least one contact', 'error');
            return;
        }

        linkContactsToOpportunity({ opportunityId: this.recordId, contactIds: contactIds })
            .then(() => {
                this.showToast('Success', 'Contacts linked to Opportunity successfully!', 'success');
                
                // Close modal
                this.handleClose();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    // Close modal
    handleClose() {
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }

    // Show toast
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}