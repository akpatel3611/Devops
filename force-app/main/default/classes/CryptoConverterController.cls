public with sharing class CryptoConverterController {
    @AuraEnabled(cacheable=false)
    public static String convertCurrency(String fiatCurrency, String cryptoCurrency, Decimal amount, Boolean isFiatToCrypto) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();

            // API Call
            String url = 'https://api.coingecko.com/api/v3/simple/price?ids=' 
                        + cryptoCurrency.toLowerCase() 
                        + '&vs_currencies=' + fiatCurrency.toLowerCase();

            req.setEndpoint(url);
            req.setMethod('GET');
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                if (resultMap.containsKey(cryptoCurrency.toLowerCase())) {
                    Map<String, Object> innerMap = (Map<String, Object>) resultMap.get(cryptoCurrency.toLowerCase());

                    Decimal conversionRate = (Decimal) innerMap.get(fiatCurrency.toLowerCase());
                    Decimal finalValue;

                    // Switch case style logic
                    if (isFiatToCrypto) {
                        finalValue = amount / conversionRate; // Fiat → Crypto
                    } else {
                        finalValue = amount * conversionRate; // Crypto → Fiat
                    }

                    return String.valueOf(finalValue.setScale(6)); // Rounded
                }
            }
            return 'Conversion Failed';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
}