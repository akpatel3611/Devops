public class AccountCalculator {
    @future
    public static void countContact(List<Id> accIds){
        List<Account> accList = [SELECT Id, (SELECT Id FROM Contacts) FROM Account WHERE Id IN: accIds];
        for(Account acc: accList){
            acc.Number_Of_Contacts__c = acc.Contacts.size();
        }
        if(!accList.isEmpty()){
            System.debug('before account update : '+ accList);
            update accList;
        }
    }
}