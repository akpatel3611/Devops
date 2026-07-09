public class FutureDemo { 
@future 
    public static void sendEmail(String emailId){
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new String[] {emailId});
        msg.setSubject('welcom');
        msg.setPlainTextBody('thanks for signign up');
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] {msg});
    }
}