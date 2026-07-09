import { LightningElement } from 'lwc';

export default class Lifecyclehookexample extends LightningElement {

     constructor(){
        super();
        console.log('Constructor called');
    } 
     connectedCallback(){
        console.log('Connected Callback called');
    }

    renderedCallback(){
        console.log('Call rec. From Rendered Callback');
        
    }
}