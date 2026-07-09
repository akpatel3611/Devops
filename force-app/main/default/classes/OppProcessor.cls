public class OppProcessor implements Database.Batchable<sObject>, Database.stateful {
    public Integer recordCount = 0;
    
    public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getqueryLocator([SELECT Id,Name FROM Opportunity]);
    }
    public void execute(Database.BatchableContext bc, List<Opportunity> opps){
        for(Opportunity oop: opps){
            oop.LeadSource = 'web';
        } 
        
        update opps;
        recordCount = recordCount+opps.size();
    }
    public void finish(Database.BatchableContext bc){
        System.debug('Total records Processed'+ recordCount);
    }
}