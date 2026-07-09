public class UpdateTotalNumberOfContact {

    public static void updateContactCounts(List<Contact> contactList, Map<Id, Contact> oldContactMap){
        Set<Id> accountIds = new Set<Id>();
        
        // Account Ids ikattha karo
        for(Contact con : contactList){
            if(Trigger.isInsert && con.AccountId != null){
                accountIds.add(con.AccountId);
            }
            if(oldContactMap != null && oldContactMap.get(con.Id).AccountId != con.AccountId ) {
                
                if(con.AccountId != null){
                    accountIds.add(con.AccountId);
                }
                accountIds.add(oldContactMap.get(con.Id).AccountId);
            }
        }

        if(accountIds.isEmpty()) return;

        Map<Id, Integer> accIdToContactCount = new Map<Id, Integer>();
        
        for(AggregateResult ar : [
            SELECT AccountId accId, COUNT(Id) contactCount
            FROM Contact
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ]){
            accIdToContactCount.put((Id)ar.get('accId'), (Integer)ar.get('contactCount'));
        }

        List<Account> accountsToUpdate = new List<Account>();
        for(Id accId : accIdToContactCount.keySet()){
            accountsToUpdate.add(new Account(
                Id = accId,
                Total_Contacts__c = accIdToContactCount.get(accId)
            ));
        }

        if(!accountsToUpdate.isEmpty()){
            update accountsToUpdate;
        }
    }
}