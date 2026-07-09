@isTest
public class AccountCalculatorTest {
@isTest
    private static void countContactTest(){
     List<Account> accList = new List<Account>();
         
        for(Integer i=0 ; i<250 ; i++){
            accList.add(New Account (Name='Test'+i));
        }
        insert accList;
        
        List<Contact> conList = new List<Contact>();
        List<Id> accIds = new List<Id>();
        for(Account acc: accList){
            conList.add(new Contact(FirstName='Test', LastName=acc.Name, AccountId=acc.Id));
            accIds.add(acc.Id);
        }
        insert conList;
        
        Test.startTest();
        AccountCalculator.countContact(accIds);
        Test.stopTest();
        
        List<Account> accs = [SELECT Id,Number_Of_Contacts__c FROM Account];
        System.assertEquals(1, accs[0].Number_Of_Contacts__c, 'Contacts are not counted successfully');   
    } 
}