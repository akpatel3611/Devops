public with sharing class AsyncEventPublisher {

    public static void publishEvent(

        Id recordId,
        String status,
        String message,
        Id jobId,
        Integer progress,
        String resourceType,
        String operationName
    ) {

        Async_Process_Event__e eventObj = new Async_Process_Event__e();

        eventObj.Record_Id__c = String.valueOf(recordId);
        eventObj.Status__c = status;
        eventObj.Message__c = message;
        eventObj.Job_Id__c = String.valueOf(jobId);
        eventObj.Progress__c = progress;
        eventObj.Resource_Type__c = resourceType;
        eventObj.Operation_Name__c = operationName;
        Database.SaveResult sr = EventBus.publish(eventObj);

        if (sr.isSuccess()) {
            System.debug('Platform Event Published Successfully');
        }
        else {
            for(Database.Error err : sr.getErrors()) {
                System.debug(err.getMessage());
            }
        }
    }
}