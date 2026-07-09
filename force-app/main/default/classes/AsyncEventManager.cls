public with sharing class AsyncEventManager {

    /// 
    /// This class serves as a centralized manager for publishing asynchronous process events.
    public static void publishStartEvent(

        Id recordId,
        Id jobId,
        String resourceType,
        String operationName
    ) {
        System.debug('Publishing STARTED event for recordId: ' + recordId + ', jobId: ' + jobId);
        AsyncEventPublisher.publishEvent(
            recordId,
            'STARTED',
            'Process Started',
            jobId,
            0,
            resourceType,
            operationName
        );
    }

    /*
    =========================================
    PROGRESS EVENT
    =========================================
    */

    public static void publishProgressEvent(

        Id recordId,
        Id jobId,
        Integer progress,
        String message,
        String resourceType,
        String operationName
    ) {

        AsyncEventPublisher.publishEvent(

            recordId,
            'IN_PROGRESS',
            message,
            jobId,
            progress,
            resourceType,
            operationName
        );
    }

    /*
    =========================================
    SUCCESS EVENT
    =========================================
    */

    public static void publishSuccessEvent(

        Id recordId,
        Id jobId,
        String message,
        String resourceType,
        String operationName
    ) {

        AsyncEventPublisher.publishEvent(

            recordId,
            'SUCCESS',
            message,
            jobId,
            100,
            resourceType,
            operationName
        );
    }

    /*
    =========================================
    FAILURE EVENT
    =========================================
    */

    public static void publishFailureEvent(

        Id recordId,
        Id jobId,
        String errorMessage,
        String resourceType,
        String operationName
    ) {

        AsyncEventPublisher.publishEvent(

            recordId,
            'FAILED',
            errorMessage,
            jobId,
            0,
            resourceType,
            operationName
        );
    }
}