import { LightningElement } from 'lwc';
import cicddemocontroller from '@salesforce/apex/cicddemocontroller.CICDDemoController';
export default class Cicddemo extends LightningElement {
    connectedCallback() {
        console.log('cicddemo component loaded');
        cicddemocontroller()
            .then(result => {
                console.log('Apex method executed successfully');
            })
            .catch(error => {
                console.error('Error executing Apex method: ', error);
            });
    }

    disconnectedCallback() {
        console.log('cicddemo component unloaded');
    }
}