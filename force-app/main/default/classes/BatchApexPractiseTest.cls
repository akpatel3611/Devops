@isTest
public class BatchApexPractiseTest {

    @isTest
    static void testBatchExecution() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@example.com',
            Username = 'testuser' + DateTime.now().getTime() + '@example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        System.runAs(u) {

            List<Task> taskList = new List<Task>();

            Task emailTask = new Task(
                Subject = 'Follow-up Email',
                WhatId = acc.Id,
                Status = 'Completed',
                ActivityDate = Date.today(),
                CallDurationInSeconds = null,
                //CompletedDateTime = System.now(),
                Priority = 'Normal'
            );
            taskList.add(emailTask);

            Task callTask = new Task(
                Subject = 'Sales Call',
                WhatId = acc.Id,
                Status = 'Completed',
                CallDurationInSeconds = 300,
                ActivityDate = Date.today(),
                //CompletedDateTime = System.now(),
                Priority = 'High'
            );
            taskList.add(callTask);
            insert taskList;
        }

        Test.startTest();
        BatchApexPractise batch = new BatchApexPractise();
        Database.executeBatch(batch, 200); // scope size 200
        Test.stopTest();

        
        Account updatedAcc = [SELECT Last_Call__c, Last_Sales_Activity__c FROM Account WHERE Id = :acc.Id];

        System.assertNotEquals(null, updatedAcc.Last_Sales_Activity__c, 'Last Sales Activity should be updated');
        System.assertNotEquals(null, updatedAcc.Last_Call__c, 'Last Call should be updated');
    }
}