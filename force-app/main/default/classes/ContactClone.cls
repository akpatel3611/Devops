public class ContactClone implements Queueable {
  private Contact con;
  private String industryValue;
    
    public ContactClone(Contact con, String industryValue){
        this.con = con;
        this.industryValue = industryValue;
    }
    public void execute(QueueableContext context){
        List<Account> accList = [SELECT Id, Name FROM Account WHERE industry =: industryValue LIMIT 200];
        
        List<Contact> conList = new List<Contact>();
        for(Account acc : accList){
            Contact c = con.clone(false, false, false, false);
            c.AccountId = acc.Id;
            conList.add(c);
        }
        if(!conList.isEmpty()){
            insert conList;
        }
    }
}