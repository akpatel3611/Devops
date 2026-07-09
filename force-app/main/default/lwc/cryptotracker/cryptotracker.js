import { LightningElement, track } from 'lwc';
import getCryptoPrices from '@salesforce/apex/apicontroller.getCryptoPrices';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CryptoTracker extends LightningElement {
    @track btcPrice;
    @track ethPrice;
    @track lastUpdated;
    @track isLoading = false;
    @track options;
    @track selectedCrypto;
    @track selectedCurrency;
    @track options1;


    connectedCallback() {
        this.fetchPrices(); // Page load pe hi data fetch karo
    }

    async fetchPrices() {
        this.isLoading = true;
        try {
            const result = await getCryptoPrices();
            this.btcPrice = result.btcPrice; // ✅ Correct field from Apex
            this.ethPrice = result.ethPrice; // ✅ Correct field from Apex
            this.lastUpdated = new Date().toLocaleString(); // Local time stamp
        } catch (error) {
            this.showToast('Error', 'Unable to fetch prices', 'error');
            console.error('API Error:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.fetchPrices(); // Button click pe bhi same fetch logic
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
            })
        );
    }   
}