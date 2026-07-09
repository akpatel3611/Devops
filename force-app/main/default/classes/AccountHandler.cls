public class AccountHandler {
    public static Account insertNewAccount(String accName) {
        Account acc = new Account(Name = accName);
        try {
            insert acc;
            return acc;
        } catch (DmlException e) {
            return null;
        }
    }
}