public with sharing class contactformcontroller {

    // Search contacts by Name, Email, Phone
    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchKey) {
        return [
            SELECT Id, Name, Email, Phone 
            FROM Contact 
            WHERE Name LIKE :('%' + searchKey + '%')
            OR Email LIKE :('%' + searchKey + '%')
            OR Phone LIKE :('%' + searchKey + '%')
            LIMIT 50
        ];
    }

    // Link contacts to Opportunity by updating lookup field
    @AuraEnabled
    public static void linkContactsToOpportunity(Id opportunityId, List<Id> contactIds) {
        // NOTE: make sure your lookup field API name is correct
        List<Contact> contactsToUpdate = [SELECT Id, Opportunity__c FROM Contact WHERE Id IN :contactIds];
        for (Contact c : contactsToUpdate) {
            c.Opportunity__c = opportunityId;
        }
        update contactsToUpdate;
    }
}