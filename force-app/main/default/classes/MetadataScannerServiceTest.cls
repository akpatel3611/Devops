@isTest
public class MetadataScannerServiceTest {

    @isTest
    static void testApexClassAndTriggerScanning() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls-meta.xml', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/triggers/AccountTrigger.trigger', 'modified'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files, 'Webhook');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.totalFiles, 'Total files should be 3');
        System.assertEquals(2, result.metadataCount, 'Metadata count should be 2 due to deduplication');
        
        // Assert sorting and details
        List<MetadataScannerService.MetadataComponent> components = result.metadataComponents;
        System.assertEquals('ApexClass', components[0].metadataType);
        System.assertEquals('AccountController', components[0].componentName);
        System.assertEquals('Code', components[0].metadataCategory);
        System.assertEquals(5, components[0].deploymentOrder);
        System.assertEquals(false, components[0].hasDependency);
        
        System.assertEquals('ApexTrigger', components[1].metadataType);
        System.assertEquals('AccountTrigger', components[1].componentName);
    }

    @isTest
    static void testBundleMetadataScanning() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/lwc/myComponent/myComponent.js', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/lwc/myComponent/myComponent.html', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/lwc/myComponent/myComponent.js-meta.xml', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/aura/myAura/myAura.cmp', 'modified'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files, 'Manual');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(2, result.metadataCount, 'Should have 2 unique bundle components');
        
        List<MetadataScannerService.MetadataComponent> components = result.metadataComponents;
        // Sorting by type: AuraDefinitionBundle (A) comes before LightningComponentBundle (L)
        System.assertEquals('AuraDefinitionBundle', components[0].metadataType);
        System.assertEquals('myAura', components[0].componentName);
        System.assertEquals('UI', components[0].metadataCategory);
        System.assertEquals(6, components[0].deploymentOrder);
        
        System.assertEquals('LightningComponentBundle', components[1].metadataType);
        System.assertEquals('myComponent', components[1].componentName);
        System.assertEquals(100, components[1].confidenceScore);
    }

    @isTest
    static void testNestedSObjectMetadataScanning() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/objects/Account/fields/Active__c.field-meta.xml', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/objects/Account/validationRules/Verify_Active.validationRule-meta.xml', 'modified'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/objects/Account/Account.object-meta.xml', 'modified'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files, 'Pipeline');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(3, result.metadataCount);
        
        // Sorting by type: CustomField, CustomObject, ValidationRule
        List<MetadataScannerService.MetadataComponent> components = result.metadataComponents;
        
        System.assertEquals('CustomField', components[0].metadataType);
        System.assertEquals('Account.Active__c', components[0].componentName);
        System.assertEquals(true, components[0].hasDependency);
        System.assertEquals('CustomObject', components[0].dependencyType);
        System.assertEquals('Account', components[0].dependencyName);
        System.assertEquals('Data', components[0].metadataCategory);
        System.assertEquals(2, components[0].deploymentOrder);
        
        System.assertEquals('CustomObject', components[1].metadataType);
        System.assertEquals('Account', components[1].componentName);
        System.assertEquals(false, components[1].hasDependency);
        System.assertEquals(1, components[1].deploymentOrder);
        
        System.assertEquals('ValidationRule', components[2].metadataType);
        System.assertEquals('Account.Verify_Active', components[2].componentName);
        System.assertEquals(true, components[2].hasDependency);
    }

    @isTest
    static void testFolderStructuredMetadataScanning() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/email/unfiled$public/WelcomeTemplate.email-meta.xml', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/reports/SupportReports/CasesClosed.report-meta.xml', 'added'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(2, result.metadataCount);
        
        List<MetadataScannerService.MetadataComponent> components = result.metadataComponents;
        // EmailTemplate (E) before Report (R)
        System.assertEquals('EmailTemplate', components[0].metadataType);
        System.assertEquals('unfiled$public/WelcomeTemplate', components[0].componentName);
        System.assertEquals('Other', components[0].metadataCategory);
        
        System.assertEquals('Report', components[1].metadataType);
        System.assertEquals('SupportReports/CasesClosed', components[1].componentName);
    }

    @isTest
    static void testStaticResourceScanning() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/staticresources/MyResource.resource', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/staticresources/MyResource/img/logo.png', 'added'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.metadataCount, 'Should merge files belonging to same static resource');
        System.assertEquals('MyResource', result.metadataComponents[0].componentName);
        System.assertEquals('StaticResource', result.metadataComponents[0].metadataType);
    }

    @isTest
    static void testIgnoredAndUnsupportedFiles() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.add(MetadataScannerTestDataFactory.createChangedFile('README.md', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('package.json', 'modified'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/classes/AccountController.cls', 'added'));
        files.add(MetadataScannerTestDataFactory.createChangedFile('force-app/main/default/unsupportedDir/test.txt', 'added'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        // README and package.json are ignored.
        // AccountController is supported and deployable.
        // unsupportedDir/test.txt is scanned but is NOT supported (metadataType is null).
        System.assertEquals(4, result.totalFiles);
        System.assertEquals(1, result.deployableFiles);
        System.assertEquals(2, result.metadataCount);
        System.assertEquals(1, result.supportedFiles);
        System.assertEquals(1, result.unsupportedFiles);
        
        System.assert(result.warnings.size() > 0, 'Should have warnings for ignored files');
    }

    @isTest
    static void testRenameAndGitFields() {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        MetadataScannerService.ChangedFile renameFile = MetadataScannerTestDataFactory.createRenamedFile(
            'force-app/main/default/classes/NewClass.cls', 
            'force-app/main/default/classes/OldClass.cls', 
            'GitLab'
        );
        renameFile.sha = 'abc_rename_sha';
        files.add(renameFile);
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.metadataCount);
        
        MetadataScannerService.MetadataComponent comp = result.metadataComponents[0];
        System.assertEquals(true, comp.isRename);
        System.assertEquals('abc_rename_sha', comp.componentHash);
    }

    @isTest
    static void testBulkScanningSafety() {
        // Create 200 files of different types
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        files.addAll(MetadataScannerTestDataFactory.createBulkFiles(100, 'classes', '.cls'));
        files.addAll(MetadataScannerTestDataFactory.createBulkFiles(100, 'triggers', '.trigger'));
        
        Test.startTest();
        MetadataScannerService.MetadataScannerResult result = MetadataScannerService.discoverMetadata(files);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(200, result.totalFiles);
        System.assertEquals(200, result.metadataCount);
        System.assertEquals(100, result.metadataTypeCounts.get('ApexClass'));
        System.assertEquals(100, result.metadataTypeCounts.get('ApexTrigger'));
    }

    @isTest
    static void testMappingMethods() {
        Map<String, List<MetadataScannerService.MetadataMapping>> folderMappings = MetadataScannerService.getFolderMappings();
        Map<String, MetadataScannerService.MetadataMapping> packageMappings = MetadataScannerService.getPackageMappings();
        
        System.assert(folderMappings.containsKey('classes'), 'Should contain classes mapping');
        System.assert(packageMappings.containsKey('apexclass'), 'Should contain ApexClass mapping');
    }
}