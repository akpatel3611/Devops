@isTest
public class PipelineMetadataProcessorTest {
    
    @isTest
    static void testValidationEarlyExit() {
        // Files is empty list
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        
        Test.startTest();
        PipelineMetadataProcessor.PipelineProcessorResult result = PipelineMetadataProcessor.process(null, null, null, files, 'Manual');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.success);
        System.assertEquals('No changed files found to process.', result.message);
        System.assertEquals(0, result.metadataCount);
        System.assertEquals('1.0.0', result.processorVersion);
    }
    
    @isTest
    static void testProcessSuccessFlow() {
        // Insert mock runtime objects
        Pipeline__c pipe = new Pipeline__c(Name = 'Test Pipeline');
        insert pipe;
        
        Deployment_Request__c req = new Deployment_Request__c(Name = 'Test Request', Pipeline__c = pipe.Id);
        insert req;
        
        User_Story__c story = new User_Story__c(Title__c = 'Test Story');
        insert story;
        
        // Mock changed files
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls-meta.xml', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/triggers/AccountTrigger.trigger', 'modified'));
        
        Test.startTest();
        PipelineMetadataProcessor.PipelineProcessorResult result = PipelineMetadataProcessor.process(pipe.Id, req.Id, story.Id, files, 'Webhook');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.success);
        System.assertEquals(2, result.metadataCount);
        System.assertEquals(2, result.deployableCount);
        System.assertEquals(0, result.unsupportedCount);
        System.assertEquals(pipe.Id, result.pipelineId);
        System.assertEquals(req.Id, result.deploymentRequestId);
        System.assertEquals(story.Id, result.userStoryId);
        
        // Verify runtime fields updated using safe dynamic lookup checks
        Pipeline__c updatedPipe = [SELECT Id FROM Pipeline__c WHERE Id = :pipe.Id];
        Map<String, Schema.SObjectField> pipeFields = Schema.SObjectType.Pipeline__c.fields.getMap();
        if (pipeFields.containsKey('metadata_count__c')) {
            System.assertEquals(2, updatedPipe.get('Metadata_Count__c'));
            System.assertEquals('Completed', updatedPipe.get('Deployment_Runtime_Status__c'));
        }
        
        Deployment_Request__c updatedReq = [SELECT Id FROM Deployment_Request__c WHERE Id = :req.Id];
        Map<String, Schema.SObjectField> reqFields = Schema.SObjectType.Deployment_Request__c.fields.getMap();
        if (reqFields.containsKey('metadata_count__c')) {
            System.assertEquals(2, updatedReq.get('Metadata_Count__c'));
        }
        
        User_Story__c updatedStory = [SELECT Id FROM User_Story__c WHERE Id = :story.Id];
        Map<String, Schema.SObjectField> storyFields = Schema.SObjectType.User_Story__c.fields.getMap();
        if (storyFields.containsKey('metadata_count__c')) {
            System.assertEquals(2, updatedStory.get('Metadata_Count__c'));
            System.assertEquals('Completed', updatedStory.get('Metadata_Scan_Status__c'));
        }
    }
    
    @isTest
    static void testProcessSystemException() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls', 'added'));
        
        // Passing invalid ID string to force an Exception
        Id invalidId = 'a0e000000000000';
        
        Test.startTest();
        PipelineMetadataProcessor.PipelineProcessorResult result = PipelineMetadataProcessor.process(invalidId, null, null, files, 'Webhook');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(false, result.success);
        System.assertEquals('System failure encountered during metadata processing.', result.message);
        System.assert(result.errors.size() > 0);
    }
}