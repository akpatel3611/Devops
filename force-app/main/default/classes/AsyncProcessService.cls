public with sharing class AsyncProcessService {

    public static void processAsyncOperation(

    Id recordId,
    Id jobId,
    String resourceType,
    String operationName
) {

    // fetch object api name
    String objectApiName =
        recordId
        .getSObjectType()
        .getDescribe()
        .getName();

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

   // start event
    AsyncEventManager.publishProgressEvent(
        recordId,
        jobId,
        10,
        'Initializing Background Process',
        resourceType,
        operationName
    );
    
    // dynamic record fetching (replace with actual logic as needed)
    String query =
        'SELECT Id ' +
        'FROM ' +
        objectApiName +
        ' WHERE Id = :recordId';

    List<SObject> recordList =
        Database.query(query);
        
    //validation logic
    AsyncEventManager.publishProgressEvent(
        recordId,
        jobId,
        30,
        'Validating Record Data',
        resourceType,
        operationName
    );

     // background processing simulation
     // (replace with actual logic as needed)
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

    // job processing event
    Integer processedCount = asyncJob.JobItemsProcessed;
    Integer totalCount = asyncJob.TotalJobItems;
    Integer calculatedProgress = 80;

    if (totalCount > 0) {
        calculatedProgress =
            Integer.valueOf(
                (
                    Decimal.valueOf(processedCount)
                    /
                    Decimal.valueOf(totalCount)
                ) * 100
            );
    }

    AsyncEventManager.publishProgressEvent(
        recordId,
        jobId,
        calculatedProgress,
        'Processing Background Operations',
        resourceType,
        operationName
    );

    //success event
    AsyncEventManager.publishSuccessEvent(
        recordId,
        jobId,
        'Background Process Completed',
        resourceType,
        operationName
    );
}
}