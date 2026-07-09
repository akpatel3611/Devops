public class AccountNameUpdator {
    public static void UpdateAccountNames(List<Account> accList){
        for(Account acc : accList){
        	if(acc.name !=null && acc.Name == 'Old Name'){
            acc.Name = 'first chatgpt';
            System.debug('after account update : '+ acc.Name);
        }
    
    }
  }
}