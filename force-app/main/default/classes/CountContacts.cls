public class CountContacts {
    @future
    public static void countContact(){
        List <Account> mycon =[SELECT Id, Name FROM Account];
        System.debug('Contact List ='+ mycon.size());
        
        for(Account con: mycon){
            String fname = (con.Name != null ? con.Name+ '': '');
            System.debug( 'Id'+ con.Id +'CName ='+ con.Name);
        }
    }
}