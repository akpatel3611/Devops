import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class RecordGraphLauncher extends NavigationMixin(LightningElement) {

    @api recordId;
    @api objectApiName;

    openGraph() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Record_Graph_Explorer'
            },
            state: {
                c__recordId: this.recordId,
                c__objectApiName: this.objectApiName
            }
        });
    }
}