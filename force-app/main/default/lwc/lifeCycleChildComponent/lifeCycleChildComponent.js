import { LightningElement } from 'lwc';

export default class LifeCycleChildComponent extends LightningElement {

    constructor(){
        super();
        console.log('Child Constructor Called');
    }

    connectedCallback(){
        console.log('Child connectedCallback Called');
    }
     
    renderedCallback(){
        console.log('Child renderedCallback Called');
    }
    
}