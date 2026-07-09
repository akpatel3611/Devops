@isTest
public class UpdateContactMailingAddressTest {
  @isTest
    public static void testAddressCopy(){
        List<Account> accList = new  List<Account>();
        List<Contact> conList = new List<Contact>();
        
        for(Integer i=1; i<5;i++){
            Account acc = new Account (Name = 'Test'+i, billingcity = 'New York' , billingcountry = 'USA');
            accList.add(acc);
        }
        insert accList;
        
        for(Account acc: accList){
            Contact con = new Contact();
            con.LastName = 'test';
            con.AccountId = acc.Id;
  			conList.add(con);
        }
        insert conList;
        
        Test.startTest();
        UpdateContactMailingAddress accProceess = new UpdateContactMailingAddress();
        Id batchId = Database.executeBatch(accProceess);
        Test.stopTest();
        
       Integer countedContact = [SELECT count() FROM Contact WHERE MailingCity = 'New York'];
       System.assertEquals(4,countedContact);
    }
}