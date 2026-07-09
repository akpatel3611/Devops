public class CommonUtil {

    public static Map<String,Object> getRequest(){
        return (Map<String,Object>)JSON.deserializeUntyped(
            RestContext.request.requestBody.toString()
        );
    }

    public static void sendResponse(Object res){
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(res));
    }
}