import { LightningElement, track } from 'lwc';
import saveContacts from '@salesforce/apex/ContactController.saveContacts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CreateMultiContact extends NavigationMixin(LightningElement) {
    @track contactList = [{ FirstName: '', LastName: '', Email: '', Phone: '' }];
    @track createdContacts = [];
    @track isLoading = false; // Spinner control
    @track showTable = false; // Table visibility

    // Inline editable columns for lightning-datatable
    columns = [
        { label: 'Name', fieldName: 'Name', editable: true },
        { label: 'Email', fieldName: 'Email', type: 'email', editable: true },
        { label: 'Phone', fieldName: 'Phone', type: 'phone', editable: true }
    ];

    // Add new contact form
    createEmptyContact() {
        return {
            FirstName: '',
            LastName: '',
            Email: '',
            Phone: ''
        };
    }
    addContactForm() {
        this.contactList = [...this.contactList, this.createEmptyContact()];
    }

    removeContactForm(event) {
        let index = event.currentTarget.dataset.index;
        if (this.contactList.length > 1) {
            this.contactList.splice(index, 1);
            this.contactList = [...this.contactList];
        } else {
            this.showToast('Error', 'At least one contact form must remain.', 'error');
        }
    }

    handleInputChange(event) {
        let index = event.target.dataset.index;
        let field = event.target.name;
        this.contactList[index][field] = event.target.value;
    }

    // Save new contacts
    saveContactsHandler() {
        let allValid = true;
        this.template.querySelectorAll('lightning-input').forEach(input => {
            if (!input.reportValidity()) {
                allValid = false;
            }
        });
        if (!allValid) return;

        this.isLoading = true;
        saveContacts({ contactsToInsert: this.contactList })
            .then(result => {
                this.createdContacts = result.map(rec => ({
                    ...rec,
                    Name: rec.FirstName + ' ' + rec.LastName
                }));
                this.showToast('Success', result.length + ' contact(s) created successfully.', 'success');
                this.contactList = [{ FirstName: '', LastName: '', Email: '', Phone: '' }];
                this.showTable = true; // Show table after creation
            })
            .catch(error => this.showToast('Error', error.body ? error.body.message : 'Unknown error', 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSave(event) {
        this.isLoading = true;
        const updatedFields = event.detail.draftValues;
        const updatedContacts = this.createdContacts.map(contact => {
            const updated = updatedFields.find(u => u.Id === contact.Id);
            return updated ? { ...contact, ...updated } : contact;
        });
        saveContacts({ contactsToInsert: updatedContacts })
            .then(result => {
                this.createdContacts = result.map(rec => ({
                    ...rec,
                    Name: rec.FirstName + ' ' + rec.LastName
                }));
                this.showToast('Success', 'Contacts updated successfully.', 'success');
                this.template.querySelector('lightning-datatable').draftValues = [];
                this.showTable = false; // Hides table after save
            })
            .catch(error => this.showToast('Error', error.body ? error.body.message : 'Unknown error', 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    cloneContactForm(event) {
        const index = event.currentTarget.dataset.index;
        const contactToClone = this.contactList[index];
        // Deep clone the contact object
        const clonedContact = { ...contactToClone };
        this.contactList = [
            ...this.contactList.slice(0, Number(index) + 1),
            clonedContact,
            ...this.contactList.slice(Number(index) + 1)
        ];
    }

    // Helper
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    }