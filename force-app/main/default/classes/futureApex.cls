public class futureApex {
    
  @future(callout=true)
    public static void futureCall(List<Id> accId){
        if(accId.size()>0){
            for(Account acc :[Select Id , Name , Phone from Account where ID IN: accId]){
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint('callout:SF_Named_Credentials/services/apexrest/DataAvailable?phonNo='+ acc.Phone);
                HttpResponse res= http.send(req);
                System.debug('status code :'+ res.getStatusCode());
                if(res.getStatusCode() == 200){
                    System.debug('Succces'+ res.getBody());
                }     
            }
        }  
    }
}