public with sharing class AsyncProcessService {

    public static void processAsyncOperation(
        Id recordId,
        Id jobId,
        String resourceType,
        String operationName
    ) {
        System.debug(LoggingLevel.INFO, '[AsyncProcessService.processAsyncOperation] START - recordId: ' + recordId + ' | jobId: ' + jobId + ' | resourceType: ' + resourceType + ' | operationName: ' + operationName);
        if (recordId == null || jobId == null) {
            System.debug(LoggingLevel.WARN, '[AsyncProcessService.processAsyncOperation] Warning: recordId or jobId is null.');
            return;
        }

        try {
            // fetch object api name
            String objectApiName = recordId.getSObjectType().getDescribe().getName();
            System.debug(LoggingLevel.DEBUG, '[AsyncProcessService.processAsyncOperation] SObjectType resolved: ' + objectApiName);

            // fetch async job details for progress tracking
            AsyncApexJob asyncJob = [
                SELECT
                    Id,
                    Status,
                    JobType,
                    TotalJobItems,
                    JobItemsProcessed,
                    NumberOfErrors
                FROM AsyncApexJob
                WHERE Id = :jobId
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, '[AsyncProcessService.processAsyncOperation] AsyncApexJob Status: ' + asyncJob.Status + ' | Processed: ' + asyncJob.JobItemsProcessed + '/' + asyncJob.TotalJobItems);

            // start event
            AsyncEventManager.publishProgressEvent(
                recordId,
                jobId,
                10,
                'Initializing Background Process',
                resourceType,
                operationName
            );
            
            // dynamic record fetching
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectApiName) + ' WHERE Id = :recordId';
            List<SObject> recordList = Database.query(query);
            System.debug(LoggingLevel.FINE, '[AsyncProcessService.processAsyncOperation] Queried record list size: ' + recordList.size());
                
            // validation logic
            AsyncEventManager.publishProgressEvent(
                recordId,
                jobId,
                30,
                'Validating Record Data',
                resourceType,
                operationName
            );

            if (asyncJob.Status == 'Processing') {
                AsyncEventManager.publishProgressEvent(
                    recordId,
                    jobId,
                    60,
                    'Background Processing Running',
                    resourceType,
                    operationName
                );
            }

            Integer processedCount = asyncJob.JobItemsProcessed;
            Integer totalCount = asyncJob.TotalJobItems;
            Integer calculatedProgress = 80;

            if (totalCount > 0) {
                calculatedProgress = Integer.valueOf((Decimal.valueOf(processedCount) / Decimal.valueOf(totalCount)) * 100);
            }

            System.debug(LoggingLevel.FINE, '[AsyncProcessService.processAsyncOperation] Calculated progress: ' + calculatedProgress + '%');

            AsyncEventManager.publishProgressEvent(
                recordId,
                jobId,
                calculatedProgress,
                'Processing Background Operations',
                resourceType,
                operationName
            );

            // success event
            AsyncEventManager.publishSuccessEvent(
                recordId,
                jobId,
                'Background Process Completed',
                resourceType,
                operationName
            );
            System.debug(LoggingLevel.INFO, '[AsyncProcessService.processAsyncOperation] SUCCESS - Published completion event for jobId: ' + jobId);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[AsyncProcessService.processAsyncOperation] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw ex;
        }
    }
}