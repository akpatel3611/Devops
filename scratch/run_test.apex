String owner = 'akpatel3611';
String repo = 'Devops';
String prNumber = '3';
String endpoint = 'https://api.github.com/repos/' + owner + '/' + repo + '/pulls/' + prNumber;

Credentials__c cred = [SELECT Access_Token__c FROM Credentials__c LIMIT 1];
String token = cred.Access_Token__c;

Http http = new Http();
HttpRequest req = new HttpRequest();
req.setEndpoint(endpoint);
req.setMethod('GET');
req.setHeader('Accept', 'application/vnd.github+json');
req.setHeader('User-Agent', 'Salesforce-Release-Management');
req.setHeader('Authorization', 'Bearer ' + token);

HttpResponse response = http.send(req);
System.debug('STATUS CODE: ' + response.getStatusCode());
if (response.getStatusCode() == 200) {
    Map<String, Object> prMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    System.debug('MERGED: ' + prMap.get('merged'));
    System.debug('STATE: ' + prMap.get('state'));
} else {
    System.debug('ERROR: ' + response.getStatus());
}
