import { api, LightningElement } from 'lwc';

export default class Test extends LightningElement {
    @api inputValue = '';

    handleInputChange(event) {
        this.inputValue = event.target.value;
    }
}