import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPromotionDetails from '@salesforce/apex/PromotionPageController.getPromotionDetails';

export default class PromotionPage extends NavigationMixin(LightningElement) {
    @api recordId;

    @track promoDetails = {};

    @wire(getPromotionDetails, { promotionId: '$recordId' })
    wiredDetails({ data, error }) {
        if (data) {
            this.promoDetails = data;
            console.log('PromotionPage wiredDetails loaded:', JSON.stringify(data));
        } else if (error) {
            console.error('PromotionPage Error fetching promotion details:', error);
        }
    }

    // ─── Pipeline path steps ─────────────────────────────────
    get pathSteps() {
        const src = this.promoDetails && this.promoDetails.sourceEnvironmentName
            ? this.promoDetails.sourceEnvironmentName
            : '';
        const tgt = this.promoDetails && this.promoDetails.targetEnvironmentName
            ? this.promoDetails.targetEnvironmentName
            : '';
        const status = this.promoDetails && this.promoDetails.status
            ? this.promoDetails.status
            : 'Draft';

        if (!src && !tgt) {
            return [];
        }

        return [
            {
                name: src,
                isComplete: status === 'Completed',
                className: status === 'Completed'
                    ? 'slds-path__item slds-is-complete'
                    : 'slds-path__item slds-is-current slds-is-active promo-path-source'
            },
            {
                name: tgt,
                isComplete: false,
                className: status === 'Completed'
                    ? 'slds-path__item slds-is-current slds-is-active'
                    : 'slds-path__item slds-is-incomplete promo-path-target'
            }
        ];
    }

    // ─── Navigation helpers ───────────────────────────────────
    handleNavProject() {
        if (this.promoDetails && this.promoDetails.projectId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.promoDetails.projectId, actionName: 'view' }
            });
        }
    }

    handleNavRelease() {
        if (this.promoDetails && this.promoDetails.releaseId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.promoDetails.releaseId, actionName: 'view' }
            });
        }
    }
}