public class API_BaseHandler {

    public static Map<String, Object> parseRequest(){
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.request.requestBody.toString()
        );
    }

    public static void sendResponse(Object data){
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(data));
    }

    public static void sendError(String msg){
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(msg);
    }
}