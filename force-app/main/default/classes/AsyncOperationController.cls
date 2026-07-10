public with sharing class AsyncOperationController {

    @AuraEnabled(cacheable=false)
    public static List<Async_Operation_Log__c> getRecentOperations(Id recordId) {
        System.debug('Fetching recent operations for recordId: ' + recordId);
        System.debug('Testing deployment flow');

        return [
            SELECT
                Id,
                Name,
                Record_Id__c,
                Record_Name__c,
                Status__c,
                BRR_Name__c,
                Operation_Name__c,
                Message__c,
                Progress__c,
                Job_Id__c,
                CreatedDate
            FROM Async_Operation_Log__c
            WHERE Record_Id__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=false)
    public static Integer getTotalOperations(Id recordId) {

        return [
            SELECT COUNT()
            FROM Async_Operation_Log__c
            WHERE Record_Id__c = :recordId
        ];
    }

    @AuraEnabled(cacheable=false)
    public static Integer getFailedOperations(Id recordId) {

        return [
            SELECT COUNT()
            FROM Async_Operation_Log__c
            WHERE Record_Id__c = :recordId
            AND Status__c = 'FAILED'
        ];
    }

    @AuraEnabled(cacheable=false)
    public static String getAsyncJobStatus( String jobId) {
        List<AsyncApexJob> jobs = [

            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        if (jobs.isEmpty()) {
            return 'UNKNOWN';
        }
        return jobs[0].Status;
    }
}