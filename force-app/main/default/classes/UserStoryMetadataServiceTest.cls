@isTest
private class UserStoryMetadataServiceTest {

    @isTest
    static void testPersistMetadataSuccess() {
        // Create parent user story record
        User_Story__c story = new User_Story__c(
            Name = 'US-001'
        );
        insert story;

        // Build list of scanner components DTOs
        List<MetadataScannerService.MetadataComponent> components = new List<MetadataScannerService.MetadataComponent>();
        
        MetadataScannerService.MetadataComponent comp1 = new MetadataScannerService.MetadataComponent();
        comp1.componentName = 'MyTestClass';
        comp1.metadataType = 'ApexClass';
        comp1.status = 'added';
        comp1.filePath = 'force-app/main/default/classes/MyTestClass.cls';
        components.add(comp1);

        MetadataScannerService.MetadataComponent comp2 = new MetadataScannerService.MetadataComponent();
        comp2.componentName = 'MyTestClassTrigger';
        comp2.metadataType = 'ApexTrigger';
        comp2.status = 'modified';
        comp2.filePath = 'force-app/main/default/triggers/MyTestClassTrigger.trigger';
        components.add(comp2);

        Test.startTest();
        UserStoryMetadataService.persistMetadata(story.Id, components);
        Test.stopTest();

        // Verify insertion
        List<User_Story_Metadata__c> inserted = [
            SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c 
            FROM User_Story_Metadata__c 
            WHERE User_Story__c = :story.Id
        ];
        System.assertEquals(2, inserted.size(), 'Expected 2 inventory records to be created');
        
        Map<String, User_Story_Metadata__c> recordsByName = new Map<String, User_Story_Metadata__c>();
        for (User_Story_Metadata__c rec : inserted) {
            recordsByName.put(rec.Metadata_API_Name__c, rec);
        }
        
        System.assert(recordsByName.containsKey('MyTestClass'), 'Expected MyTestClass record');
        System.assertEquals('ApexClass', recordsByName.get('MyTestClass').Metadata_Type__c);
        System.assertEquals('added', recordsByName.get('MyTestClass').Action__c);
        
        System.assert(recordsByName.containsKey('MyTestClassTrigger'), 'Expected MyTestClassTrigger record');
        System.assertEquals('ApexTrigger', recordsByName.get('MyTestClassTrigger').Metadata_Type__c);
        System.assertEquals('modified', recordsByName.get('MyTestClassTrigger').Action__c);
    }

    @isTest
    static void testReScanClearsDuplicates() {
        User_Story__c story = new User_Story__c(
            Name = 'US-002'
        );
        insert story;

        List<MetadataScannerService.MetadataComponent> originalComponents = new List<MetadataScannerService.MetadataComponent>();
        MetadataScannerService.MetadataComponent comp1 = new MetadataScannerService.MetadataComponent();
        comp1.componentName = 'OldClass';
        comp1.metadataType = 'ApexClass';
        comp1.status = 'added';
        comp1.filePath = 'force-app/main/default/classes/OldClass.cls';
        originalComponents.add(comp1);

        // Run first scan persistence
        UserStoryMetadataService.persistMetadata(story.Id, originalComponents);
        System.assertEquals(1, [SELECT count() FROM User_Story_Metadata__c WHERE User_Story__c = :story.Id]);

        // Setup new list representing a subsequent commit re-scan
        List<MetadataScannerService.MetadataComponent> newComponents = new List<MetadataScannerService.MetadataComponent>();
        MetadataScannerService.MetadataComponent comp2 = new MetadataScannerService.MetadataComponent();
        comp2.componentName = 'NewClass';
        comp2.metadataType = 'ApexClass';
        comp2.status = 'added';
        comp2.filePath = 'force-app/main/default/classes/NewClass.cls';
        newComponents.add(comp2);

        Test.startTest();
        UserStoryMetadataService.persistMetadata(story.Id, newComponents);
        Test.stopTest();

        // Verify clean replace occurred
        List<User_Story_Metadata__c> records = [
            SELECT Id, Metadata_API_Name__c 
            FROM User_Story_Metadata__c 
            WHERE User_Story__c = :story.Id
        ];
        System.assertEquals(1, records.size(), 'Expected old records to be deleted and only 1 new record remaining');
        System.assertEquals('NewClass', records[0].Metadata_API_Name__c);
    }

    @isTest
    static void testNullInputs() {
        Test.startTest();
        UserStoryMetadataService.persistMetadata(null, null);
        Test.stopTest();
        
        System.assertEquals(0, [SELECT count() FROM User_Story_Metadata__c], 'Expected zero records');
    }
}