public class CalculatecaseOrigin {
 @future
    public static void countCasesBasedOrigin(List<Id> accIds){
	    List <Account> accList = [SELECT Id, Cases_through_Email__c ,Cases_through_Phone__c, Cases_through_Web__c,
                                 (SELECT Id, Origin FROM Cases) FROM Account WHERE Id IN: accIds];
        
        
        for(Account acc : accList){
            Integer Email=0, Phone=0, Web =0;
            
            for(Case ca : acc.Cases){
                if(ca.Origin == 'Phone'){
                    Phone++;
                }else if(ca.Origin == 'Email'){
                    Email++;
                }else if(ca.Origin == 'Web'){
                    Web++;
                }
            }
            acc.Cases_through_Email__c = Email;
            acc.Cases_through_Web__c = Web;
            acc.Cases_through_Phone__c = Phone;
        }
        if(!accList.isEmpty()){
            update accList;
        }
    }
}