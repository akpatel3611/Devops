import { LightningElement } from 'lwc';

export default class BikeCard extends LightningElement {
    constructor() {
        super();
        console.log('BikeCard component initialized');
    }
    connectedCallback() {
        console.log('connectedCallback called');
    }
    renderedCallback() {
        console.log('renderedCallback called');
    }
     disconnectedCallback() {
        console.log('disconnectedCallback called');
    }
    // No additional methods or logic needed here
    //console.log('BikeCard component disconnected');
    //Pr and validation Tst 1
    // Full Test deployment
    // full deployment test

    bike = {
        name: 'Trail Blazer',
        type: 'Mountain',
        price: 1200
    };
}