public class AsyncProcessor implements Queueable {

    String type;
    Id recordId;

    public AsyncProcessor(String type, Id recordId){
        this.type = type;
        this.recordId = recordId;
    }

    public void execute(QueueableContext ctx){

        if(type == 'MIP'){
            // send email / generate PDF
        }
        else if(type == 'OTP'){
            // send OTP
        }
        else if(type == 'PAYMENT'){
            // update payment
        }
    }
}