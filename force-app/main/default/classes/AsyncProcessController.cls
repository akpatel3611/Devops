public with sharing class AsyncProcessController {

    @AuraEnabled
    public static void startAsyncProcess(Id recordId) {

        System.enqueueJob(
            new AsyncProcessQueueable(recordId)
        );
    }
}