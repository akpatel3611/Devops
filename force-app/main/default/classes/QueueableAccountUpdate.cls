public class QueueableAccountUpdate implements queueable{
    public void execute(QueueableContext context){
        List<Account> accs = [SELECT Id , Name FROM Account];
        for(Account acc : accs){
            acc.Name = acc.Name + 'update'; 
        }
    		update accs;        
    } 
    
}