@isTest
public class ContactTriggerHandlerTest {
    @isTest
    static void testIndustryUpdateFromAccount() {
        Account acc = new Account(Name = 'Test Account', Industry = 'Technology');
        insert acc;

        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc.Id);
        insert con;

        con.AccountId = acc.Id;
        update con;

        con = [SELECT Industry__c FROM Contact WHERE Id = :con.Id];
        System.assertEquals('Technology', con.Industry__c);
    }
}