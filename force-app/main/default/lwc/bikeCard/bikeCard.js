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
    bike = {
        name: 'Trail Blazer',
        type: 'Mountain',
        price: 1200
    };
}