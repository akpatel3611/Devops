public class ContactAndLeadSearch 
{
    public static List<List<sObject>> searchContactsAndLeads(String name)
    {
        // SOSL to search Contacts and Leads where FirstName or LastName matches
        List<List<sObject>> searchResults = [FIND :name IN NAME FIELDS 
                                             RETURNING Contact(FirstName, LastName), 
                                                       Lead(FirstName, LastName)];
        return searchResults;
    }
}