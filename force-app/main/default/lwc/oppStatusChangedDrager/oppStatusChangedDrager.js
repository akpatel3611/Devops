import { LightningElement, wire, track } from 'lwc';
import getLatestOpportunities from '@salesforce/apex/OpportunityKanbanController.getLatestOpportunities';
import updateStage from '@salesforce/apex/OpportunityKanbanController.updateStage';
import { refreshApex } from '@salesforce/apex';

export default class OppStatusChangeDrager extends LightningElement {
    @track opportunities = [];
    wiredResult;

    stages = [
        { name: 'All', label: 'Opportunity Records' },
        { name: 'Prospecting', label: 'Prospecting' },
        { name: 'Qualification', label: 'Qualification' },
        { name: 'Proposal/Price Quote', label: 'Proposal/Price Quote' },
        { name: 'Closed Won', label: 'Closed Won' }
    ];

    @wire(getLatestOpportunities)
    wiredOpps(result) {
        this.wiredResult = result;
        if (result.data) {
            // Filter: only records with Amount + StageName
            this.opportunities = result.data.filter(
                r => r.Amount !== null && r.StageName
            );
        }
    }

    get columns() {
        return this.stages.map(stage => {
            let records = [];
            if (stage.name === 'All') {
                records = this.opportunities;
            } else {
                records = this.opportunities.filter(r => r.StageName === stage.name);
            }
            return { ...stage, records };
        });
    }

    // Drag & Drop
    handleDrag(event) {
        event.dataTransfer.setData('oppId', event.target.dataset.id);
    }

    allowDrop(event) {
        event.preventDefault();
    }

    async handleDrop(event) {
        event.preventDefault();
        const oppId = event.dataTransfer.getData('oppId');
        const newStage = event.currentTarget.dataset.stage;

        if (newStage !== 'All') {
            await updateStage({ oppId, newStage });
            refreshApex(this.wiredResult);
        }
    }
}