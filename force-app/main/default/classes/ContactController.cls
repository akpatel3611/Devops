public with sharing class ContactController {

    @AuraEnabled
    public static List<Contact> saveContacts(List<Contact> contactsToInsert) {
        if (contactsToInsert == null || contactsToInsert.isEmpty()) {
            return new List<Contact>();
        }

        upsert contactsToInsert;

        Set<Id> ids = new Set<Id>();

        for (Contact c : contactsToInsert) {
            if (c.Id != null) {
                ids.add(c.Id);
            }
        }

        return [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Contact
            WHERE Id IN :ids
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> searchContacts(String searchKey) {

        if(String.isBlank(searchKey)){
            return new List<Contact>();
        }

        return [
            SELECT Id,
                   FirstName,
                   LastName,
                   Email,
                   Phone
            FROM Contact
            WHERE Name LIKE :('%' + searchKey + '%')
            LIMIT 10
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Contact getContactDetails(Id contactId){

        if(contactId == null){
            return null;
        }

        return [
            SELECT Id,
                   FirstName,
                   LastName,
                   Email,
                   Phone
            FROM Contact
            WHERE Id=:contactId
            LIMIT 1
        ];
    }
}