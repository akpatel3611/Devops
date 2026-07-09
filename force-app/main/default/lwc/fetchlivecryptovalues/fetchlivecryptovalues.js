import { LightningElement, track } from 'lwc';

export default class FetchLiveCryptoValues extends LightningElement {
    @track btcPrice;
    @track ethPrice;

    connectedCallback() {
        this.fetchPrices();
    }

    handleRefresh() {
        this.fetchPrices();
    }

    async fetchPrices() {
        try {
            // ✅ API call
            const response = await fetch(
                'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=inr'
            );

            // ✅ Check HTTP status
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }

            // ✅ Parse JSON
            const data = await response.json();

            // ✅ Validate data
            if (data.bitcoin?.inr && data.ethereum?.inr) {
                this.btcPrice = `₹${data.bitcoin.inr}`;
                this.ethPrice = `₹${data.ethereum.inr}`;
            } else {
                throw new Error('Invalid data structure');
            }
        } catch (error) {
            console.error('Error fetching prices:', error);
            this.btcPrice = '₹Error';
            this.ethPrice = '₹Error';
        }
    }
}