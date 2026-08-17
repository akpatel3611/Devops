public with sharing class AsyncOperationController {

    @AuraEnabled(cacheable=false)
    public static List<Async_Operation_Log__c> getRecentOperations(Id recordId) {
        System.debug(LoggingLevel.INFO, '[AsyncOperationController.getRecentOperations] START - recordId: ' + recordId);
        if (recordId == null) {
            System.debug(LoggingLevel.WARN, '[AsyncOperationController.getRecentOperations] Warning: recordId is null.');
            return new List<Async_Operation_Log__c>();
        }

        try {
            List<Async_Operation_Log__c> logs = [
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
            System.debug(LoggingLevel.INFO, '[AsyncOperationController.getRecentOperations] SUCCESS - Loaded ' + logs.size() + ' recent async operation logs.');
            return logs;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[AsyncOperationController.getRecentOperations] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to load recent operations: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getTotalOperations(Id recordId) {
        System.debug(LoggingLevel.INFO, '[AsyncOperationController.getTotalOperations] START - recordId: ' + recordId);
        try {
            Integer countVal = [
                SELECT COUNT()
                FROM Async_Operation_Log__c
                WHERE Record_Id__c = :recordId
            ];
            System.debug(LoggingLevel.INFO, '[AsyncOperationController.getTotalOperations] Total operations count: ' + countVal);
            return countVal;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[AsyncOperationController.getTotalOperations] Exception: ' + ex.getMessage());
            return 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getFailedOperations(Id recordId) {
        System.debug(LoggingLevel.INFO, '[AsyncOperationController.getFailedOperations] START - recordId: ' + recordId);
        try {
            Integer countVal = [
                SELECT COUNT()
                FROM Async_Operation_Log__c
                WHERE Record_Id__c = :recordId
                AND Status__c = 'FAILED'
            ];
            System.debug(LoggingLevel.INFO, '[AsyncOperationController.getFailedOperations] Failed operations count: ' + countVal);
            return countVal;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[AsyncOperationController.getFailedOperations] Exception: ' + ex.getMessage());
            return 0;
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getAsyncJobStatus(String jobId) {
        System.debug(LoggingLevel.INFO, '[AsyncOperationController.getAsyncJobStatus] START - jobId: ' + jobId);
        if (String.isBlank(jobId)) {
            System.debug(LoggingLevel.WARN, '[AsyncOperationController.getAsyncJobStatus] Warning: jobId is blank.');
            return 'UNKNOWN';
        }

        try {
            List<AsyncApexJob> jobs = [
                SELECT Id, Status
                FROM AsyncApexJob
                WHERE Id = :jobId
                LIMIT 1
            ];

            if (jobs.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[AsyncOperationController.getAsyncJobStatus] Warning: No AsyncApexJob found for ID: ' + jobId);
                return 'UNKNOWN';
            }

            System.debug(LoggingLevel.INFO, '[AsyncOperationController.getAsyncJobStatus] Job status: ' + jobs[0].Status);
            return jobs[0].Status;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[AsyncOperationController.getAsyncJobStatus] Exception: ' + ex.getMessage());
            return 'UNKNOWN';
        }
    }
}