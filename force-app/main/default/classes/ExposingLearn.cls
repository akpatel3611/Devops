@RestResource(urlMapping='/getDataFromOurSystem/*')
global class ExposingLearn {
    
    @HttpGet
    global static List<Contact> getContactData() {
        RestRequest req;
        if (RestContext.request == null) {
            req = new RestRequest();
            req.params.put('sfId', '003WU00000Np03zYAB');
            req.params.put('email', 'rose@edge.com');
            RestContext.request = req;
        } else {
            req = RestContext.request;
        }

        Map<String, String> mapOfData = req.params;
        String myRecId = mapOfData.get('sfId');
        String Email = mapOfData.get('email');
        System.debug('Check Passed Id: ' + myRecId);
        System.debug('Check Passed Email: ' + Email);
        
        List<Contact> conList = [SELECT Id, Name FROM Contact WHERE Id=: myRecId AND email=: Email];
        return conList;
    }
}