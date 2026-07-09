public class UpdateContactMailingAddress implements Database.Batchable<sObject>, Database.Stateful {

    public Integer recordCount = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, BillingStreet, BillingCity, BillingState, ShippingPostalCode, ' +
            '(SELECT Id, MailingStreet, MailingCity, MailingState, MailingPostalCode FROM Contacts)'+
            'FROM Account WHERE BillingCountry = \'USA\''
        );
    }

    public void execute(Database.BatchableContext bc, List<Account> accList) {
        List<Contact> conList = new List<Contact>();

        for (Account acc : accList) {
            if (acc.Contacts != null) {
                for (Contact con : acc.Contacts) {
                    con.MailingStreet = acc.BillingStreet;
                    con.MailingCity = acc.BillingCity;
                    con.MailingPostalCode = acc.ShippingPostalCode;
                    con.MailingState = acc.BillingState;
                    conList.add(con);
                    recordCount++;
                }
            }
        }

        if (!conList.isEmpty()) {
            update conList;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Record Count = ' + recordCount);
    }
}