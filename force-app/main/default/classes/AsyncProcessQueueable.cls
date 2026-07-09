public with sharing class AsyncProcessQueueable implements Queueable {
    private Id recordId;
    
    public AsyncProcessQueueable(Id recordId) {
        this.recordId = recordId;
    }

    public void execute(QueueableContext context) {
        try {
            AsyncEventManager.publishStartEvent(
                recordId,
                context.getJobId(),
                'Queueable',
                'Async Background Operation'
            );

            AsyncProcessService.processAsyncOperation(
                recordId,
                context.getJobId(),
                'Queueable',
                'Async Background Operation'
            );
        }
        catch(Exception ex) {
            AsyncEventManager.publishFailureEvent(
                recordId,
                context.getJobId(),
                ex.getMessage(),
                'Queueable',
                'Async Background Operation'
            );
        }
    }

    // Helper to publish event immediately
    // NOTE: Because of "Publish Immediately" setting, these fire instantly
    // private void publishEvent(Id recId, String jobId, Decimal progress, String status, String msg) {
    //     Async_Process_Event__e event = new Async_Process_Event__e(
    //         Record_Id__c = recId,
    //         Job_Id__c = jobId,
    //         Progress__c = progress,
    //         Status__c = status,
    //         Message__c = msg,
    //         Resource_Type__c = 'Queueable',
    //         Operation_Name__c = 'Customer Sync'
    //     );
    //     EventBus.publish(event);
    // }
}