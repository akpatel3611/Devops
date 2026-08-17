import { LightningElement } from 'lwc';
import cicddemocontroller from '@salesforce/apex/cicddemocontroller.CICDDemoController';
export default class Cicddemo extends LightningElement {
    // deprecated lifecycle hooks
    // constructor() {
    //     super();
    //     console.log('cicddemo component initialized');
    // full deployment test 3
    // }
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

    // full deployment test

    disconnectedCallback() {
        console.log('cicddemo component unloaded');
    } 

    renderedCallback() {
        console.log('cicddemo component rendered');
    }
    
}