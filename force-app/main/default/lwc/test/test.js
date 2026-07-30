import { api, LightningElement } from 'lwc';

export default class Test extends LightningElement {
    @api inputValue = '';

    connectedCallback() {
        // No initialization needed for inputValue in connectedCallback
    }
    // No additional methods or logic needed here
    handleInputChange(event) {
        this.inputValue = event.target.value;
    }
}