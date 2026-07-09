public class API_Logger {

    public static void log(String apiName, String request, String response){
        System.debug('API: ' + apiName);
        System.debug('REQ: ' + request);
        System.debug('RES: ' + response);
    }
}