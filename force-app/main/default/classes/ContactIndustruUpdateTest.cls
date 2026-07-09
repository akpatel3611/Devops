@isTest
public class ContactIndustruUpdateTest {
 @isTest
    public static void ContactInsertAndUpdateInIndustry(){
        
        Account acc= new Account(Name = 'Test2', Industry ='Technology');
        insert acc;
        
        Contact con = new Contact(LastName='Test Con', AccountId= acc.Id);
        insert con;
        
        con =[SELECT Id, Industry__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals(acc.Industry, con.Industry__c , 'industry__c should match after insert');
        
        acc.Industry = 'Finance';
        update acc;
        
        con.LastName = 'Update Contact';
        update con;
        
        con = [SELECT Id, Industry__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Finance', con.Industry__c ,'industry__c should match after insert');
        
    }
}