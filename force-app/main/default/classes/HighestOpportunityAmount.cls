public class HighestOpportunityAmount {

    public static void updateHighestOpportunityAmounts(List<Opportunity> oppList) {
        
        Set<Id> accountIds = new Set<Id>();

        for (Opportunity opp : oppList) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }

        if (accountIds.isEmpty()) return;

        // Step 2: Get highest opportunity amount per account using AggregateResult
        List<AggregateResult> grprslt = [
            SELECT AccountId, MAX(Amount) maxAmount
            FROM Opportunity
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ];

        Map<Id, Decimal> accToMaxAmt = new Map<Id, Decimal>();
        for (AggregateResult ar : grprslt) {
            accToMaxAmt.put((Id) ar.get('AccountId'), (Decimal) ar.get('maxAmount'));
        }

        List<Account> acctsToUpdate = new List<Account>();
        for (Id accId : accToMaxAmt.keySet()) {
            acctsToUpdate.add(new Account(
                Id = accId,
                Highest_Opportunity_Amount__c = accToMaxAmt.get(accId)
            ));
        }

        if (!acctsToUpdate.isEmpty()) {
            update acctsToUpdate;
        }
    }
}