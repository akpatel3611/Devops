public with sharing class apicontroller {

    public class CryptoPrice {
        @AuraEnabled public Decimal btcPrice;
        @AuraEnabled public Decimal ethPrice;
    }

    @AuraEnabled(cacheable=false)
    public static CryptoPrice getCryptoPrices() {
        Http http = new Http();
        HttpRequest req = new HttpRequest();

        // CoinGecko API - No API key required
        req.setEndpoint('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=inr');
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            Map<String, Object> btcMap = (Map<String, Object>) result.get('bitcoin');
            Map<String, Object> ethMap = (Map<String, Object>) result.get('ethereum');

            CryptoPrice cp = new CryptoPrice();
            cp.btcPrice = (Decimal) btcMap.get('inr');
            cp.ethPrice = (Decimal) ethMap.get('inr');

            return cp;
        } else {
            throw new AuraHandledException('API call failed with status: ' + res.getStatus());
        }
    }
}