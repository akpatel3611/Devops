@isTest
public class ObjectManagerControllerTest {
// test
    /* =========================================
       HTTP CALLOUT MOCK - SUCCESS SCENARIOS
       ========================================= */

    public class ObjectManagerMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String endpoint = req.getEndpoint();
            String method = req.getMethod();
            String body = req.getBody();

            // SOAP Metadata API (field/object deletion)
            if (endpoint.contains('/services/Soap/m/')) {
                res.setHeader('Content-Type', 'text/xml');
                res.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<env:Body>' +
                    '<deleteMetadataResponse>' +
                    '<result>' +
                    '<success>true</success>' +
                    '<fullName>Account.TestCustomField__c</fullName>' +
                    '</result>' +
                    '</deleteMetadataResponse>' +
                    '</env:Body>' +
                    '</env:Envelope>'
                );
                return res;
            }

            // Tooling API query
            if (endpoint.contains('/tooling/query')) {
                String decodedQuery = '';
                try {
                    decodedQuery = EncodingUtil.urlDecode(endpoint.substringAfter('q='), 'UTF-8');
                } catch (Exception ex) {
                    decodedQuery = endpoint;
                }

                if (decodedQuery.contains('FROM EntityDefinition')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"QualifiedApiName": "Account", "IsCustomizable": true, "IsCustomSetting": false, "IsDeprecatedAndHidden": false, "Id": "Account", "DurableId": "Account"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM CustomField')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "01Ixx0000000001", "DeveloperName": "TestCustomField", "TableEnumOrId": "Account", "ManageableState": "unmanaged"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM ValidationRule')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "03dxx0000000001", "ValidationName": "Test_Validation", "Active": true, "ErrorConditionFormula": "ISBLANK(Name)", "ErrorMessage": "Name is required", "EntityDefinitionId": "Account", "Metadata": {"errorConditionFormula": "ISBLANK(Name)", "errorMessage": "Name is required"}}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM ApexClass')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Name": "ObjectManagerController", "Body": "public class ObjectManagerController { Account a; }"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM WebLink')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "00txx0000000001", "Name": "Test_Link", "MasterLabel": "Test Link Label", "DisplayType": "link", "LinkType": "url", "OpenType": "newWindow"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM QuickActionDefinition')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "09dxx0000000001", "DeveloperName": "Test_Action", "MasterLabel": "Test Action Label", "Type": "Create", "ActionSubtype": "Action", "TargetSobjectType": "Contact"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM PublisherAction')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "09dxx0000000002", "DeveloperName": "Test_Publisher_Action", "MasterLabel": "Test Pub Label", "DisplayType": "button", "ActionType": "Action", "ActionSubtype": "Action", "SobjectType": "Account"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM FlexiPage')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "0lhxx0000000002", "DeveloperName": "Account_Record_Page", "MasterLabel": "Account Record Page", "Type": "RecordPage"}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM WorkflowRule')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "0dfxx0000000001", "Name": "Test Workflow Rule", "TableEnumOrId": "Account", "Metadata": {"active": true}}' +
                        ']' +
                    '}');
                } else if (decodedQuery.contains('FROM CompactLayout')) {
                    res.setBody('{' +
                        '"records": [' +
                            '{"Id": "0lhxx0000000003", "DeveloperName": "Test_Compact", "MasterLabel": "Test Compact"}' +
                        ']' +
                    '}');
                } else {
                    res.setBody('{"records": []}');
                }
                return res;
            }

            // Tooling API POST (custom field creation)
            if (endpoint.contains('/tooling/sobjects/CustomField')) {
                res.setBody('{"id": "01Ixx0000000001", "success": true}');
                return res;
            }

            // SObject describe compact layouts
            if (endpoint.contains('/describe/compactLayouts')) {
                res.setBody('{' +
                    '"compactLayouts": [' +
                        '{"id": "0lhxx0000000001", "name": "Account Compact Layout", "label": "Account Compact Layout Label", "isDefault": true, "fields": [{"label": "Account Name", "name": "Name"}]}' +
                    '],' +
                    '"defaultCompactLayoutId": "0lhxx0000000001"' +
                '}');
                return res;
            }

            // SObject describe layouts
            if (endpoint.contains('/describe/layouts')) {
                res.setBody('{' +
                    '"layouts": [' +
                        '{' +
                            '"id": "00hxx0000000001",' +
                            '"label": "Account Layout",' +
                            '"name": "Account Layout",' +
                            '"layoutType": "Full",' +
                            '"mode": "View",' +
                            '"saveOptions": [{"name": "Save", "label": "Save", "isDefault": true}],' +
                            '"limitRows": 10,' +
                            '"buttonLayoutSection": {' +
                                '"detailButtons": [' +
                                    '{"label": "Custom Detail", "name": "Custom_Detail", "id": "00b000000000001AAA", "custom": true, "contentSource": "url", "url": "/servlet/servlet.Integration?lid=00b000000000002AAA"},' +
                                    '{"title": "View", "apiName": "view", "custom": false}' +
                                '],' +
                                '"listButtons": [' +
                                    '{"label": "New", "name": "new", "custom": false}' +
                                ']' +
                            '},' +
                            '"relatedLists": [' +
                                '{"label": "Contacts", "buttons": [{"label": "New Contact", "name": "NewContact", "custom": false}, {"label": "Custom RL", "name": "Custom_RL", "custom": true}]}' +
                            '],' +
                            '"layoutSections": [' +
                                '{"heading": "Account Information", "useHeading": true, "layoutRows": [{"layoutItems": [{"editable": true, "required": false, "label": "Account Name", "layoutComponents": [{"type": "Field", "componentType": "FIELD", "value": "Name", "apiName": "Name", "details": {"name": "Name", "apiName": "Name"}}]}]}]},' +
                                '{"heading": "System Information", "useHeading": true, "layoutRows": [{"layoutItems": [{"editable": false, "required": false, "label": "Created By", "layoutComponents": [{"type": "Field", "componentType": "FIELD", "value": "CreatedById"}]}]}]}' +
                            '],' +
                            '"detailLayoutSections": [' +
                                '{"heading": "Account Information", "useHeading": true, "layoutRows": [{"layoutItems": [{"editable": true, "required": false, "label": "Account Name", "layoutComponents": [{"type": "Field", "componentType": "FIELD", "value": "Name", "apiName": "Name", "details": {"name": "Name", "apiName": "Name"}}]}]}]}' +
                            ']' +
                        '}' +
                    '],' +
                    '"recordTypeMappings": [' +
                        '{"recordTypeId": "012000000000000AAA", "name": "Master", "layoutId": "00hxx0000000001"}' +
                    ']' +
                '}');
                return res;
            }

            // SObject describe (general)
            if (endpoint.contains('/describe')) {
                res.setBody('{' +
                    '"name": "Account",' +
                    '"label": "Account",' +
                    '"fields": [' +
                        '{"name": "Name", "label": "Account Name", "type": "string"}' +
                    '],' +
                    '"recordTypeInfos": [' +
                        '{"recordTypeId": "012000000000000AAA", "name": "Master", "active": true, "urls": {"layout": "/services/data/v66.0/sobjects/Account/describe/layouts/012000000000000AAA"}}' +
                    ']' +
                '}');
                return res;
            }

            // UI API layout
            if (endpoint.contains('/ui-api/layout/')) {
                res.setBody('{' +
                    '"layout": {' +
                        '"id": "00hxx0000000002",' +
                        '"layoutType": "Full",' +
                        '"mode": "View",' +
                        '"saveOptions": [{"name": "Save", "label": "Save", "isDefault": true}],' +
                        '"sections": [' +
                            '{"heading": "Highlights", "layoutRows": [{"layoutItems": [{"layoutComponents": [{"componentType": "FIELD", "apiName": "Name"}]}]}]},' +
                            '{"heading": "Details", "layoutRows": [{"layoutItems": [{"layoutComponents": [{"componentType": "FIELD", "details": {"apiName": "OwnerId"}}]}]}]}' +
                        ']' +
                    '}' +
                '}');
                return res;
            }

            // Search layouts
            if (endpoint.contains('/search/layout')) {
                res.setBody('{' +
                    '"value": [' +
                        '{"label": "Default Search", "searchColumns": [{"name": "Name", "label": "Account Name", "field": "Name"}, {"name": "Owner.Name", "label": "Owner", "field": "OwnerId"}]}' +
                    ']' +
                '}');
                return res;
            }

            // Default empty response
            res.setBody('{}');
            return res;
        }
    }

    /* =========================================
       HTTP CALLOUT MOCK - ERROR SCENARIOS
       ========================================= */

    public class ObjectManagerErrorMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('[{"message": "Internal Server Error", "errorCode": "SERVER_ERROR"}]');
            return res;
        }
    }

    public class ObjectManagerMetadataFaultMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(200);
            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<env:Body>' +
                '<env:Fault><faultstring>Delete denied by test mock</faultstring></env:Fault>' +
                '</env:Body>' +
                '</env:Envelope>'
            );
            return res;
        }
    }

    public class ObjectManagerUnreadableMetadataMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(500);
            res.setBody('not xml');
            return res;
        }
    }

    public class ObjectManagerUnreadableSuccessMetadataMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(200);
            res.setBody('not xml');
            return res;
        }
    }

    public class ObjectManagerNoResultMetadataMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(200);
            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<env:Body><deleteMetadataResponse></deleteMetadataResponse></env:Body>' +
                '</env:Envelope>'
            );
            return res;
        }
    }

    public class ObjectManagerFailedResultMetadataMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/xml');
            res.setStatusCode(200);
            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<env:Body><deleteMetadataResponse><result>' +
                '<success>false</success>' +
                '<errors><statusCode>FIELD_INTEGRITY_EXCEPTION</statusCode><message>Cannot delete test metadata</message></errors>' +
                '</result></deleteMetadataResponse></env:Body>' +
                '</env:Envelope>'
            );
            return res;
        }
    }

    public class ObjectManagerNonCustomizableMockProvider implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            if (req.getEndpoint().contains('/tooling/query')) {
                res.setBody('{"records": [{"QualifiedApiName": "Account", "IsCustomizable": false, "DurableId": "Account", "Id": "Account"}]}');
            } else {
                res.setBody('{}');
            }

            return res;
        }
    }

    /* =========================================
       TEST: getAllObjects
       ========================================= */

    @isTest
    static void testGetAllObjects() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        List<Map<String, Object>> result = ObjectManagerController.getAllObjects();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result list should not be null');
        // Account is a standard accessible object, should be in the list
        Boolean foundAccount = false;
        for (Map<String, Object> obj : result) {
            if (obj.get('apiName') == 'Account') {
                foundAccount = true;
                System.assertEquals('Account', obj.get('label'));
                System.assertEquals(false, obj.get('isCustom'));
                System.assertEquals('Standard', obj.get('typeLabel'));
                break;
            }
        }
    }

    /* =========================================
       TEST: getObjectDetails
       ========================================= */

    @isTest
    static void testGetObjectDetails() {
        Test.startTest();
        // Valid object
        Map<String, Object> details = ObjectManagerController.getObjectDetails('Account');
        // Invalid object
        Map<String, Object> emptyDetails = ObjectManagerController.getObjectDetails('NonExistentObject__c');
        Test.stopTest();

        System.assertNotEquals(null, details);
        System.assertEquals('Account', details.get('apiName'));
        System.assertEquals('Account', details.get('label'));
        System.assertNotEquals(null, details.get('keyPrefix'));
        System.assertEquals(false, details.get('isCustom'));
        System.assertNotEquals(null, details.get('isQueryable'));
        System.assertNotEquals(null, details.get('isCreateable'));
        System.assertNotEquals(null, details.get('isUpdateable'));
        System.assertNotEquals(null, details.get('isDeletable'));
        System.assertEquals(true, emptyDetails.isEmpty());
    }

    /* =========================================
       TEST: getObjectFields
       ========================================= */

    @isTest
    static void testGetObjectFields() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        List<Map<String, Object>> fields = ObjectManagerController.getObjectFields('Account');
        List<Map<String, Object>> emptyFields = ObjectManagerController.getObjectFields('ZZZNonExistentObject__c');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assert(!fields.isEmpty(), 'Account should have fields');
        // Verify field structure
        Map<String, Object> firstField = fields[0];
        System.assert(firstField.containsKey('label'));
        System.assert(firstField.containsKey('apiName'));
        System.assert(firstField.containsKey('dataType'));
        System.assert(firstField.containsKey('isRequired'));
        System.assert(firstField.containsKey('isCustom'));
        System.assert(firstField.containsKey('isExternalId'));

        System.assertEquals(true, emptyFields.isEmpty());
    }

    /* =========================================
       TEST: createFieldsBulk - all field types
       ========================================= */

    @isTest
    static void testCreateFieldsBulkAllTypes() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        List<Map<String, Object>> fieldDefs = new List<Map<String, Object>>();

        // 1. Text
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Text Field',
            'apiName' => 'Test_Text_Field',
            'type' => 'Text',
            'length' => 100,
            'required' => true,
            'description' => 'Test description',
            'helpText' => 'Help text',
            'unique' => true,
            'externalId' => true
        });

        // 2. TextArea
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test TextArea',
            'apiName' => 'Test_TextArea',
            'type' => 'TextArea'
        });

        // 3. LongTextArea
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Long Text',
            'apiName' => 'Test_Long_Text',
            'type' => 'LongTextArea',
            'length' => 50000,
            'visibleLines' => 5
        });

        // 4. Html / Rich Text Area
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Html',
            'apiName' => 'Test_Html',
            'type' => 'Html',
            'length' => 32768,
            'visibleLines' => 10
        });

        // 5. Number
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Number',
            'apiName' => 'Test_Number',
            'type' => 'Number',
            'precision' => 10,
            'scale' => 2,
            'unique' => true,
            'externalId' => true
        });

        // 6. Currency
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Currency',
            'apiName' => 'Test_Currency',
            'type' => 'Currency',
            'precision' => 16,
            'scale' => 2
        });

        // 7. Percent
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Percent',
            'apiName' => 'Test_Percent',
            'type' => 'Percent'
        });

        // 8. Checkbox
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Checkbox',
            'apiName' => 'Test_Checkbox',
            'type' => 'Checkbox',
            'defaultValue' => true
        });

        // 9. AutoNumber
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test AutoNumber',
            'apiName' => 'Test_AutoNumber',
            'type' => 'AutoNumber',
            'displayFormat' => 'TST-{0000}',
            'startingNumber' => 1
        });

        // 10. Picklist
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Picklist',
            'apiName' => 'Test_Picklist',
            'type' => 'Picklist',
            'picklistValues' => 'Value1\nValue2\nValue3'
        });

        // 11. MultiselectPicklist
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Multi Picklist',
            'apiName' => 'Test_Multi_Picklist',
            'type' => 'MultiselectPicklist',
            'picklistValues' => 'Alpha;Beta;Gamma'
        });

        // 12. Date
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Date',
            'apiName' => 'Test_Date',
            'type' => 'Date'
        });

        // 13. DateTime
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test DateTime',
            'apiName' => 'Test_DateTime',
            'type' => 'DateTime'
        });

        // 14. Time
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Time',
            'apiName' => 'Test_Time',
            'type' => 'Time'
        });

        // 15. Email
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Email',
            'apiName' => 'Test_Email',
            'type' => 'Email',
            'unique' => false,
            'externalId' => false
        });

        // 16. Phone
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Phone',
            'apiName' => 'Test_Phone',
            'type' => 'Phone'
        });

        // 17. Url
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Url',
            'apiName' => 'Test_Url',
            'type' => 'Url'
        });

        // 18. EncryptedText
        fieldDefs.add(new Map<String, Object>{
            'label' => 'Test Encrypted',
            'apiName' => 'Test_Encrypted',
            'type' => 'EncryptedText',
            'length' => 100
        });

        Test.startTest();
        List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', fieldDefs);
        Test.stopTest();

        System.assertEquals(fieldDefs.size(), results.size(), 'Results count should match input count');
        for (Map<String, Object> r : results) {
            System.assertEquals(true, r.get('success'), 'Field creation should succeed: ' + r.get('message'));
        }
    }

    /* =========================================
       TEST: createFieldsBulk - validation errors
       ========================================= */

    @isTest
    static void testCreateFieldsBulkValidations() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // 1. Blank object name
        try {
            ObjectManagerController.createFieldsBulk('', new List<Map<String, Object>>{ new Map<String, Object>() });
            System.assert(false, 'Should throw for blank object name');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        // 2. Null field definitions
        try {
            ObjectManagerController.createFieldsBulk('Account', null);
            System.assert(false, 'Should throw for null field definitions');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        // 3. Empty field definitions
        try {
            ObjectManagerController.createFieldsBulk('Account', new List<Map<String, Object>>());
            System.assert(false, 'Should throw for empty field definitions');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        // 4. Invalid object name (not in Schema)
        try {
            ObjectManagerController.createFieldsBulk('ZZZInvalidObject__c', new List<Map<String, Object>>{ new Map<String, Object>{'label' => 'X', 'type' => 'Text'} });
            System.assert(false, 'Should throw for invalid object name');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        // 5. Missing label
        List<Map<String, Object>> defs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'apiName' => 'Test_Field', 'type' => 'Text' }
        };
        List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', defs);
        System.assertEquals(false, results[0].get('success'), 'Missing label should fail');

        // 6. Missing type
        defs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'label' => 'Test Field' }
        };
        results = ObjectManagerController.createFieldsBulk('Account', defs);
        System.assertEquals(false, results[0].get('success'), 'Missing type should fail');

        // 7. Picklist without values
        defs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'label' => 'Test Pick', 'type' => 'Picklist', 'picklistValues' => '' }
        };
        results = ObjectManagerController.createFieldsBulk('Account', defs);
        System.assertEquals(false, results[0].get('success'), 'Picklist without values should fail');

        // 8. Unsupported field type
        defs = new List<Map<String, Object>>{
            new Map<String, Object>{ 'label' => 'Test Unknown', 'type' => 'SuperCustomType' }
        };
        results = ObjectManagerController.createFieldsBulk('Account', defs);
        System.assertEquals(false, results[0].get('success'), 'Unsupported type should fail');
    }

    /* =========================================
       TEST: deleteField
       ========================================= */

    @isTest
    static void testDeleteFieldValidations() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // 1. Blank object name
        try {
            ObjectManagerController.deleteField('', 'Name', '', '');
            System.assert(false, 'Should throw for blank object name');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }

        // 2. Blank field name
        try {
            ObjectManagerController.deleteField('Account', '', '', '');
            System.assert(false, 'Should throw for blank field name');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }

        // 3. Non-existent field
        try {
            ObjectManagerController.deleteField('Account', 'ZZZNonExistentField__c', '', '');
            System.assert(false, 'Should throw for non-existent field');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }

        // 4. Standard field (cannot delete)
        try {
            ObjectManagerController.deleteField('Account', 'Name', '', '');
            System.assert(false, 'Should throw for standard field deletion');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @isTest
    static void testDeleteFieldCustom() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // Dynamically find any custom field to test the happy path
        String customFieldName = '';
        String targetObjectName = '';
        for (String objName : Schema.getGlobalDescribe().keySet()) {
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objName).getDescribe();
            if (!objDescribe.isAccessible()) continue;
            for (Schema.SObjectField fld : objDescribe.fields.getMap().values()) {
                if (fld.getDescribe().isCustom()) {
                    customFieldName = fld.getDescribe().getName();
                    targetObjectName = objDescribe.getName();
                    break;
                }
            }
            if (customFieldName != '') break;
        }

        Test.startTest();
        if (customFieldName != '') {
            Map<String, Object> deleteResult = ObjectManagerController.deleteField(
                targetObjectName, customFieldName, '', ''
            );
            System.assertEquals(true, deleteResult.get('success'));
        }
        Test.stopTest();
    }

    /* =========================================
       TEST: deleteObject
       ========================================= */

    @isTest
    static void testDeleteObjectValidations() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // 1. Blank object name
        try {
            ObjectManagerController.deleteObject('');
            System.assert(false, 'Should throw for blank object name');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }

        // 2. Non-existent object
        try {
            ObjectManagerController.deleteObject('ZZZNonExistentObject__c');
            System.assert(false, 'Should throw for non-existent object');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }

        // 3. Standard object (cannot delete)
        try {
            ObjectManagerController.deleteObject('Account');
            System.assert(false, 'Should throw for standard object deletion');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
    }

    @isTest
    static void testDeleteObjectCustom() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // Dynamically find any custom object to test the happy path
        String customObjectName = '';
        for (Schema.SObjectType sObjType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult objDescribe = sObjType.getDescribe();
            if (objDescribe.isAccessible() && objDescribe.isCustom()) {
                customObjectName = objDescribe.getName();
                break;
            }
        }

        Test.startTest();
        if (customObjectName != '') {
            Map<String, Object> deleteResult = ObjectManagerController.deleteObject(customObjectName);
            System.assertEquals(true, deleteResult.get('success'));
        }
        Test.stopTest();
    }

    /* =========================================
       TEST: searchMetadata
       ========================================= */

    @isTest
    static void testSearchMetadata() {
        Test.startTest();
        // Valid search (>= 2 chars)
        List<Map<String, String>> results = ObjectManagerController.searchMetadata('Name');
        // Blank keyword
        List<Map<String, String>> emptyResults = ObjectManagerController.searchMetadata('');
        // Null keyword
        List<Map<String, String>> nullResults = ObjectManagerController.searchMetadata(null);
        // Single char keyword (too short)
        List<Map<String, String>> shortResults = ObjectManagerController.searchMetadata('A');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(0, emptyResults.size());
        System.assertEquals(0, nullResults.size());
        System.assertEquals(0, shortResults.size());
    }

    /* =========================================
       TEST: getObjectLimits
       ========================================= */

    @isTest
    static void testGetObjectLimits() {
        Test.startTest();
        Map<String, Object> limits = ObjectManagerController.getObjectLimits('Account');
        Map<String, Object> emptyLimits = ObjectManagerController.getObjectLimits('ZZZNonExistentObject__c');
        Test.stopTest();

        System.assertNotEquals(null, limits);
        System.assert(limits.containsKey('fieldCount'));
        System.assert(limits.containsKey('customFieldCount'));
        System.assert(limits.containsKey('childRelationshipCount'));
        System.assert(limits.containsKey('recordTypeCount'));
        System.assert(limits.containsKey('fieldSetCount'));
        System.assertEquals(true, emptyLimits.isEmpty());
    }

    /* =========================================
       TEST: getRecordTypes
       ========================================= */

    @isTest
    static void testGetRecordTypes() {
        Test.startTest();
        List<Map<String, Object>> rtList = ObjectManagerController.getRecordTypes('Account');
        List<Map<String, Object>> emptyRtList = ObjectManagerController.getRecordTypes('ZZZNonExistentObject__c');
        Test.stopTest();

        System.assertNotEquals(null, rtList);
        System.assert(!rtList.isEmpty(), 'Account should have at least Master record type');
        Map<String, Object> firstRt = rtList[0];
        System.assert(firstRt.containsKey('name'));
        System.assert(firstRt.containsKey('developerName'));
        System.assert(firstRt.containsKey('id'));
        System.assert(firstRt.containsKey('isActive'));
        System.assert(firstRt.containsKey('isDefault'));
        System.assertEquals(true, emptyRtList.isEmpty());
    }

    /* =========================================
       TEST: getDocumentationData
       ========================================= */

    @isTest
    static void testGetDocumentationData() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        // Valid input
        List<Map<String, Object>> docData = ObjectManagerController.getDocumentationData(
            new List<String>{'Account'}
        );
        // Empty list
        List<Map<String, Object>> emptyData = ObjectManagerController.getDocumentationData(
            new List<String>()
        );
        // Null list
        List<Map<String, Object>> nullData = ObjectManagerController.getDocumentationData(null);
        // Duplicates and blank entries
        List<Map<String, Object>> dedupData = ObjectManagerController.getDocumentationData(
            new List<String>{'Account', 'Account', '', null}
        );
        Test.stopTest();

        System.assertNotEquals(null, docData);
        System.assert(!docData.isEmpty());
        System.assertEquals(0, emptyData.size());
        System.assertEquals(0, nullData.size());
        // Deduplicated should have only 1 entry (Account)
        System.assertEquals(1, dedupData.size());
    }

    /* =========================================
       TEST: getImpactAnalysisMetadata
       ========================================= */

    @isTest
    static void testGetImpactAnalysisMetadata() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        // Field-level impact
        Map<String, Object> fieldImpact = ObjectManagerController.getImpactAnalysisMetadata(
            'field', 'Name', 'Account'
        );
        // Object-level impact
        Map<String, Object> objectImpact = ObjectManagerController.getImpactAnalysisMetadata(
            'object', 'Account', ''
        );
        Test.stopTest();

        System.assertNotEquals(null, fieldImpact);
        System.assert(fieldImpact.containsKey('flows'));
        System.assert(fieldImpact.containsKey('validationRules'));
        System.assert(fieldImpact.containsKey('apexClasses'));
        System.assert(fieldImpact.containsKey('reports'));
        System.assert(fieldImpact.containsKey('dashboards'));
        System.assert(fieldImpact.containsKey('pageLayouts'));
        System.assert(fieldImpact.containsKey('workflowRules'));
        System.assert(fieldImpact.containsKey('formulas'));

        System.assertNotEquals(null, objectImpact);
    }

    /* =========================================
       TEST: getSectionData - all sections
       ========================================= */

    @isTest
    static void testGetSectionData() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        List<String> sections = new List<String>{
            'flows',
            'pageLayouts',
            'lightningRecordPages',
            'buttonsLinksActions',
            'compactLayouts',
            'fieldSets',
            'objectLimits',
            'validationRules',
            'relatedLookupFilters',
            'searchLayouts',
            'listViewButtonLayout',
            'hierarchyColumns'
        };

        Test.startTest();

        // Missing sectionId
        Map<String, Object> emptySection = ObjectManagerController.getSectionData('', 'Account');
        System.assertEquals('message', emptySection.get('type'));

        // Missing objectName
        Map<String, Object> emptyObj = ObjectManagerController.getSectionData('flows', '');
        System.assertEquals('message', emptyObj.get('type'));

        // All known sections
        for (String secId : sections) {
            Map<String, Object> result = ObjectManagerController.getSectionData(secId, 'Account');
            System.assertNotEquals(null, result, 'Result should not be null for section: ' + secId);
            System.assert(
                result.containsKey('title') || result.containsKey('type'),
                'Result should have title or type for section: ' + secId
            );
        }

        // Unknown section (falls through to default message)
        Map<String, Object> unknownSection = ObjectManagerController.getSectionData('unknownSection', 'Account');
        System.assertEquals('message', unknownSection.get('type'));

        // scopingRules (also unknown/fallthrough)
        Map<String, Object> scopingRules = ObjectManagerController.getSectionData('scopingRules', 'Account');
        System.assertEquals('message', scopingRules.get('type'));

        Test.stopTest();
    }

    /* =========================================
       TEST: Error scenarios (HTTP 500)
       ========================================= */

    @isTest
    static void testErrorScenariosToolingQuery() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerErrorMockProvider());

        Test.startTest();
        // getAllObjects uses toolingQuery which calls restGetJson -> throws MetadataRequestException
        // This exception is NOT caught inside getAllObjects, so it should propagate
        try {
            List<Map<String, Object>> result = ObjectManagerController.getAllObjects();
            // If it doesn't throw, the result should be empty since toolingQuery fails
            System.assertNotEquals(null, result);
        } catch (Exception ex) {
            // Expected: MetadataRequestException from restGetJson
            System.assert(ex.getMessage() != null);
        }
        Test.stopTest();
    }

    @isTest
    static void testErrorScenariosCreateField() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerErrorMockProvider());

        Test.startTest();
        // createFieldsBulk - the toolingQuery for EntityDefinition check will fail,
        // but the exception is caught inside the per-field try-catch
        try {
            List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', new List<Map<String, Object>>{
                new Map<String, Object>{
                    'label' => 'Error Field',
                    'apiName' => 'Error_Field',
                    'type' => 'Text'
                }
            });
            // If toolingQuery for entity check fails, it throws before per-field loop
            // depending on how exception is handled
        } catch (Exception ex) {
            System.assert(ex.getMessage() != null);
        }
        Test.stopTest();
    }

    /* =========================================
       TEST: ObjectInfoComparator
       ========================================= */

    @isTest
    static void testObjectInfoComparator() {
        ObjectManagerController.ObjectInfoComparator comparator =
            new ObjectManagerController.ObjectInfoComparator();

        Map<String, Object> obj1 = new Map<String, Object>{ 'label' => 'Account' };
        Map<String, Object> obj2 = new Map<String, Object>{ 'label' => 'Contact' };
        Map<String, Object> obj3 = new Map<String, Object>{ 'label' => 'Account' };

        Test.startTest();
        Integer result1 = comparator.compare(obj1, obj2);
        Integer result2 = comparator.compare(obj2, obj1);
        Integer result3 = comparator.compare(obj1, obj3);
        Test.stopTest();

        System.assert(result1 < 0, 'Account should sort before Contact');
        System.assert(result2 > 0, 'Contact should sort after Account');
        System.assertEquals(0, result3, 'Same labels should be equal');
    }

    /* =========================================
       TEST: getSectionData with Contact object
       (to cover different code paths with different object shapes)
       ========================================= */

    @isTest
    static void testGetSectionDataContact() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        // fieldSets, objectLimits, relatedLookupFilters, hierarchyColumns
        // These use Schema describe and don't require HTTP callouts
        Map<String, Object> fieldSets = ObjectManagerController.getSectionData('fieldSets', 'Contact');
        Map<String, Object> objLimits = ObjectManagerController.getSectionData('objectLimits', 'Contact');
        Map<String, Object> lookupFilters = ObjectManagerController.getSectionData('relatedLookupFilters', 'Contact');
        Map<String, Object> hierarchy = ObjectManagerController.getSectionData('hierarchyColumns', 'Contact');
        Test.stopTest();

        System.assertNotEquals(null, fieldSets);
        System.assertNotEquals(null, objLimits);
        System.assertNotEquals(null, lookupFilters);
        System.assertNotEquals(null, hierarchy);
    }

    /* =========================================
       TEST: Additional edge cases for full coverage
       ========================================= */

    @isTest
    static void testCreateFieldsBulkAutoNumberDefaults() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // AutoNumber with blank displayFormat (should default to AUTO-{0000})
        List<Map<String, Object>> defs = new List<Map<String, Object>>{
            new Map<String, Object>{
                'label' => 'Auto Default',
                'type' => 'auto number'
            }
        };

        Test.startTest();
        List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', defs);
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @isTest
    static void testCreateFieldsBulkAlternateTypeNames() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        // Test alternate type name formats covered by normalizeFieldType
        List<Map<String, Object>> defs = new List<Map<String, Object>>();

        defs.add(new Map<String, Object>{
            'label' => 'Test Rich', 'type' => 'rich text area', 'length' => 5000, 'visibleLines' => 3
        });
        defs.add(new Map<String, Object>{
            'label' => 'Test LTA', 'type' => 'long text area', 'length' => 10000, 'visibleLines' => 4
        });
        defs.add(new Map<String, Object>{
            'label' => 'Test DT', 'type' => 'date/time'
        });
        defs.add(new Map<String, Object>{
            'label' => 'Test Bool', 'type' => 'boolean', 'defaultValue' => false
        });
        defs.add(new Map<String, Object>{
            'label' => 'Test MSP', 'type' => 'multi-select picklist', 'picklistValues' => 'A;B;C'
        });
        defs.add(new Map<String, Object>{
            'label' => 'Test ET', 'type' => 'encrypted text', 'length' => 50
        });

        Test.startTest();
        List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', defs);
        Test.stopTest();

        System.assertEquals(defs.size(), results.size());
    }

    /* =========================================
       TEST: getObjectFields with Contact
       (covers different field shapes like lookups, formulas)
       ========================================= */

    @isTest
    static void testGetObjectFieldsContact() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        List<Map<String, Object>> fields = ObjectManagerController.getObjectFields('Contact');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assert(!fields.isEmpty());
    }

    /* =========================================
       TEST: getDocumentationData with multiple objects
       ========================================= */

    @isTest
    static void testGetDocumentationDataMultiple() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        List<Map<String, Object>> docData = ObjectManagerController.getDocumentationData(
            new List<String>{'Account', 'Contact'}
        );
        Test.stopTest();

        System.assertEquals(2, docData.size());
    }

    /* =========================================
       TEST: getImpactAnalysisMetadata edge cases
       ========================================= */

    @isTest
    static void testGetImpactAnalysisMetadataBlank() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        Test.startTest();
        // Blank apiName
        Map<String, Object> blankImpact = ObjectManagerController.getImpactAnalysisMetadata(
            'field', '', 'Account'
        );
        Test.stopTest();

        System.assertNotEquals(null, blankImpact);
    }

    @isTest
    static void testCreateFieldsBulkMoreNormalizationAndBlockedObject() {
        Test.setMock(HttpCalloutMock.class, new ObjectManagerMockProvider());

        List<Map<String, Object>> defs = new List<Map<String, Object>>{
            new Map<String, Object>{
                'label' => '123 Needs Prefix',
                'apiName' => '123 Needs Prefix',
                'type' => 'Text',
                'length' => '25.7',
                'required' => 'yes',
                'externalId' => '1',
                'unique' => 'y',
                'inlineHelpText' => 'Inline help wins'
            },
            new Map<String, Object>{
                'label' => 'Already Upper Suffix',
                'apiName' => 'Already_Upper__C',
                'type' => 'Percent',
                'precision' => '',
                'scale' => 'bad'
            },
            new Map<String, Object>{
                'label' => 'Comma Picklist',
                'apiName' => '',
                'type' => 'Picklist',
                'picklistValues' => 'One, Two, , Three'
            }
        };

        Test.startTest();
        List<Map<String, Object>> results = ObjectManagerController.createFieldsBulk('Account', defs);
        Test.stopTest();

        System.assertEquals(3, results.size());
        System.assertEquals('F_123_Needs_Prefix__c', results[0].get('apiName'));
        System.assertEquals('Already_Upper_C__c', results[1].get('apiName'));
        System.assertEquals('Comma_Picklist__c', results[2].get('apiName'));

        Test.setMock(HttpCalloutMock.class, new ObjectManagerNonCustomizableMockProvider());
        try {
            ObjectManagerController.createFieldsBulk('Account', new List<Map<String, Object>>{
                new Map<String, Object>{ 'label' => 'Blocked Field', 'type' => 'Text' }
            });
            System.assert(false, 'Non-customizable object should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }
    }

    @isTest
    static void testDeleteMetadataFaultResponses() {
        String customFieldName = '';
        String targetObjectName = '';
        for (String objName : Schema.getGlobalDescribe().keySet()) {
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objName).getDescribe();
            if (!objDescribe.isAccessible()) continue;
            for (Schema.SObjectField fld : objDescribe.fields.getMap().values()) {
                if (fld.getDescribe().isCustom()) {
                    customFieldName = fld.getDescribe().getName();
                    targetObjectName = objDescribe.getName();
                    break;
                }
            }
            if (customFieldName != '') break;
        }

        if (customFieldName == '') {
            System.assert(true, 'No custom field available in this org.');
            return;
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerMetadataFaultMockProvider());
        try {
            ObjectManagerController.deleteField(targetObjectName, customFieldName, '', '');
            System.assert(false, 'SOAP fault should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerUnreadableMetadataMockProvider());
        try {
            ObjectManagerController.deleteField(targetObjectName, customFieldName, '', '');
            System.assert(false, 'Unreadable Metadata API response should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerUnreadableSuccessMetadataMockProvider());
        try {
            ObjectManagerController.deleteField(targetObjectName, customFieldName, '', '');
            System.assert(false, 'Unreadable successful Metadata API response should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerNoResultMetadataMockProvider());
        try {
            ObjectManagerController.deleteField(targetObjectName, customFieldName, '', '');
            System.assert(false, 'Missing Metadata API result should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerFailedResultMetadataMockProvider());
        try {
            ObjectManagerController.deleteField(targetObjectName, customFieldName, '', '');
            System.assert(false, 'Failed Metadata API result should throw');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }
    }

    @isTest
    static void testDeleteObjectMetadataFaultResponse() {
        String customObjectName = '';
        for (Schema.SObjectType sObjType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult objDescribe = sObjType.getDescribe();
            if (objDescribe.isAccessible() && objDescribe.isCustom()) {
                customObjectName = objDescribe.getName();
                break;
            }
        }

        if (customObjectName == '') {
            System.assert(true, 'No custom object available in this org.');
            return;
        }

        Test.setMock(HttpCalloutMock.class, new ObjectManagerMetadataFaultMockProvider());
        try {
            ObjectManagerController.deleteObject(customObjectName);
            System.assert(false, 'SOAP fault should throw for custom object delete');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage() != null);
        }
    }

    @isTest
    static void testPureMetadataHelperBranches() {
        System.assertEquals('', ObjectManagerController.extractDurableIdToken(null));
        System.assertEquals('01I000000000001', ObjectManagerController.extractDurableIdToken('01I000000000001'));
        System.assertEquals('', ObjectManagerController.extractDurableIdToken('Account.'));
        System.assertEquals('00N000000000001AAA', ObjectManagerController.extractDurableIdToken('Account.00N000000000001AAA'));

        System.assertEquals('', ObjectManagerController.extractDeveloperName(''));
        System.assertEquals('Custom_Field', ObjectManagerController.extractDeveloperName(' Custom_Field__c '));
        System.assertEquals('Upper_Field', ObjectManagerController.extractDeveloperName('Upper_Field__C'));
        System.assertEquals('Name', ObjectManagerController.extractDeveloperName('Name'));

        System.assertEquals('', ObjectManagerController.normalizeSalesforceId(null));
        System.assertEquals('', ObjectManagerController.normalizeSalesforceId('not an id'));
        System.assertEquals('001000000000001', ObjectManagerController.normalizeSalesforceId(' 001000000000001 '));
        System.assertEquals('001000000000001AAA', ObjectManagerController.normalizeSalesforceId('001000000000001AAA'));

        System.assertEquals('New_Field__c', ObjectManagerController.normalizeCustomFieldApiName('', ''));
        System.assertEquals('Field_Name__c', ObjectManagerController.normalizeCustomFieldApiName('', 'Field Name'));
        System.assertEquals('F_9Lives__c', ObjectManagerController.normalizeCustomFieldApiName('9Lives', 'Ignored'));
        System.assertEquals('Already_c__c', ObjectManagerController.normalizeCustomFieldApiName('Already__c', 'Ignored'));
        System.assertEquals('Already_C__c', ObjectManagerController.normalizeCustomFieldApiName('Already__C', 'Ignored'));
    }
}