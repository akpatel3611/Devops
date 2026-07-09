public with sharing class OpportunityKanbanController {
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getLatestOpportunities() {
        return [
            SELECT Id, Name, Amount, StageName
            FROM Opportunity
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }

    @AuraEnabled
    public static void updateStage(Id oppId, String newStage) {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Id = :oppId LIMIT 1];
        opp.StageName = newStage;
        update opp;
    }
}