public with sharing class AsyncBatch
implements Database.Batchable<SObject> {

    public Id recordId;

    public AsyncBatch(Id recordId) {

        this.recordId = recordId;
    }

    public Database.QueryLocator start(
        Database.BatchableContext bc
    ) {

        AsyncEventManager.publishStartEvent(

            recordId,
            bc.getJobId(),
            'Batch',
            'Batch Sync'
        );

        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Account
                LIMIT 50
            ]
        );
    }

    public void execute( Database.BatchableContext bc, List<Account> scope) {
        // fetch job details for progress tracking
        AsyncApexJob currentJob = [

            SELECT
                Id,
                TotalJobItems,
                JobItemsProcessed
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
            LIMIT 1
        ];

        // calculate progress percentage
        Integer progressValue = Integer.valueOf(
            (
                Decimal.valueOf( currentJob.JobItemsProcessed)
                /Decimal.valueOf(
                    currentJob.TotalJobItems
                )
            ) * 100
        );

        // progress event
        AsyncEventManager.publishProgressEvent(
            recordId,
            bc.getJobId(),
            progressValue,
            'Batch Processing Running',
            'Batch',
            'Batch Sync'
        );
    }

    public void finish(
        Database.BatchableContext bc
    ) {

        AsyncEventManager.publishSuccessEvent(

            recordId,
            bc.getJobId(),
            'Batch Completed',
            'Batch',
            'Batch Sync'
        );
    }
}