import { LightningElement, track } from 'lwc';
import searchContacts from '@salesforce/apex/ContactController.searchContacts';
import getContactDetails from '@salesforce/apex/ContactController.getContactDetails';

export default class SearchBarOnContact extends LightningElement {
    @track searchKey = '';
    @track searchResult = [];
    @track selectedContactId;
    @track contactDetails = {};
    @track isLoadingDetails = false; // new tracker
    timeout;

    handleSearch(event) {
        clearTimeout(this.timeout);
        this.searchKey = event.target.value;

        this.timeout = setTimeout(() => {
            if (this.searchKey.length >= 2) {
                this.fetchContacts();
            } else {
                this.searchResult = [];
            }
        }, 300);
    }

    fetchContacts() {
        searchContacts({searchKey: this.searchKey })
            .then(result => {
                this.searchResult = result;
            })
            .catch(error => {
                console.error('Error fetching contacts', error);
            });
    }

    handleContactSelect(event) {
        this.selectedContactId = event.target.value;
        this.contactDetails = {}; // reset safely
        this.isLoadingDetails = true; // show loading
        this.searchResult = [];
        this.fetchContactDetails();
    }

    fetchContactDetails() {
        getContactDetails({ contactId: this.selectedContactId})
            .then(result => {
                this.contactDetails = result || {};
                this.isLoadingDetails = false;
            })
            .catch(error => {
                console.error('Error fetching contact details', error);
                this.isLoadingDetails = false;
            });
    }
}