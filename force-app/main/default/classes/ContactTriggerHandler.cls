public class ContactTriggerHandler {

    public static void updateIndustry(List<Contact> contactList) {
        Set<Id> accIds = new Set<Id>();

        for (Contact con : contactList) {
            if (con.AccountId != null) {
                accIds.add(con.AccountId);
            }
        }

        if (accIds.isEmpty()) return;

        Map<Id, Account> accMap = new Map<Id, Account>(
            [SELECT Id, Industry FROM Account WHERE Id IN :accIds]
        );

        List<Contact> contactsToUpdate = new List<Contact>();

        for (Contact con : contactList) {
            if (con.AccountId != null && accMap.containsKey(con.AccountId)) {
                Account acc = accMap.get(con.AccountId);
                if (con.Industry__c != acc.Industry) {
                    Contact updatedCon = new Contact(Id = con.Id);
                    updatedCon.Industry__c = acc.Industry;
                    contactsToUpdate.add(updatedCon);
                }
            }
        }

        if (!contactsToUpdate.isEmpty()) {
            try {
                update contactsToUpdate;
            } catch (exception e) {
                System.debug('Error handling' + e.getMessage());
            }
        }
    }
}