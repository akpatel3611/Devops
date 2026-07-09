public with sharing class FutureProcess {

    @future
    public static void processFuture(
        Id recordId
    ) {

        AsyncEventManager.publishStartEvent(

            recordId,
            null,
            'Future',
            'Future Sync'
        );

        AsyncEventManager.publishProgressEvent(

            recordId,
            null,
            50,
            'Future Processing',
            'Future',
            'Future Sync'
        );

        AsyncEventManager.publishSuccessEvent(

            recordId,
            null,
            'Future Completed',
            'Future',
            'Future Sync'
        );
    }
}