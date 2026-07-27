@isTest
public class ContactControllerTest {

    @isTest
    static void testSaveContacts() {

        List<Contact> conList = new List<Contact>();

        Contact con = new Contact(
            FirstName='Ankit',
            LastName='Patel',
            Email='ankit@test.com',
            Phone='9999999999'
        );

        conList.add(con);

        Test.startTest();

        List<Contact> result =
            ContactController.saveContacts(conList);

        Test.stopTest();

        System.assertEquals(
            1,
            result.size()
        );

        System.assertEquals(
            'Ankit',
            result[0].FirstName
        );
    }


    @isTest
    static void testSearchContacts() {

        Contact con = new Contact(
            FirstName='Demo',
            LastName='User',
            Email='demo@test.com'
        );

        insert con;

        Test.startTest();

        List<Contact> result =
            ContactController.searchContacts('Demo');

        Test.stopTest();

        System.assert(
            result.size()>0
        );
    }


    @isTest
    static void testGetContactDetails() {

        Contact con = new Contact(
            FirstName='John',
            LastName='Smith',
            Email='john@test.com'
        );

        insert con;

        Test.startTest();

        Contact result =
            ContactController.getContactDetails(con.Id);

        Test.stopTest();

        System.assertEquals(
            con.Id,
            result.Id
        );
    }
}