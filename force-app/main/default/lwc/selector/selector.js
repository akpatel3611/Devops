import { LightningElement, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';

const FIELDS = ['User.Name'];

export default class Selector extends LightningElement {
    name; // 👈 This is important for the challenge

    @wire(getRecord, { recordId: USER_ID, fields: FIELDS })
    userRecord({ error, data }) {
        if (data) {
            this.name = data.fields.Name.value;
        } else if (error) {
            this.name = 'Error loading name';
        }
    }
}