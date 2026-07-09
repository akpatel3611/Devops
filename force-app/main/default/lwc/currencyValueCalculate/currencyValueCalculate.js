import { LightningElement, track } from 'lwc';
import convertCurrency from '@salesforce/apex/CryptoConverterController.convertCurrency';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CurrencyValueCalculate extends LightningElement {
    @track fromCurrency = '';
    @track toCurrency = '';
    @track amount = '';
    @track conversionResult;
    @track conversionDateTime;
    @track isLoading = false;
    @track isButtonDisabled = true;

    // Options
    cryptoOptions = [
        { label: 'Bitcoin (BTC)', value: 'bitcoin' },
        { label: 'Ethereum (ETH)', value: 'ethereum' }
    ];

    fiatOptions = [
        { label: 'USD', value: 'usd' },
        { label: 'INR', value: 'inr' },
        { label: 'EUR', value: 'eur' }
    ];

    // Dynamic Options
    get fromOptions() {
        return [...this.cryptoOptions, ...this.fiatOptions];
    }

    get toOptions() {
        if (!this.fromCurrency) return [];
        return this.isFiat(this.fromCurrency) ? this.cryptoOptions : this.fiatOptions;
    }

    // Check Fiat
    isFiat(currency) {
        return ['usd', 'inr', 'eur'].includes(currency);
    }

    // Handlers
    handleFromChange(e) {
        this.fromCurrency = e.detail.value;
        this.toCurrency = '';
        this.enableButton();
    }

    handleToChange(e) {
        this.toCurrency = e.detail.value;
        this.enableButton();
    }

    handleAmountChange(e) {
        this.amount = e.detail.value;
        this.enableButton();
    }

    handleSwap() {
        [this.fromCurrency, this.toCurrency] = [this.toCurrency, this.fromCurrency];
        this.enableButton();
    }

    handleConvert() {
        this.fetchConversion();
    }

    handleRefresh() {
        this.fetchConversion(true);
    }

    // Conversion Call
    fetchConversion(isRefresh = false) {
        this.isLoading = true;
        this.isButtonDisabled = true;

        const isFiatToCrypto = this.isFiat(this.fromCurrency);

        convertCurrency({
            fiatCurrency: isFiatToCrypto ? this.fromCurrency : this.toCurrency,
            cryptoCurrency: isFiatToCrypto ? this.toCurrency : this.fromCurrency,
            amount: this.amount,
            isFiatToCrypto
        })
        .then(result => {
            this.conversionResult = `${this.amount} ${this.fromCurrency.toUpperCase()} = ${result} ${this.toCurrency.toUpperCase()}`;
            this.conversionDateTime = new Date().toLocaleString();

            this.showToast('Success', isRefresh ? 'Price refreshed!' : 'Conversion successful!', 'success');
        })
        .catch(error => {
            this.conversionResult = null;
            this.showToast('Error', error.body?.message || 'Conversion failed', 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    enableButton() {
        this.isButtonDisabled = !(this.fromCurrency && this.toCurrency && this.amount > 0);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}