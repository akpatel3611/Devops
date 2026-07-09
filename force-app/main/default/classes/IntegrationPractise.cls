public class IntegrationPractise {
    public static void MakeCallout() {
        
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.unsplash.com/photos?query=mountain?apiKey=d4c3b2a1908f7e6d5c4b3a2f1e0d9c8b');
        req.setMethod('GET');
        HttpResponse res = http.send(req);
        System.debug('this is status code '+res.getStatusCode());
        if(res.getStatusCode() == 200){
            System.debug('data fetch successfully'+ res.getBody());
        }        
    }
}