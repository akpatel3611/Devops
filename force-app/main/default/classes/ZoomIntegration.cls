public class ZoomIntegration {
    
    public static void populateWrapper(){
        ZoomIntegration.WrapperMeeting wrap =new ZoomIntegration.WrapperMeeting();
        wrap.topicofMeeting = 'for youtube video';
        wrap.typeofMeeting =2;
        wrap.StartTime = '2024-06-16T16:30:04z';
        wrap.timeZone = 'Asia/Kolkata';
        String jsonString = JSON.serialize(wrap);
        createMeeting(jsonString);
    }

    public static void createMeeting(String jsonBody){
        Http http = new Http();
		HttpRequest req= new HttpRequest();
        req.setBody(jsonBody);
        req.setMethod('POST');
        req.setEndpoint('callout:Zoom_Integration_Learning/v2/users/me/meetings');
        req.setHeader('Content-type','application/json');
        HttpResponse res= http.send(req);
        System.debug('response code' + res.getStatusCode());
        if(res.getStatusCode()== 201){
            System.debug('Success');
        }
        else
        {
            System.debug('failure');
        }
    }
    public class WrapperMeeting{
        public String topicofMeeting{get;set;}
        public Integer typeofMeeting{get;set;}
        public String StartTime{get;set;}
        public Integer durationMeeting{get;set;}
        public String timeZone{get;set;}
    }
}