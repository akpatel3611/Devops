public with sharing class BulkMetadataService {

    public class ObjectOption implements Comparable {
        public String label;
        public String value;

        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }

        public Integer compareTo(Object compareTo) {
            ObjectOption other = (ObjectOption) compareTo;
            if (this.label == other.label) return 0;
            if (this.label > other.label) return 1;
            return -1;
        }
    }

    public class DeploymentResult {
        @AuraEnabled public Boolean overallSuccess;
        @AuraEnabled public String overallMessage;
        @AuraEnabled public ObjectDeploymentResult objectResult;
        @AuraEnabled public List<FieldDeploymentResult> fieldResults;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
    }

    public class ObjectDeploymentResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String message;
    }

    public class FieldDeploymentResult {
        @AuraEnabled public String rowKey;
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String status;
    }

    public class MetadataCallResult {
        public Boolean success;
        public String message;
    }

    public class ProfileFlsResult {
        @AuraEnabled public String profileLabel;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer fieldsApplied;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjects() {
        try {
            List<ObjectOption> sortedOptions = new List<ObjectOption>();
            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

            for (String objName : gd.keySet()) {
                Schema.DescribeSObjectResult describe = gd.get(objName).getDescribe();
                if (describe.isCreateable() && describe.isUpdateable() && !describe.isCustomSetting() && !describe.getName().endsWith('__mdt')) {
                    sortedOptions.add(new ObjectOption(describe.getLabel() + ' (' + describe.getName() + ')', describe.getName()));
                }
            }

            sortedOptions.sort();

            List<Map<String, String>> options = new List<Map<String, String>>();
            for (ObjectOption opt : sortedOptions) {
                Map<String, String> obj = new Map<String, String>();
                obj.put('label', opt.label);
                obj.put('value', opt.value);
                options.add(obj);
            }
            return options;
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectFields(String objectApiName) {
        try {
            List<Map<String, String>> fields = new List<Map<String, String>>();
            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

            if (gd.containsKey(objectApiName)) {
                Schema.DescribeSObjectResult describe = gd.get(objectApiName).getDescribe();
                Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
                for (Schema.SObjectField f : fieldMap.values()) {
                    Schema.DescribeFieldResult fDescribe = f.getDescribe();
                    if (fDescribe.isCreateable() && !fDescribe.isCalculated()) {
                        Boolean isRequired = !fDescribe.isNillable() && !fDescribe.isDefaultedOnCreate();
                        Boolean isNameField = fDescribe.isNameField() && fDescribe.isCreateable();
                        Boolean isCustom = fDescribe.isCustom();

                        if (isRequired || isNameField || isCustom) {
                            Map<String, String> field = new Map<String, String>();
                            field.put('value', fDescribe.getName());
                            field.put('label', fDescribe.getLabel());
                            field.put('type', fDescribe.getType().name());
                            field.put('isRequired', String.valueOf(isRequired));
                            fields.add(field);
                        }
                    }
                }
            }
            return fields;
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProfiles() {
        try {
            List<Map<String, String>> profileList = new List<Map<String, String>>();
            for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name LIMIT 200]) {
                Map<String, String> profileMap = new Map<String, String>();
                profileMap.put('label', p.Name);
                profileMap.put('value', p.Name);
                profileMap.put('metadataName', getProfileMetadataName(p.Name));
                profileList.add(profileMap);
            }
            return profileList;
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<ProfileFlsResult> assignProfileFls(
        List<ProfileFlsAssignment> assignments,
        List<String> successfulFieldApiNames
    ) {
        try {
            List<ProfileFlsResult> results = new List<ProfileFlsResult>();
            if (assignments == null || assignments.isEmpty()
                || successfulFieldApiNames == null || successfulFieldApiNames.isEmpty()) {
                return results;
            }
            for (ProfileFlsAssignment assignment : assignments) {
                ProfileFlsResult flsResult = new ProfileFlsResult();
                flsResult.profileLabel = assignment.profileLabel;
                flsResult.fieldsApplied = successfulFieldApiNames.size();

                Boolean readable = assignment.readAll == true;
                Boolean editable = assignment.editAll == true && readable;

                List<String> metadata = new List<String>();
                metadata.add('<met:metadata xsi:type="met:Profile">');
                metadata.add('<met:fullName>' + escapeXml(assignment.profileMetadataName) + '</met:fullName>');

                for (String fieldApiName : successfulFieldApiNames) {
                    metadata.add('<met:fieldPermissions>');
                    metadata.add('<met:field>' + escapeXml(fieldApiName) + '</met:field>');
                    metadata.add('<met:readable>' + (readable ? 'true' : 'false') + '</met:readable>');
                    metadata.add('<met:editable>' + (editable ? 'true' : 'false') + '</met:editable>');
                    metadata.add('</met:fieldPermissions>');
                }

                metadata.add('</met:metadata>');

                MetadataCallResult callResult = updateMetadata(metadata);
                flsResult.success = callResult.success;
                flsResult.message = callResult.success
                    ? 'FLS applied to ' + successfulFieldApiNames.size() + ' field(s) successfully.'
                    : callResult.message;
                results.add(flsResult);
            }
            return results;
        } catch (CalloutException ce) {
            throw newAuraHandledException('FLS callout failed: ' + ce.getMessage()
                + '. Ensure the Org Domain is in Remote Site Settings.');
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static DeploymentResult deploySchema(ObjectDefinition objDef, List<FieldDefinition> fields) {
        try {
            DeploymentResult result = initializeDeploymentResult(fields);
            List<String> validationErrors = validateDeploymentRequest(objDef, fields);
            if (!validationErrors.isEmpty()) {
                result.overallSuccess = false;
                result.overallMessage = String.join(validationErrors, ' ');
                markAllFieldsFailed(result.fieldResults, 'Validation Error', result.overallMessage);
                result.failureCount = result.fieldResults.size();
                result.successCount = 0;
                return result;
            }

            String targetObjectApiName = '';
            if (objDef != null && String.isNotBlank(objDef.apiName)) {
                targetObjectApiName = ensureCustomSuffix(objDef.apiName);
                MetadataCallResult objectCallResult = createCustomObject(objDef, targetObjectApiName);
                result.objectResult = new ObjectDeploymentResult();
                result.objectResult.objectApiName = targetObjectApiName;
                result.objectResult.success = objectCallResult.success;
                result.objectResult.message = objectCallResult.message;

                if (!objectCallResult.success) {
                    String objectError = 'Object creation failed: ' + objectCallResult.message;
                    markAllFieldsFailed(result.fieldResults, 'Skipped', objectError);
                    result.overallSuccess = false;
                    result.overallMessage = objectError;
                    result.failureCount = result.fieldResults.size();
                    result.successCount = 0;
                    return result;
                }

                MetadataCallResult tabCallResult = createCustomTab(targetObjectApiName, objDef.theme);
                if (!tabCallResult.success && result.objectResult != null) {
                    result.objectResult.message += ' Tab creation issue: ' + tabCallResult.message;
                }
            }

            Integer successCount = 0;
            Integer failureCount = 0;
            for (Integer index = 0; index < fields.size(); index++) {
                FieldDefinition field = fields[index];
                FieldDeploymentResult fieldResult = result.fieldResults[index];
                String parentObject = String.isNotBlank(targetObjectApiName)
                    ? targetObjectApiName
                    : field.relatedObject;
                fieldResult.targetObject = parentObject;

                MetadataCallResult fieldCallResult = createCustomField(parentObject, field);
                fieldResult.success = fieldCallResult.success;
                fieldResult.message = fieldCallResult.message;
                fieldResult.status = fieldCallResult.success ? 'Success' : 'Error';

                if (fieldCallResult.success) {
                    successCount++;
                } else {
                    failureCount++;
                }
            }

            result.successCount = successCount;
            result.failureCount = failureCount;
            result.overallSuccess = failureCount == 0 && (result.objectResult == null || result.objectResult.success);
            if (result.overallSuccess) {
                result.overallMessage = 'Schema deployed successfully.';
            } else if (successCount > 0) {
                result.overallMessage = successCount + ' field(s) deployed successfully and ' + failureCount + ' field(s) failed.';
            } else {
                result.overallMessage = 'Schema deployment failed.';
            }

            return result;
        } catch (CalloutException ce) {
            throw newAuraHandledException('Callout failed: ' + ce.getMessage() + '. Please ensure the Salesforce Org Domain is added to Remote Site Settings, or a Named Credential is set up.');
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void insertRecords(String objectApiName, List<Map<String, Object>> records) {
        try {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }

            Schema.DescribeSObjectResult objectDescribe = sObjectType.getDescribe();
            if (!objectDescribe.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create records for ' + objectApiName + '.');
            }

            Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
            List<SObject> sobjectsToInsert = new List<SObject>();

            for (Map<String, Object> recordMap : records) {
                SObject newObj = sObjectType.newSObject();
                for (String fieldName : recordMap.keySet()) {
                    if (fieldMap.containsKey(fieldName)) {
                        Schema.DescribeFieldResult fDescribe = fieldMap.get(fieldName).getDescribe();
                        if (!fDescribe.isCreateable()) {
                            continue;
                        }

                        Object value = recordMap.get(fieldName);
                        if (value != null && String.isNotBlank(String.valueOf(value))) {
                            Schema.DisplayType dType = fDescribe.getType();
                            if (dType == Schema.DisplayType.Integer) {
                                newObj.put(fieldName, Integer.valueOf(String.valueOf(value)));
                            } else if (dType == Schema.DisplayType.Double || dType == Schema.DisplayType.Currency || dType == Schema.DisplayType.Percent) {
                                newObj.put(fieldName, Decimal.valueOf(String.valueOf(value)));
                            } else if (dType == Schema.DisplayType.Boolean) {
                                newObj.put(fieldName, Boolean.valueOf(String.valueOf(value)));
                            } else if (dType == Schema.DisplayType.Date) {
                                newObj.put(fieldName, Date.valueOf(String.valueOf(value)));
                            } else if (dType == Schema.DisplayType.DateTime) {
                                newObj.put(fieldName, parseDateTimeValue(String.valueOf(value)));
                            } else {
                                newObj.put(fieldName, String.valueOf(value));
                            }
                        }
                    }
                }
                sobjectsToInsert.add(newObj);
            }

            insert sobjectsToInsert;
        } catch (Exception e) {
            throw newAuraHandledException(e.getMessage());
        }
    }

    private static DeploymentResult initializeDeploymentResult(List<FieldDefinition> fields) {
        DeploymentResult result = new DeploymentResult();
        result.overallSuccess = false;
        result.overallMessage = 'Schema deployment did not start.';
        result.objectResult = null;
        result.fieldResults = new List<FieldDeploymentResult>();
        result.successCount = 0;
        result.failureCount = 0;

        if (fields == null) {
            return result;
        }

        for (FieldDefinition field : fields) {
            FieldDeploymentResult fieldResult = new FieldDeploymentResult();
            fieldResult.rowKey = field.rowKey;
            fieldResult.label = field.label;
            fieldResult.apiName = ensureCustomSuffix(field.apiName);
            fieldResult.dataType = field.dataType;
            fieldResult.targetObject = field.relatedObject;
            fieldResult.success = false;
            fieldResult.message = 'Pending deployment.';
            fieldResult.status = 'Pending';
            result.fieldResults.add(fieldResult);
        }

        return result;
    }

    private static List<String> validateDeploymentRequest(ObjectDefinition objDef, List<FieldDefinition> fields) {
        List<String> errors = new List<String>();
        if (fields == null || fields.isEmpty()) {
            errors.add('Please define at least one field before deploying.');
            return errors;
        }

        Set<String> seenFieldApiNames = new Set<String>();
        for (FieldDefinition field : fields) {
            if (String.isBlank(field.label)) {
                errors.add('Each field requires a label.');
                break;
            }
            if (String.isBlank(field.apiName)) {
                errors.add('Each field requires an API name.');
                break;
            }

            String normalizedFieldApiName = ensureCustomSuffix(field.apiName).toLowerCase();
            if (seenFieldApiNames.contains(normalizedFieldApiName)) {
                errors.add('Duplicate field API names are not allowed: ' + ensureCustomSuffix(field.apiName));
                break;
            }
            seenFieldApiNames.add(normalizedFieldApiName);

            if ((field.dataType == 'Lookup' || field.dataType == 'ExternalLookup') && String.isBlank(field.relatedObject) && (objDef == null || String.isBlank(objDef.apiName))) {
                errors.add('Lookup fields require a related object.');
                break;
            }
            if (field.dataType == 'Formula' && String.isBlank(field.formula)) {
                errors.add('Formula fields require a formula expression.');
                break;
            }
            if ((field.dataType == 'Picklist' || field.dataType == 'MultiselectPicklist') && String.isBlank(field.picklistValues)) {
                errors.add('Picklist fields require at least one value.');
                break;
            }
            if (field.dataType == 'Summary') {
                errors.add('Roll-Up Summary fields are not supported in bulk deployment yet.');
                break;
            }
        }

        if (objDef != null && String.isNotBlank(objDef.apiName)) {
            if (String.isBlank(objDef.label) || String.isBlank(objDef.pluralLabel)) {
                errors.add('New object deployment requires both object label and plural label.');
            }
        }

        return errors;
    }

    private static void markAllFieldsFailed(List<FieldDeploymentResult> fieldResults, String status, String message) {
        for (FieldDeploymentResult fieldResult : fieldResults) {
            fieldResult.success = false;
            fieldResult.status = status;
            fieldResult.message = message;
        }
    }

    private static MetadataCallResult createCustomObject(ObjectDefinition objDef, String objectApiName) {
        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomObject">');
        metadata.add('<met:fullName>' + escapeXml(objectApiName) + '</met:fullName>');
        metadata.add('<met:label>' + escapeXml(objDef.label) + '</met:label>');
        metadata.add('<met:pluralLabel>' + escapeXml(objDef.pluralLabel) + '</met:pluralLabel>');
        metadata.add('<met:deploymentStatus>Deployed</met:deploymentStatus>');
        metadata.add('<met:sharingModel>ReadWrite</met:sharingModel>');
        metadata.add('<met:nameField>');
        metadata.add('<met:label>' + escapeXml(objDef.nameFieldLabel) + '</met:label>');
        metadata.add('<met:type>' + escapeXml(objDef.nameFieldType) + '</met:type>');
        if (objDef.nameFieldType == 'AutoNumber') {
            metadata.add('<met:displayFormat>OBJ-{0000}</met:displayFormat>');
        }
        metadata.add('</met:nameField>');
        metadata.add('</met:metadata>');
        return createMetadata(metadata);
    }

    private static MetadataCallResult createCustomTab(String objectApiName, String theme) {
        if (String.isBlank(theme)) {
            MetadataCallResult skipped = new MetadataCallResult();
            skipped.success = true;
            skipped.message = 'Object created successfully.';
            return skipped;
        }

        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomTab">');
        metadata.add('<met:fullName>' + escapeXml(objectApiName) + '</met:fullName>');
        metadata.add('<met:motif>' + escapeXml(theme) + '</met:motif>');
        metadata.add('<met:customObject>true</met:customObject>');
        metadata.add('</met:metadata>');
        return createMetadata(metadata);
    }

    private static MetadataCallResult createCustomField(String parentObject, FieldDefinition field) {
        if (String.isBlank(parentObject)) {
            MetadataCallResult missingParent = new MetadataCallResult();
            missingParent.success = false;
            missingParent.message = 'Target object could not be determined for this field.';
            return missingParent;
        }

        String fieldApiName = ensureCustomSuffix(field.apiName);
        String actualType = field.dataType == 'Formula' && String.isNotBlank(field.formulaType)
            ? field.formulaType
            : field.dataType;

        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomField">');
        metadata.add('<met:fullName>' + escapeXml(parentObject + '.' + fieldApiName) + '</met:fullName>');
        metadata.add('<met:label>' + escapeXml(field.label) + '</met:label>');
        metadata.add('<met:type>' + escapeXml(actualType) + '</met:type>');

        Boolean isRequired = field.isRequired == true
            && field.dataType != 'AutoNumber'
            && field.dataType != 'Summary'
            && field.dataType != 'Formula';
        metadata.add('<met:required>' + (isRequired ? 'true' : 'false') + '</met:required>');

        if (field.dataType == 'Formula' && String.isNotBlank(field.formula)) {
            metadata.add('<met:formula>' + escapeXml(field.formula) + '</met:formula>');
        }

        if (actualType == 'Text' || actualType == 'TextArea') {
            metadata.add('<met:length>' + String.valueOf(field.length != null ? field.length : 255) + '</met:length>');
        } else if (actualType == 'Number' || actualType == 'Percent' || actualType == 'Currency') {
            metadata.add('<met:precision>18</met:precision>');
            metadata.add('<met:scale>' + String.valueOf(field.scale != null ? field.scale : 2) + '</met:scale>');
        } else if (actualType == 'Checkbox') {
            metadata.add('<met:defaultValue>false</met:defaultValue>');
        } else if (actualType == 'Lookup' || actualType == 'ExternalLookup') {
            String relationshipName = buildRelationshipName(parentObject, fieldApiName);
            metadata.add('<met:referenceTo>' + escapeXml(field.relatedObject) + '</met:referenceTo>');
            metadata.add('<met:relationshipName>' + escapeXml(relationshipName) + '</met:relationshipName>');
            metadata.add('<met:relationshipLabel>' + escapeXml(buildRelationshipLabel(parentObject)) + '</met:relationshipLabel>');
        } else if (actualType == 'LongTextArea') {
            metadata.add('<met:length>32768</met:length>');
            metadata.add('<met:visibleLines>' + String.valueOf(field.visibleLines != null ? field.visibleLines : 3) + '</met:visibleLines>');
        } else if (actualType == 'Html') {
            metadata.add('<met:length>' + String.valueOf(field.length != null ? field.length : 32768) + '</met:length>');
            metadata.add('<met:visibleLines>' + String.valueOf(field.visibleLines != null ? field.visibleLines : 10) + '</met:visibleLines>');
        } else if (actualType == 'EncryptedText') {
            metadata.add('<met:length>' + String.valueOf(field.length != null ? field.length : 175) + '</met:length>');
            metadata.add('<met:maskChar>asterisk</met:maskChar>');
            metadata.add('<met:maskType>all</met:maskType>');
        } else if (actualType == 'Location') {
            metadata.add('<met:displayLocationInDecimal>true</met:displayLocationInDecimal>');
            metadata.add('<met:scale>' + String.valueOf(field.scale != null ? field.scale : 2) + '</met:scale>');
        } else if (actualType == 'AutoNumber') {
            metadata.add('<met:displayFormat>' + escapeXml(String.isNotBlank(field.displayFormat) ? field.displayFormat : 'AN-{0000}') + '</met:displayFormat>');
            metadata.add('<met:startingNumber>' + String.valueOf(field.startingNumber != null ? field.startingNumber : 1) + '</met:startingNumber>');
        } else if (actualType == 'Picklist' || actualType == 'MultiselectPicklist') {
            metadata.add('<met:valueSet>');
            metadata.add('<met:valueSetDefinition>');
            metadata.add('<met:sorted>false</met:sorted>');

            String values = String.isNotBlank(field.picklistValues) ? field.picklistValues : 'Value 1, Value 2, Value 3';
            for (String picklistValue : values.split('[,\\n]')) {
                String trimmedValue = picklistValue.trim();
                if (String.isNotBlank(trimmedValue)) {
                    metadata.add('<met:value>');
                    metadata.add('<met:fullName>' + escapeXml(trimmedValue) + '</met:fullName>');
                    metadata.add('<met:label>' + escapeXml(trimmedValue) + '</met:label>');
                    metadata.add('<met:default>false</met:default>');
                    metadata.add('</met:value>');
                }
            }

            metadata.add('</met:valueSetDefinition>');
            metadata.add('</met:valueSet>');
            if (actualType == 'MultiselectPicklist') {
                metadata.add('<met:visibleLines>' + String.valueOf(field.visibleLines != null ? field.visibleLines : 4) + '</met:visibleLines>');
            }
        }

        metadata.add('</met:metadata>');
        return createMetadata(metadata);
    }

    private static MetadataCallResult createMetadata(List<String> metadataSegments) {
        return executeMetadataOperation(metadataSegments, 'createMetadata');
    }

    private static MetadataCallResult updateMetadata(List<String> metadataSegments) {
        return executeMetadataOperation(metadataSegments, 'updateMetadata');
    }

    private static MetadataCallResult executeMetadataOperation(List<String> metadataSegments, String operationName) {
        String endpoint = Url.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/67.0';
        String soapBody = buildSoapEnvelope(metadataSegments, operationName);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', operationName);
        req.setBody(soapBody);

        HttpResponse res = new Http().send(req);
        MetadataCallResult callResult = new MetadataCallResult();
        String responseBody = res.getBody();
        if (res.getStatusCode() == 200 && !responseBody.contains('<success>false</success>')) {
            callResult.success = true;
            callResult.message = parseSuccessMessage(responseBody);
        } else {
            callResult.success = false;
            callResult.message = parseSoapErrors(responseBody);
        }
        return callResult;
    }

    private static String getSessionId() {
        if (Test.isRunningTest()) {
            return 'MockSessionId';
        }
        try {
            PageReference pageRef = new PageReference('/apex/SessionIdPage');
            String content = pageRef.getContent().toString();

            Integer startIdx = content.indexOf('Session_ID_Start');
            Integer endIdx = content.indexOf('Session_ID_End');
            if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
                return content.substring(startIdx + 16, endIdx).trim();
            }
        } catch (Exception e) {
            // Fallback
        }
        return UserInfo.getSessionId();
    }

    private static String buildSoapEnvelope(List<String> metadataSegments, String operationName) {
        String soap = '';
        soap += '<?xml version="1.0" encoding="utf-8"?>';
        soap += '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        soap += '<soapenv:Header>';
        soap += '<met:SessionHeader><met:sessionId>' + escapeXml(getSessionId()) + '</met:sessionId></met:SessionHeader>';
        soap += '</soapenv:Header>';
        soap += '<soapenv:Body>';
        soap += '<met:' + operationName + '>';
        soap += String.join(metadataSegments, '');
        soap += '</met:' + operationName + '>';
        soap += '</soapenv:Body>';
        soap += '</soapenv:Envelope>';
        return soap;
    }

    private static String parseSoapErrors(String soapBody) {
        List<String> errorMessages = new List<String>();

        Integer lastIndex = 0;
        while (true) {
            Integer msgStart = soapBody.indexOf('<message>', lastIndex);
            if (msgStart == -1) break;
            Integer msgEnd = soapBody.indexOf('</message>', msgStart);
            if (msgEnd == -1) break;
            String msg = soapBody.substring(msgStart + 9, msgEnd);
            errorMessages.add(msg);
            lastIndex = msgEnd;
        }

        if (errorMessages.isEmpty()) {
            Integer faultStart = soapBody.indexOf('<faultstring>');
            if (faultStart != -1) {
                Integer faultEnd = soapBody.indexOf('</faultstring>', faultStart);
                if (faultEnd != -1) {
                    return soapBody.substring(faultStart + 13, faultEnd);
                }
            }
            return 'Deployment failed. Please check your metadata values.';
        }
        return String.join(errorMessages, '; ');
    }

    private static String parseSuccessMessage(String soapBody) {
        Integer fullNameStart = soapBody.indexOf('<fullName>');
        Integer fullNameEnd = soapBody.indexOf('</fullName>', fullNameStart);
        if (fullNameStart != -1 && fullNameEnd != -1) {
            return soapBody.substring(fullNameStart + 10, fullNameEnd) + ' created successfully.';
        }
        return 'Created successfully.';
    }

    private static String getProfileMetadataName(String profileName) {
        Map<String, String> standardProfiles = new Map<String, String>{
            'System Administrator' => 'Admin',
            'Standard User'       => 'Standard',
            'Read Only'           => 'ReadOnly',
            'Solution Manager'    => 'SolutionManager',
            'Contract Manager'    => 'ContractManager',
            'Marketing User'      => 'MarketingUser',
            'Chatter External User'  => 'ChatterExternal',
            'Chatter Free User'      => 'ChatterFree',
            'Chatter Moderator User' => 'ChatterModerator',
            'Force.com - Free User'  => 'FreeUser',
            'Minimum Access - Salesforce' => 'MinimumAccess',
            'Identity User'       => 'IdentityUser',
            'External Identity'   => 'ExternalIdentityUser'
        };
        return standardProfiles.containsKey(profileName)
            ? standardProfiles.get(profileName)
            : profileName;
    }

    private static String escapeXml(String value) {
        return value == null ? '' : value.escapeXml();
    }

    private static String ensureCustomSuffix(String apiName) {
        if (String.isBlank(apiName)) {
            return '';
        }
        return apiName.endsWith('__c') ? apiName : apiName + '__c';
    }

    private static String buildRelationshipName(String parentObject, String fieldApiName) {
        String relationshipName = parentObject.replace('__c', '') + '_' + fieldApiName.replace('__c', '') + 's';
        return relationshipName.length() > 40 ? relationshipName.substring(0, 40) : relationshipName;
    }

    private static String buildRelationshipLabel(String parentObject) {
        String relationshipLabel = parentObject.replace('__c', '') + 's';
        return relationshipLabel.length() > 40 ? relationshipLabel.substring(0, 40) : relationshipLabel;
    }

    private static DateTime parseDateTimeValue(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        String normalized = rawValue.replace('T', ' ');
        if (normalized.endsWith('Z')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (normalized.contains('.')) {
            normalized = normalized.substring(0, normalized.indexOf('.'));
        }
        return DateTime.valueOf(normalized);
    }

    private static AuraHandledException newAuraHandledException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }
}