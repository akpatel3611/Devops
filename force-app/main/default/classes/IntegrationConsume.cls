public class IntegrationConsume {
  
    public static void callout(){
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:SF_Named_Credentials/services/apexrest/DataAvailble');
        HttpResponse res= http.send(req);
    	System.debug('the status code is :'+res.getStatusCode());
        if(res.getStatusCode() ==200){
            System.debug('success');
        }
    }
}