@isTest
private class AsyncOperationControllerTest {

    @isTest
    static void testAllMethods() {

        Account acc = new Account(
            Name='Test Account'
        );
        insert acc;

        Async_Operation_Log__c logRecord =
            new Async_Operation_Log__c(

                Record_Id__c=acc.Id,
                Record_Name__c='Test Record',
                Status__c='FAILED',
                BRR_Name__c='BRR Test',
                Operation_Name__c='Operation Test',
                Message__c='Testing',
                Progress__c=50
        );

        insert logRecord;

        Test.startTest();

        List<Async_Operation_Log__c> result =
            AsyncOperationController.getRecentOperations(
                acc.Id
            );

        Integer total =
            AsyncOperationController.getTotalOperations(
                acc.Id
            );

        Integer failed =
            AsyncOperationController.getFailedOperations(
                acc.Id
            );

        String status =
            AsyncOperationController.getAsyncJobStatus(
                '707000000000000'
            );

        Test.stopTest();

        System.assertEquals(
            1,
            result.size()
        );

        System.assertEquals(
            1,
            total
        );

        System.assertEquals(
            1,
            failed
        );

        System.assertNotEquals(
            null,
            status
        );

    }

}