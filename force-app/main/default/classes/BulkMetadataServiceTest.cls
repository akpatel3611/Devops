@IsTest
public class BulkMetadataServiceTest {

    public class MockHttpResponseGenerator implements HttpCalloutMock {
        private Boolean failObject;
        private Set<String> failingFieldNames;

        public MockHttpResponseGenerator(Boolean failObject, Set<String> failingFieldNames) {
            this.failObject = failObject;
            this.failingFieldNames = failingFieldNames == null ? new Set<String>() : failingFieldNames;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');

            String body = req.getBody();
            if (failObject && body.contains('xsi:type="met:CustomObject"')) {
                res.setStatusCode(500);
                res.setBody(buildErrorBody('Custom Object already exists'));
                return res;
            }

            for (String failingFieldName : failingFieldNames) {
                if (body.contains(failingFieldName)) {
                    res.setStatusCode(500);
                    res.setBody(buildErrorBody(failingFieldName + ' failed to deploy'));
                    return res;
                }
            }

            res.setStatusCode(200);
            res.setBody(buildSuccessBody(extractFullName(body)));
            return res;
        }

        private String buildSuccessBody(String fullName) {
            return '<?xml version="1.0" encoding="utf-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<soapenv:Body>' +
                '<createMetadataResponse>' +
                '<result><success>true</success><fullName>' + fullName + '</fullName></result>' +
                '</createMetadataResponse>' +
                '</soapenv:Body>' +
                '</soapenv:Envelope>';
        }

        private String buildErrorBody(String message) {
            return '<?xml version="1.0" encoding="utf-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<soapenv:Body>' +
                '<createMetadataResponse>' +
                '<result><success>false</success><errors><message>' + message + '</message></errors></result>' +
                '</createMetadataResponse>' +
                '</soapenv:Body>' +
                '</soapenv:Envelope>';
        }

        private String extractFullName(String body) {
            Integer fullNameStart = body.indexOf('<met:fullName>');
            Integer fullNameEnd = body.indexOf('</met:fullName>', fullNameStart);
            if (fullNameStart == -1 || fullNameEnd == -1) {
                return 'Unknown';
            }
            return body.substring(fullNameStart + 14, fullNameEnd);
        }
    }

    @IsTest
    static void testGetObjects() {
        Test.startTest();
        List<Map<String, String>> objects = BulkMetadataService.getObjects();
        Test.stopTest();
        System.assertNotEquals(null, objects, 'Should return list of objects');
        System.assert(objects.size() > 0, 'Should return at least one object');
    }

    @IsTest
    static void testGetObjectFields() {
        Test.startTest();
        List<Map<String, String>> fields = BulkMetadataService.getObjectFields('Account');
        Test.stopTest();
        System.assertNotEquals(null, fields, 'Should return list of fields');
    }

    @IsTest
    static void testDeploySchemaSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false, null));

        ObjectDefinition obj = new ObjectDefinition();
        obj.label = 'Test Object';
        obj.pluralLabel = 'Test Objects';
        obj.apiName = 'TestObject__c';
        obj.nameFieldLabel = 'Name';
        obj.nameFieldType = 'Text';

        FieldDefinition field1 = new FieldDefinition();
        field1.rowKey = 'row-1';
        field1.label = 'Test Field 1';
        field1.apiName = 'TestField1__c';
        field1.dataType = 'Text';
        field1.length = 255;
        field1.relatedObject = 'TestObject__c';
        field1.isRequired = false;

        FieldDefinition field2 = new FieldDefinition();
        field2.rowKey = 'row-2';
        field2.label = 'Test Field 2';
        field2.apiName = 'TestField2__c';
        field2.dataType = 'Picklist';
        field2.picklistValues = 'A,B,C';
        field2.isRequired = false;

        Test.startTest();
        BulkMetadataService.DeploymentResult result = BulkMetadataService.deploySchema(
            obj,
            new List<FieldDefinition>{field1, field2}
        );
        Test.stopTest();

        System.assertEquals(true, result.overallSuccess, 'Overall result should be successful');
        System.assertEquals(2, result.successCount, 'Both fields should succeed');
        System.assertEquals(0, result.failureCount, 'No field should fail');
        System.assertEquals(true, result.objectResult.success, 'Object should succeed');
        System.assertEquals('row-1', result.fieldResults[0].rowKey, 'Row key should be preserved');
        System.assertEquals('Success', result.fieldResults[0].status, 'Field status should be success');
    }

    @IsTest
    static void testDeploySchemaPartialFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockHttpResponseGenerator(false, new Set<String>{'TestObject__c.TestField2__c'})
        );

        FieldDefinition field1 = new FieldDefinition();
        field1.rowKey = 'row-1';
        field1.label = 'Test Field 1';
        field1.apiName = 'TestField1__c';
        field1.dataType = 'Text';
        field1.length = 255;

        FieldDefinition field2 = new FieldDefinition();
        field2.rowKey = 'row-2';
        field2.label = 'Test Field 2';
        field2.apiName = 'TestField2__c';
        field2.dataType = 'Text';
        field2.length = 255;
        field2.relatedObject = 'TestObject__c';

        Test.startTest();
        BulkMetadataService.DeploymentResult result = BulkMetadataService.deploySchema(
            null,
            new List<FieldDefinition>{field1, field2}
        );
        Test.stopTest();

        System.assertEquals(false, result.overallSuccess, 'Overall result should be partial failure');
        System.assertEquals(1, result.successCount, 'One field should succeed');
        System.assertEquals(1, result.failureCount, 'One field should fail');
        System.assertEquals(true, result.fieldResults[0].success, 'First field should succeed');
        System.assertEquals(false, result.fieldResults[1].success, 'Second field should fail');
        System.assert(result.fieldResults[1].message.contains('failed to deploy'), 'Field error should surface');
    }

    @IsTest
    static void testDeploySchemaValidationFailure() {
        FieldDefinition field = new FieldDefinition();
        field.rowKey = 'row-1';
        field.label = 'Summary Field';
        field.apiName = 'SummaryField__c';
        field.dataType = 'Summary';

        Test.startTest();
        BulkMetadataService.DeploymentResult result = BulkMetadataService.deploySchema(
            null,
            new List<FieldDefinition>{field}
        );
        Test.stopTest();

        System.assertEquals(false, result.overallSuccess, 'Validation failures should not be successful');
        System.assertEquals(1, result.failureCount, 'Validation failure should mark the row as failed');
        System.assertEquals('Validation Error', result.fieldResults[0].status, 'Status should reflect validation');
    }

    @IsTest
    static void testInsertRecords() {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        Map<String, Object> rec = new Map<String, Object>();
        rec.put('Name', 'Test Account Name');
        rec.put('Phone', '1234567890');
        records.add(rec);

        Test.startTest();
        BulkMetadataService.insertRecords('Account', records);
        Test.stopTest();

        List<Account> accounts = [SELECT Id, Name, Phone FROM Account WHERE Name = 'Test Account Name'];
        System.assertEquals(1, accounts.size(), 'Should have inserted one account');
        System.assertEquals('1234567890', accounts[0].Phone, 'Phone number should match');
    }
    @IsTest
    static void testAssignProfileFlsSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false, null));

        ProfileFlsAssignment assignment = new ProfileFlsAssignment();
        assignment.profileMetadataName = 'Admin';
        assignment.profileLabel = 'System Administrator';
        assignment.readAll = true;
        assignment.editAll = true;

        List<String> fieldApiNames = new List<String>{
            'Account.Salary__c',
            'Account.Employee_ID__c'
        };

        Test.startTest();
        List<BulkMetadataService.ProfileFlsResult> results = BulkMetadataService.assignProfileFls(
            new List<ProfileFlsAssignment>{ assignment },
            fieldApiNames
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result per profile');
        System.assertEquals(true, results[0].success, 'FLS assignment should succeed');
        System.assertEquals('System Administrator', results[0].profileLabel, 'Profile label should be preserved');
        System.assertEquals(2, results[0].fieldsApplied, 'Should report 2 fields applied');
        System.assert(results[0].message.contains('successfully'), 'Success message should confirm FLS applied');
    }

    @IsTest
    static void testAssignProfileFlsFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockHttpResponseGenerator(false, new Set<String>{ 'Account.Salary__c' })
        );

        ProfileFlsAssignment assignment = new ProfileFlsAssignment();
        assignment.profileMetadataName = 'Standard';
        assignment.profileLabel = 'Standard User';
        assignment.readAll = true;
        assignment.editAll = false;

        Test.startTest();
        List<BulkMetadataService.ProfileFlsResult> results = BulkMetadataService.assignProfileFls(
            new List<ProfileFlsAssignment>{ assignment },
            new List<String>{ 'Account.Salary__c' }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'FLS assignment should fail');
        System.assert(String.isNotBlank(results[0].message), 'Failure message should be populated');
    }

    @IsTest
    static void testAssignProfileFlsEmptyInputs() {
        Test.startTest();
        List<BulkMetadataService.ProfileFlsResult> results = BulkMetadataService.assignProfileFls(
            new List<ProfileFlsAssignment>(),
            new List<String>{ 'Account.Salary__c' }
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty assignments should return empty list');
    }
}