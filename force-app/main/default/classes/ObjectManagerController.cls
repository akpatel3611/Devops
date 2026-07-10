public with sharing class ObjectManagerController {

    private static final Integer GLOBAL_SEARCH_RESULT_LIMIT = 25;
    private static final String API_VERSION = 'v66.0';
    private static final String SALESFORCE_NAMED_CREDENTIAL = 'SalesforceSelf';

    private class MetadataRequestException extends Exception {
    }

    /* =========================================
       GET ALL OBJECTS
       ========================================= */

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAllObjects() {

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        List<Map<String, Object>> entityRows =
            toolingQuery(
                'SELECT QualifiedApiName, IsCustomizable, IsCustomSetting, ' +
                'IsDeprecatedAndHidden FROM EntityDefinition ' +
                'WHERE IsCustomizable = true ' +
                'AND IsCustomSetting = false ' +
                'AND IsDeprecatedAndHidden = false'
            );

        Set<String> eligibleObjectNames = new Set<String>();
        for (Map<String, Object> entityRow : entityRows) {
            String objectName =
                getString(entityRow, 'QualifiedApiName', '');

            if (!String.isBlank(objectName)) {
                eligibleObjectNames.add(objectName);
            }
        }

        List<Map<String, Object>> objects =
            new List<Map<String, Object>>();

        for (String objName : eligibleObjectNames) {

            if (!globalMap.containsKey(objName)) {
                continue;
            }

            Schema.DescribeSObjectResult objDescribe =
                globalMap.get(objName).getDescribe();

            if (shouldShowInObjectManager(objDescribe)) {

                Map<String, Object> objectInfo =
                    new Map<String, Object>();

                objectInfo.put(
                    'apiName',
                    objDescribe.getName()
                );

                objectInfo.put(
                    'label',
                    objDescribe.getLabel()
                );

                objectInfo.put(
                    'isCustom',
                    objDescribe.isCustom()
                );

                objectInfo.put(
                    'typeLabel',
                    objDescribe.isCustom()
                        ? 'Custom'
                        : 'Standard'
                );

                objects.add(objectInfo);

            }
        }

        objects.sort(new ObjectInfoComparator());

        return objects;

    }

    private static Boolean
    shouldShowInObjectManager(
        Schema.DescribeSObjectResult objDescribe
    ) {

        return objDescribe.isAccessible();

    }

    public class ObjectInfoComparator
    implements Comparator<Map<String, Object>> {

        public Integer compare(
            Map<String, Object> firstObject,
            Map<String, Object> secondObject
        ) {

            String firstLabel =
                String.valueOf(firstObject.get('label'));

            String secondLabel =
                String.valueOf(secondObject.get('label'));

            return firstLabel
                .toLowerCase()
                .compareTo(secondLabel.toLowerCase());

        }

    }

    /* =========================================
       GET OBJECT DETAILS
       ========================================= */

    @AuraEnabled(cacheable=true)
    public static Map<String, Object>
    getObjectDetails(String objectName) {

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return new Map<String, Object>();

        }

        Schema.DescribeSObjectResult objDescribe =
            globalMap.get(objectName).getDescribe();

        Map<String, Object> details =
            new Map<String, Object>();

        details.put(
            'label',
            objDescribe.getLabel()
        );

        details.put(
            'pluralLabel',
            objDescribe.getLabelPlural()
        );

        details.put(
            'apiName',
            objDescribe.getName()
        );

        details.put(
            'keyPrefix',
            objDescribe.getKeyPrefix()
        );

        details.put(
            'isCustom',
            objDescribe.isCustom()
        );

        details.put(
            'isQueryable',
            objDescribe.isQueryable()
        );

        details.put(
            'isCreateable',
            objDescribe.isCreateable()
        );

        details.put(
            'isUpdateable',
            objDescribe.isUpdateable()
        );

        details.put(
            'isDeletable',
            objDescribe.isDeletable()
        );

        return details;

    }

    /* =========================================
       GET OBJECT FIELDS
       ========================================= */

   @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>>
getObjectFields(String objectName) {

    List<Map<String, Object>> fieldList =
        new List<Map<String, Object>>();

    Map<String, Schema.SObjectType> globalMap =
        Schema.getGlobalDescribe();

    if (!globalMap.containsKey(objectName)) {

        return fieldList;

    }

    Schema.DescribeSObjectResult objDescribe =
        globalMap.get(objectName).getDescribe();

    Map<String, String> fieldDurableIdsByApiName =
        getFieldDurableIdsByApiName(objectName);
    Map<String, String> customFieldIdsByApiName =
        getCustomFieldIdsByApiName(objectName);

    Map<String, Schema.SObjectField> fieldMap =
        objDescribe.fields.getMap();

    List<String> sortedFieldNames =
        new List<String>();

    sortedFieldNames.addAll(fieldMap.keySet());

    sortedFieldNames.sort();

    for (String fieldName : sortedFieldNames) {

        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldName).getDescribe();

        Map<String, Object> fieldInfo =
            new Map<String, Object>();

        fieldInfo.put(
            'label',
            fieldDescribe.getLabel()
        );

        fieldInfo.put(
            'apiName',
            fieldDescribe.getName()
        );

        fieldInfo.put(
            'durableId',
            fieldDurableIdsByApiName.get(fieldDescribe.getName())
        );

        fieldInfo.put(
            'customFieldId',
            customFieldIdsByApiName.get(fieldDescribe.getName())
        );

        fieldInfo.put(
            'dataType',
            String.valueOf(
                fieldDescribe.getType()
            )
        );

        fieldInfo.put(
            'isRequired',
            !fieldDescribe.isNillable()
        );

        fieldInfo.put(
            'isExternalId',
            fieldDescribe.isExternalId()
        );

        fieldInfo.put(
            'isCustom',
            fieldDescribe.isCustom()
        );

        fieldList.add(fieldInfo);

    }

    return fieldList;

}

    private static Map<String, String>
    getFieldDurableIdsByApiName(String objectName) {

        Map<String, String> durableIdsByApiName =
            new Map<String, String>();

        try {

            List<SObject> fieldDefinitionRows =
                Database.query(
                    'SELECT QualifiedApiName, DurableId FROM FieldDefinition ' +
                    'WHERE EntityDefinition.QualifiedApiName = \'' +
                    escapeSoql(objectName) +
                    '\''
                );

            for (SObject row : fieldDefinitionRows) {
                String apiName =
                    row.get('QualifiedApiName') == null
                        ? ''
                        : String.valueOf(row.get('QualifiedApiName'));
                String durableId =
                    row.get('DurableId') == null
                        ? ''
                        : String.valueOf(row.get('DurableId'));

                if (!String.isBlank(apiName)) {
                    durableIdsByApiName.put(apiName, durableId);

                    Integer separatorIndex =
                        apiName.lastIndexOf('.');
                    if (separatorIndex >= 0
                        && separatorIndex + 1 < apiName.length()) {
                        durableIdsByApiName.put(
                            apiName.substring(separatorIndex + 1),
                            durableId
                        );
                    }
                }
            }

        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to fetch field durable ids for object ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return durableIdsByApiName;

    }

    private static Map<String, String>
    getCustomFieldIdsByApiName(String objectName) {

        Map<String, String> customFieldIdsByApiName =
            new Map<String, String>();

        String entityDefinitionId =
            getEntityDefinitionId(objectName);

        if (String.isBlank(entityDefinitionId)) {
            return customFieldIdsByApiName;
        }

        String whereClause =
            'WHERE (TableEnumOrId = \'' +
            escapeSoql(entityDefinitionId) +
            '\'';

        if (entityDefinitionId != objectName) {
            whereClause +=
                ' OR TableEnumOrId = \'' + escapeSoql(objectName) + '\'';
        }

        whereClause += ')';

        List<Map<String, Object>> customFieldRows =
            toolingQuery(
                'SELECT Id, DeveloperName FROM CustomField ' +
                whereClause +
                ' AND ManageableState = \'unmanaged\''
            );

        for (Map<String, Object> row : customFieldRows) {
            String developerName =
                getString(row, 'DeveloperName', '');
            String customFieldId =
                getString(row, 'Id', '');

            if (!String.isBlank(developerName)
                && !String.isBlank(customFieldId)) {
                customFieldIdsByApiName.put(
                    developerName + '__c',
                    customFieldId
                );
            }
        }

        return customFieldIdsByApiName;

    }

    @AuraEnabled
    public static List<Map<String, Object>>
    createFieldsBulk(
        String objectName,
        List<Map<String, Object>> fieldDefinitions
    ) {

        List<Map<String, Object>> results =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {

            throw new AuraHandledException(
                'Object name is required.'
            );

        }

        if (fieldDefinitions == null
            || fieldDefinitions.isEmpty()) {

            throw new AuraHandledException(
                'At least one field definition is required.'
            );

        }

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {
            throw new AuraHandledException(
                'Invalid object name: ' + objectName
            );
        }

        List<Map<String, Object>> entityRows =
            toolingQuery(
                'SELECT IsCustomizable FROM EntityDefinition ' +
                'WHERE QualifiedApiName = \'' + escapeSoql(objectName) + '\' ' +
                'LIMIT 1'
            );

        if (!entityRows.isEmpty()
            && entityRows[0].containsKey('IsCustomizable')
            && entityRows[0].get('IsCustomizable') != null
            && !(Boolean) entityRows[0].get('IsCustomizable')) {

            throw new AuraHandledException(
                'Custom fields are not supported on object ' + objectName + '.'
            );

        }

        Integer index = 0;

        for (Map<String, Object> fieldDefinition :
            fieldDefinitions) {

            index++;

            String label =
                getString(fieldDefinition, 'label', '');

            String apiNameInput =
                getString(fieldDefinition, 'apiName', '');

            String typeInput =
                getString(fieldDefinition, 'type', '');

            Map<String, Object> rowResult =
                new Map<String, Object>{
                    'rowNumber' => index,
                    'label' => label,
                    'apiName' => apiNameInput,
                    'type' => typeInput
                };

            if (String.isBlank(label)) {

                rowResult.put('success', false);
                rowResult.put('message', 'Label is required.');
                results.add(rowResult);
                continue;

            }

            if (String.isBlank(typeInput)) {

                rowResult.put('success', false);
                rowResult.put('message', 'Type is required.');
                results.add(rowResult);
                continue;

            }

            String normalizedApiName =
                normalizeCustomFieldApiName(
                    apiNameInput,
                    label
                );

            rowResult.put(
                'apiName',
                normalizedApiName
            );

            try {
                Map<String, Object> payload =
                    new Map<String, Object>{
                        'FullName' => objectName + '.' + normalizedApiName,
                        'Metadata' => buildCustomFieldMetadata(fieldDefinition, label, typeInput)
                    };

                Map<String, Object> response =
                    restPostJson(
                        '/tooling/sobjects/CustomField',
                        payload
                    );

                rowResult.put('success', true);
                rowResult.put(
                    'id',
                    getString(response, 'id', '')
                );
                rowResult.put(
                    'message',
                    'Field created.'
                );
            } catch (Exception ex) {
                rowResult.put('success', false);
                rowResult.put('message', ex.getMessage());
            }

            results.add(rowResult);

        }

        return results;

    }

    @AuraEnabled
    public static Map<String, Object>
    deleteField(
        String objectName,
        String fieldApiName,
        String fieldDurableIdToken,
        String customFieldIdInput
    ) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException(
                'Object name is required.'
            );
        }

        if (String.isBlank(fieldApiName)) {
            throw new AuraHandledException(
                'Field API name is required.'
            );
        }

        Map<String, Schema.SObjectField> fieldMap =
            getFieldMap(objectName);

        if (!fieldMap.containsKey(fieldApiName)) {
            throw new AuraHandledException(
                'Field ' + fieldApiName + ' was not found on object ' + objectName + '.'
            );
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldApiName).getDescribe();

        if (!fieldDescribe.isCustom()) {
            throw new AuraHandledException(
                'Only custom fields can be deleted from this screen.'
            );
        }

        deleteCustomFieldViaMetadataApi(
            objectName + '.' + fieldApiName
        );

        return new Map<String, Object>{
            'success' => true,
            'fieldApiName' => fieldApiName,
            'id' => objectName + '.' + fieldApiName,
            'message' => 'Field deleted.'
        };

    }

    @AuraEnabled
    public static Map<String, Object>
    deleteObject(String objectName) {

        if (String.isBlank(objectName)) {
            throw new AuraHandledException(
                'Object name is required.'
            );
        }

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {
            throw new AuraHandledException(
                'Object ' + objectName + ' was not found.'
            );
        }

        Schema.DescribeSObjectResult objectDescribe =
            globalMap.get(objectName).getDescribe();

        if (!objectDescribe.isCustom()) {
            throw new AuraHandledException(
                'Only custom objects can be deleted from this screen.'
            );
        }

        deleteCustomObjectViaMetadataApi(objectName);

        return new Map<String, Object>{
            'success' => true,
            'id' => objectName,
            'apiName' => objectName,
            'message' => 'Object deleted.'
        };

    }

    private static void
    deleteCustomFieldViaMetadataApi(String fieldFullName) {

        if (String.isBlank(fieldFullName)) {
            throw new AuraHandledException(
                'Field full name is required.'
            );
        }

        // Use Named Credential OAuth token because UI session ids can be invalid for Metadata SOAP API.
        String sessionId =
            '{!$Credential.OAuthToken}';

        String endpoint =
            'callout:' +
            SALESFORCE_NAMED_CREDENTIAL +
            '/services/Soap/m/' +
            API_VERSION.substring(1);

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        request.setHeader('SOAPAction', '""');
        request.setBody(
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
            '<env:Header>' +
            '<met:SessionHeader><met:sessionId>' +
            escapeXml(sessionId) +
            '</met:sessionId></met:SessionHeader>' +
            '</env:Header>' +
            '<env:Body>' +
            '<met:deleteMetadata>' +
            '<met:type>CustomField</met:type>' +
            '<met:fullNames>' +
            escapeXml(fieldFullName) +
            '</met:fullNames>' +
            '</met:deleteMetadata>' +
            '</env:Body>' +
            '</env:Envelope>'
        );

        HttpResponse response =
            new Http().send(request);

        parseMetadataDeleteResponse(response, fieldFullName);

    }

    private static void
    deleteCustomObjectViaMetadataApi(String objectApiName) {

        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException(
                'Object API name is required.'
            );
        }

        String sessionId =
            '{!$Credential.OAuthToken}';

        String endpoint =
            'callout:' +
            SALESFORCE_NAMED_CREDENTIAL +
            '/services/Soap/m/' +
            API_VERSION.substring(1);

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        request.setHeader('SOAPAction', '""');
        request.setBody(
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
            '<env:Header>' +
            '<met:SessionHeader><met:sessionId>' +
            escapeXml(sessionId) +
            '</met:sessionId></met:SessionHeader>' +
            '</env:Header>' +
            '<env:Body>' +
            '<met:deleteMetadata>' +
            '<met:type>CustomObject</met:type>' +
            '<met:fullNames>' +
            escapeXml(objectApiName) +
            '</met:fullNames>' +
            '</met:deleteMetadata>' +
            '</env:Body>' +
            '</env:Envelope>'
        );

        HttpResponse response =
            new Http().send(request);

        parseMetadataDeleteResponse(response, objectApiName);

    }

    private static void
    parseMetadataDeleteResponse(
        HttpResponse response,
        String fieldFullName
    ) {

        String body =
            response == null
                ? ''
                : response.getBody();

        if (response == null) {
            throw new AuraHandledException(
                'No response was received from Metadata API delete call.'
            );
        }

        Dom.Document doc =
            new Dom.Document();

        try {
            doc.load(body);
        } catch (Exception parseException) {
            if (response.getStatusCode() < 200
                || response.getStatusCode() >= 300) {
                throw new AuraHandledException(
                    'Metadata delete failed: ' + parseErrorMessage(response)
                );
            }

            throw new AuraHandledException(
                'Metadata delete returned an unreadable response.'
            );
        }

        Dom.XmlNode envelope =
            doc.getRootElement();
        Dom.XmlNode bodyNode =
            findXmlChildByLocalName(envelope, 'Body');

        if (bodyNode == null) {
            throw new AuraHandledException(
                'Metadata delete response body was not returned.'
            );
        }

        Dom.XmlNode faultNode =
            findXmlChildByLocalName(bodyNode, 'Fault');

        if (faultNode != null) {
            Dom.XmlNode faultStringNode =
                findXmlChildByLocalName(faultNode, 'faultstring');
            String faultMessage =
                faultStringNode == null
                    ? 'Unknown Metadata API fault.'
                    : faultStringNode.getText();

            throw new AuraHandledException(
                'Metadata delete failed: ' + faultMessage
            );
        }

        Dom.XmlNode deleteResponseNode =
            findXmlChildByLocalName(bodyNode, 'deleteMetadataResponse');
        Dom.XmlNode resultNode =
            deleteResponseNode == null
                ? null
                : findXmlChildByLocalName(deleteResponseNode, 'result');

        if (resultNode == null) {
            throw new AuraHandledException(
                'Metadata delete did not return a result for ' + fieldFullName + '.'
            );
        }

        String successText =
            getXmlChildText(resultNode, 'success');
        Boolean isSuccess =
            successText != null
                && successText.trim().toLowerCase() == 'true';

        if (isSuccess) {
            return;
        }

        Dom.XmlNode errorsNode =
            findXmlChildByLocalName(resultNode, 'errors');
        String statusCode =
            errorsNode == null
                ? ''
                : getXmlChildText(errorsNode, 'statusCode');
        String message =
            errorsNode == null
                ? ''
                : getXmlChildText(errorsNode, 'message');

        String combinedMessage =
            'Metadata delete failed for ' +
            fieldFullName +
            (String.isBlank(statusCode) ? '' : ' [' + statusCode + ']') +
            (String.isBlank(message) ? '' : ' ' + message);

        throw new AuraHandledException(combinedMessage);

    }

    private static Dom.XmlNode
    findXmlChildByLocalName(Dom.XmlNode parent, String localName) {

        if (parent == null || String.isBlank(localName)) {
            return null;
        }

        for (Dom.XmlNode child : parent.getChildElements()) {
            if (child.getName() == localName) {
                return child;
            }
        }

        return null;

    }

    private static String
    getXmlChildText(Dom.XmlNode parent, String localName) {

        Dom.XmlNode child =
            findXmlChildByLocalName(parent, localName);

        return child == null
            ? null
            : child.getText();

    }

    private static String
    resolveCustomFieldMetadataId(
        String objectName,
        String fieldApiName
    ) {

        String entityDefinitionId =
            getEntityDefinitionDurableId(objectName);

        List<Map<String, Object>> fieldDefinitionRows =
            toolingQuery(
                'SELECT DurableId FROM FieldDefinition ' +
                'WHERE EntityDefinitionId = \'' +
                escapeSoql(entityDefinitionId) +
                '\' ' +
                'AND QualifiedApiName = \'' +
                escapeSoql(fieldApiName) +
                '\' ' +
                'LIMIT 1'
            );

        if (!fieldDefinitionRows.isEmpty()) {
            String durableId =
                getString(fieldDefinitionRows[0], 'DurableId', '');
            String durableToken =
                extractDurableIdToken(durableId);

            if (!String.isBlank(durableToken)) {
                String tokenAsId =
                    normalizeSalesforceId(durableToken);
                if (!String.isBlank(tokenAsId)) {
                    String validatedId =
                        validateCustomFieldIdForObject(objectName, tokenAsId);
                    if (!String.isBlank(validatedId)) {
                        return validatedId;
                    }
                }
            }
        }

        String developerName =
            extractDeveloperName(fieldApiName);

        if (String.isBlank(developerName)) {
            return '';
        }

        if (String.isBlank(entityDefinitionId)) {
            return '';
        }

        List<Map<String, Object>> fieldRows =
            toolingQuery(
                'SELECT Id FROM CustomField ' +
                'WHERE TableEnumOrId = \'' + escapeSoql(entityDefinitionId) + '\' ' +
                'AND DeveloperName = \'' + escapeSoql(developerName) + '\' ' +
                'AND ManageableState = \'unmanaged\' ' +
                'LIMIT 1'
            );

        return fieldRows.isEmpty()
            ? ''
            : normalizeSalesforceId(getString(fieldRows[0], 'Id', ''));

    }

    @TestVisible
    private static String
    extractDurableIdToken(String durableId) {

        if (String.isBlank(durableId)) {
            return '';
        }

        Integer separatorIndex =
            durableId.indexOf('.');

        if (separatorIndex < 0) {
            return durableId;
        }

        if (separatorIndex + 1 >= durableId.length()) {
            return '';
        }

        return durableId.substring(separatorIndex + 1);

    }

    @TestVisible
    private static String
    extractDeveloperName(String fieldApiName) {

        if (String.isBlank(fieldApiName)) {
            return '';
        }

        String developerName =
            fieldApiName.trim();

        if (developerName.endsWith('__c')
            || developerName.endsWith('__C')) {
            developerName =
                developerName.substring(0, developerName.length() - 3);
        }

        return developerName;

    }

    @TestVisible
    private static String
    normalizeSalesforceId(String candidateId) {

        if (String.isBlank(candidateId)) {
            return '';
        }

        String trimmed =
            candidateId.trim();

        if (!Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', trimmed)) {
            return '';
        }

        return trimmed;

    }

    private static String
    validateCustomFieldIdForObject(
        String objectName,
        String candidateId
    ) {

        String normalizedId =
            normalizeSalesforceId(candidateId);

        if (String.isBlank(normalizedId)) {
            return '';
        }

        String entityDefinitionId =
            getEntityDefinitionDurableId(objectName);

        if (String.isBlank(entityDefinitionId)) {
            return '';
        }

        List<Map<String, Object>> rows =
            toolingQuery(
                'SELECT Id FROM CustomField ' +
                'WHERE Id = \'' + escapeSoql(normalizedId) + '\' ' +
                'AND (TableEnumOrId = \'' + escapeSoql(entityDefinitionId) + '\' ' +
                'OR TableEnumOrId = \'' + escapeSoql(objectName) + '\') ' +
                'AND ManageableState = \'unmanaged\' ' +
                'LIMIT 1'
            );

        return rows.isEmpty()
            ? ''
            : getString(rows[0], 'Id', '');

    }

    @TestVisible
    private static String
    normalizeCustomFieldApiName(
        String apiNameInput,
        String label
    ) {

        String candidate =
            String.isBlank(apiNameInput)
                ? label
                : apiNameInput;

        candidate =
            candidate
                .trim()
                .replaceAll('[^a-zA-Z0-9_]', '_')
                .replaceAll('_+', '_');

        if (String.isBlank(candidate)) {
            candidate = 'New_Field';
        }

        if (!Pattern.matches('^[A-Za-z_].*', candidate)) {
            candidate = 'F_' + candidate;
        }

        if (candidate.endsWith('__c')) {
            return candidate;
        }

        if (candidate.endsWith('__C')) {
            return candidate.substring(0, candidate.length() - 3) + '__c';
        }

        return candidate + '__c';

    }

    private static Map<String, Object>
    buildCustomFieldMetadata(
        Map<String, Object> fieldDefinition,
        String label,
        String rawType
    ) {

        String normalizedType =
            normalizeFieldType(rawType);

        Map<String, Object> metadata =
            new Map<String, Object>{
                'label' => label,
                'type' => normalizedType
            };

        String description =
            getString(fieldDefinition, 'description', '');

        if (!String.isBlank(description)) {
            metadata.put('description', description);
        }

        String inlineHelpText =
            getString(fieldDefinition, 'inlineHelpText', '');

        if (String.isBlank(inlineHelpText)) {
            inlineHelpText =
                getString(fieldDefinition, 'helpText', '');
        }

        if (!String.isBlank(inlineHelpText)) {
            metadata.put('inlineHelpText', inlineHelpText);
        }

        Boolean required =
            toBoolean(
                fieldDefinition.get('required')
            );

        if (normalizedType != 'Checkbox'
            && normalizedType != 'AutoNumber') {
            metadata.put('required', required);
        }

        if (normalizedType == 'Text'
            || normalizedType == 'TextArea'
            || normalizedType == 'Email'
            || normalizedType == 'Phone'
            || normalizedType == 'Url'
            || normalizedType == 'EncryptedText') {

            Integer length =
                toInteger(
                    fieldDefinition.get('length'),
                    defaultLengthForType(normalizedType)
                );

            metadata.put('length', length);

        } else if (normalizedType == 'LongTextArea'
            || normalizedType == 'Html') {

            Integer length =
                toInteger(
                    fieldDefinition.get('length'),
                    32768
                );

            Integer visibleLines =
                toInteger(
                    fieldDefinition.get('visibleLines'),
                    3
                );

            metadata.put('length', length);
            metadata.put('visibleLines', visibleLines);

        } else if (normalizedType == 'Number'
            || normalizedType == 'Currency'
            || normalizedType == 'Percent') {

            Integer precision =
                toInteger(
                    fieldDefinition.get('precision'),
                    defaultPrecisionForType(normalizedType)
                );

            Integer scale =
                toInteger(
                    fieldDefinition.get('scale'),
                    defaultScaleForType(normalizedType)
                );

            metadata.put('precision', precision);
            metadata.put('scale', scale);

        } else if (normalizedType == 'Checkbox') {

            metadata.put(
                'defaultValue',
                toBoolean(fieldDefinition.get('defaultValue'))
            );

        } else if (normalizedType == 'AutoNumber') {

            String displayFormat =
                getString(fieldDefinition, 'displayFormat', 'AUTO-{0000}');

            if (String.isBlank(displayFormat)) {
                displayFormat = 'AUTO-{0000}';
            }

            Integer startingNumber =
                toInteger(
                    fieldDefinition.get('startingNumber'),
                    1
                );

            metadata.put('displayFormat', displayFormat);
            metadata.put('startingNumber', startingNumber);

        } else if (normalizedType == 'Picklist'
            || normalizedType == 'MultiselectPicklist') {

            List<String> values =
                splitPicklistValues(
                    getString(
                        fieldDefinition,
                        'picklistValues',
                        ''
                    )
                );

            if (values.isEmpty()) {
                throw new AuraHandledException(
                    'Picklist values are required for ' +
                    normalizedType +
                    ' type.'
                );
            }

            List<Object> picklistEntries =
                new List<Object>();

            for (String value : values) {
                picklistEntries.add(
                    new Map<String, Object>{
                        'fullName' => value,
                        'default' => false,
                        'label' => value
                    }
                );
            }

            metadata.put(
                'valueSet',
                new Map<String, Object>{
                    'valueSetDefinition' => new Map<String, Object>{
                        'sorted' => false,
                        'value' => picklistEntries
                    }
                }
            );

        } else if (normalizedType == 'Date'
            || normalizedType == 'DateTime'
            || normalizedType == 'Time') {
            // Date has no additional properties for this flow.
        } else {
            throw new AuraHandledException(
                'Unsupported field type: ' + rawType
            );
        }

        if (supportsExternalId(normalizedType)) {
            metadata.put(
                'externalId',
                toBoolean(fieldDefinition.get('externalId'))
            );
        }

        if (supportsUnique(normalizedType)) {
            metadata.put(
                'unique',
                toBoolean(fieldDefinition.get('unique'))
            );
        }

        return metadata;

    }

    private static String
    normalizeFieldType(String rawType) {

        String key =
            String.isBlank(rawType)
                ? ''
                : rawType.trim().toLowerCase();

        if (key == 'text') {
            return 'Text';
        }

        if (key == 'textarea'
            || key == 'text area') {
            return 'TextArea';
        }

        if (key == 'longtextarea'
            || key == 'long text area'
            || key == 'long_text_area') {
            return 'LongTextArea';
        }

        if (key == 'html'
            || key == 'richtextarea'
            || key == 'rich text area') {
            return 'Html';
        }

        if (key == 'number') {
            return 'Number';
        }

        if (key == 'currency') {
            return 'Currency';
        }

        if (key == 'percent') {
            return 'Percent';
        }

        if (key == 'date') {
            return 'Date';
        }

        if (key == 'datetime'
            || key == 'date/time'
            || key == 'date time') {
            return 'DateTime';
        }

        if (key == 'time') {
            return 'Time';
        }

        if (key == 'checkbox'
            || key == 'boolean') {
            return 'Checkbox';
        }

        if (key == 'picklist') {
            return 'Picklist';
        }

        if (key == 'multipicklist'
            || key == 'multi-select picklist'
            || key == 'picklist (multi-select)'
            || key == 'multi picklist') {
            return 'MultiselectPicklist';
        }

        if (key == 'email') {
            return 'Email';
        }

        if (key == 'phone') {
            return 'Phone';
        }

        if (key == 'url') {
            return 'Url';
        }

        if (key == 'encryptedtext'
            || key == 'encrypted text') {
            return 'EncryptedText';
        }

        if (key == 'autonumber'
            || key == 'auto number'
            || key == 'auto_number') {
            return 'AutoNumber';
        }

        return rawType;

    }

    private static Integer
    defaultLengthForType(String normalizedType) {

        if (normalizedType == 'Email') {
            return 80;
        }

        if (normalizedType == 'Phone') {
            return 40;
        }

        if (normalizedType == 'EncryptedText') {
            return 175;
        }

        return 255;

    }

    private static Integer
    defaultPrecisionForType(String normalizedType) {

        if (normalizedType == 'Percent') {
            return 3;
        }

        return 18;

    }

    private static Integer
    defaultScaleForType(String normalizedType) {

        if (normalizedType == 'Currency') {
            return 2;
        }

        if (normalizedType == 'Percent') {
            return 2;
        }

        return 0;

    }

    private static Boolean
    supportsExternalId(String normalizedType) {

        return normalizedType == 'Text'
            || normalizedType == 'Number'
            || normalizedType == 'Email';

    }

    private static Boolean
    supportsUnique(String normalizedType) {

        return normalizedType == 'Text'
            || normalizedType == 'Number'
            || normalizedType == 'Email';

    }

    private static List<String>
    splitPicklistValues(String rawValues) {

        List<String> values =
            new List<String>();

        if (String.isBlank(rawValues)) {
            return values;
        }

        String normalized =
            rawValues.replace('\n', ';').replace('\r', ';').replace(',', ';');

        for (String value :
            normalized.split(';')) {

            String trimmed =
                value == null
                    ? ''
                    : value.trim();

            if (!String.isBlank(trimmed)) {
                values.add(trimmed);
            }

        }

        return values;

    }

    private static Integer
    toInteger(Object rawValue, Integer fallbackValue) {

        if (rawValue == null) {
            return fallbackValue;
        }

        try {
            String asText =
                String.valueOf(rawValue).trim();

            if (String.isBlank(asText)) {
                return fallbackValue;
            }

            if (asText.contains('.')) {
                return Integer.valueOf(
                    Decimal.valueOf(asText).intValue()
                );
            }

            return Integer.valueOf(asText);
        } catch (Exception ignored) {
            return fallbackValue;
        }

    }

    private static Boolean
    toBoolean(Object rawValue) {

        if (rawValue == null) {
            return false;
        }

        if (rawValue instanceof Boolean) {
            return (Boolean) rawValue;
        }

        String normalized =
            String.valueOf(rawValue).trim().toLowerCase();

        return normalized == 'true'
            || normalized == 'yes'
            || normalized == '1'
            || normalized == 'y';

    }
    /* =========================================
       GLOBAL METADATA SEARCH
       ========================================= */

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>>
    searchMetadata(String keyword) {

        List<Map<String, String>> results =
            new List<Map<String, String>>();

        if (String.isBlank(keyword)) {

            return results;

        }

        String searchKey =
            keyword.trim().toLowerCase();

        if (searchKey.length() < 2) {

            return results;

        }

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        for (String objName : globalMap.keySet()) {

            if (results.size() >= GLOBAL_SEARCH_RESULT_LIMIT) {

                break;

            }

            Schema.DescribeSObjectResult objDescribe =
                globalMap.get(objName).getDescribe();

            if (!objDescribe.isAccessible()) {

                continue;

            }

            Map<String, Schema.SObjectField> fieldMap =
                objDescribe.fields.getMap();

            for (String fieldName : fieldMap.keySet()) {

                if (results.size() >= GLOBAL_SEARCH_RESULT_LIMIT) {

                    break;

                }

                Schema.DescribeFieldResult fieldDescribe =
                    fieldMap.get(fieldName).getDescribe();

                String apiName =
                    fieldDescribe.getName();

                String label =
                    fieldDescribe.getLabel();

                if (
                    apiName
                    .toLowerCase()
                    .contains(searchKey)

                    ||

                    label
                    .toLowerCase()
                    .contains(searchKey)
                ) {

                    Map<String, String> result =
                        new Map<String, String>();

                    result.put(
                        'objectName',
                        objName
                    );

                    result.put(
                        'objectLabel',
                        objDescribe.getLabel()
                    );

                    result.put(
                        'fieldName',
                        apiName
                    );

                    result.put(
                        'fieldLabel',
                        label
                    );

                    results.add(result);

                }

            }

        }

        return results;

    }

    /* =========================================
       OBJECT LIMITS
       ========================================= */

    @AuraEnabled(cacheable=true)
    public static Map<String, Object>
    getObjectLimits(String objectName) {

        Map<String, Object> limits =
            new Map<String, Object>();

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return limits;

        }

        Schema.DescribeSObjectResult objDescribe =
            globalMap.get(objectName).getDescribe();

        Integer customFieldCount = 0;

        for (Schema.SObjectField fieldRef :
            objDescribe.fields.getMap().values()) {

            if (fieldRef.getDescribe().isCustom()) {
                customFieldCount++;
            }

        }

        limits.put(
            'fieldCount',
            objDescribe.fields.getMap().size()
        );

        limits.put(
            'customFieldCount',
            customFieldCount
        );

        limits.put(
            'childRelationshipCount',
            objDescribe.getChildRelationships().size()
        );

        limits.put(
            'recordTypeCount',
            objDescribe.getRecordTypeInfos().size()
        );

        limits.put(
            'fieldSetCount',
            objDescribe.fieldSets.getMap().size()
        );

        return limits;

    }

    /* =========================================
       RECORD TYPES
       ========================================= */

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>>
    getRecordTypes(String objectName) {

        List<Map<String, Object>> recordTypeList =
            new List<Map<String, Object>>();

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return recordTypeList;

        }

        Schema.DescribeSObjectResult objDescribe =
            globalMap.get(objectName).getDescribe();

        List<Schema.RecordTypeInfo> rtInfos =
            objDescribe.getRecordTypeInfos();

        for (Schema.RecordTypeInfo rt : rtInfos) {

            Map<String, Object> rtInfo =
                new Map<String, Object>();

            rtInfo.put(
                'name',
                rt.getName()
            );

            rtInfo.put(
                'developerName',
                rt.getDeveloperName()
            );

            rtInfo.put(
                'id',
                rt.getRecordTypeId()
            );

            rtInfo.put(
                'isActive',
                rt.isActive()
            );

            rtInfo.put(
                'isDefault',
                rt.isDefaultRecordTypeMapping()
            );

            recordTypeList.add(rtInfo);

        }

        return recordTypeList;

    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>>
    getDocumentationData(List<String> objectNames) {

        List<Map<String, Object>> documentationObjects =
            new List<Map<String, Object>>();

        if (objectNames == null
            || objectNames.isEmpty()) {

            return documentationObjects;

        }

        Set<String> uniqueObjectNames =
            new Set<String>();

        for (String objectName : objectNames) {

            if (!String.isBlank(objectName)) {
                uniqueObjectNames.add(objectName.trim());
            }

        }

        List<String> sortedObjectNames =
            new List<String>();

        sortedObjectNames.addAll(uniqueObjectNames);
        sortedObjectNames.sort();

        for (String objectName : sortedObjectNames) {
            documentationObjects.add(
                buildDocumentationObject(objectName)
            );
        }

        return documentationObjects;

    }

    private static Map<String, Object>
    buildDocumentationObject(String objectName) {

        Map<String, Object> details =
            getObjectDetails(objectName);
        Boolean isCustom =
            getBoolean(details, 'isCustom');

        return new Map<String, Object>{
            'name' => getString(details, 'label', objectName),
            'apiName' => getString(details, 'apiName', objectName),
            'type' => isCustom
                ? 'Custom Object'
                : 'Standard Object',
            'fields' => getDocumentationFields(objectName),
            'validationRules' => getDocumentationValidationRules(objectName),
            'relationships' => getDocumentationRelationships(objectName),
            'picklistValues' => getDocumentationPicklistValues(objectName),
            'pageLayouts' => getDocumentationPageLayouts(objectName),
            'additionalSections' =>
                getDocumentationAdditionalSections(
                    objectName,
                    details
                )
        };

    }

    private static List<Map<String, Object>>
    getDocumentationFields(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Map<String, Object> fieldInfo :
            getObjectFields(objectName)) {

            rows.add(
                new Map<String, Object>{
                    'apiName' => getString(fieldInfo, 'apiName', ''),
                    'label' => getString(fieldInfo, 'label', ''),
                    'type' => getString(fieldInfo, 'dataType', ''),
                    'required' => getBoolean(fieldInfo, 'isRequired')
                }
            );

        }

        return rows;

    }

    private static List<Map<String, Object>>
    getDocumentationValidationRules(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        try {
            List<Map<String, Object>> entityRows =
                toolingQuery(
                    'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = \'' +
                    escapeSoql(objectName) +
                    '\' LIMIT 1'
                );

            if (entityRows.isEmpty()) {
                return rows;
            }

            String entityDefinitionId =
                getString(entityRows[0], 'DurableId', '');

            if (String.isBlank(entityDefinitionId)) {
                return rows;
            }

            List<Map<String, Object>> rules =
                toolingQuery(
                    'SELECT ValidationName, ErrorConditionFormula, ErrorMessage ' +
                    'FROM ValidationRule ' +
                    'WHERE EntityDefinitionId = \'' +
                    escapeSoql(entityDefinitionId) +
                    '\' ' +
                    'ORDER BY ValidationName'
                );

            for (Map<String, Object> rule : rules) {
                rows.add(
                    new Map<String, Object>{
                        'name' => getString(rule, 'ValidationName', 'N/A'),
                        'formula' => getString(rule, 'ErrorConditionFormula', 'N/A'),
                        'errorMessage' => getString(rule, 'ErrorMessage', 'N/A')
                    }
                );
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load documentation validation rules for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static String
    getEntityDefinitionId(String objectName) {

        if (String.isBlank(objectName)) {
            return '';
        }

        try {
            List<Map<String, Object>> entityRows =
                toolingQuery(
                    'SELECT Id FROM EntityDefinition ' +
                    'WHERE QualifiedApiName = \'' +
                    escapeSoql(objectName) +
                    '\' LIMIT 1'
                );

            return entityRows.isEmpty()
                ? ''
                : getString(entityRows[0], 'Id', '');
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to resolve EntityDefinitionId for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
            return '';
        }

    }

    private static String
    getEntityDefinitionDurableId(String objectName) {

        if (String.isBlank(objectName)) {
            return '';
        }

        try {
            List<Map<String, Object>> entityRows =
                toolingQuery(
                    'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = \'' +
                    escapeSoql(objectName) +
                    '\' LIMIT 1'
                );

            if (entityRows.isEmpty()) {
                return '';
            }

            return getString(entityRows[0], 'DurableId', '');
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to resolve EntityDefinitionId for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
            return '';
        }

    }

    private static List<Map<String, Object>>
    getDocumentationRelationships(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap =
            getFieldMap(objectName);
        List<String> fieldNames =
            new List<String>();

        fieldNames.addAll(fieldMap.keySet());
        fieldNames.sort();

        for (String fieldName : fieldNames) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (fieldDescribe.getType()
                != Schema.DisplayType.Reference) {
                continue;
            }

            List<String> relatedObjects =
                new List<String>();

            for (Schema.SObjectType referenceType :
                fieldDescribe.getReferenceTo()) {

                relatedObjects.add(
                    referenceType.getDescribe().getName()
                );

            }

            if (relatedObjects.isEmpty()) {
                continue;
            }

            rows.add(
                new Map<String, Object>{
                    'name' => fieldDescribe.getName(),
                    'type' => resolveRelationshipType(fieldDescribe),
                    'relatedObject' => String.join(relatedObjects, ', ')
                }
            );

        }

        return rows;

    }

    private static String
    resolveRelationshipType(
        Schema.DescribeFieldResult fieldDescribe
    ) {

        return fieldDescribe.isCascadeDelete()
            ? 'Master-Detail'
            : 'Lookup';

    }

    private static Map<String, Object>
    getDocumentationPicklistValues(String objectName) {

        Map<String, Object> picklistValuesByField =
            new Map<String, Object>();
        Map<String, Schema.SObjectField> fieldMap =
            getFieldMap(objectName);
        List<String> fieldNames =
            new List<String>();

        fieldNames.addAll(fieldMap.keySet());
        fieldNames.sort();

        for (String fieldName : fieldNames) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (fieldDescribe.getType()
                != Schema.DisplayType.Picklist
                && fieldDescribe.getType()
                    != Schema.DisplayType.MultiPicklist) {
                continue;
            }

            List<String> values =
                new List<String>();

            for (Schema.PicklistEntry picklistEntry :
                fieldDescribe.getPicklistValues()) {

                values.add(
                    picklistEntry.getValue()
                );

            }

            picklistValuesByField.put(
                fieldDescribe.getName(),
                values
            );

        }

        return picklistValuesByField;

    }

    private static List<Map<String, Object>>
    getDocumentationPageLayouts(String objectName) {

        try {
            return getDocumentationPageLayoutsUiApi(objectName);
        } catch (Exception uiApiError) {
            return getDocumentationPageLayoutsDescribe(objectName);
        }

    }

    private static List<Map<String, Object>>
    getDocumentationPageLayoutsUiApi(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {
            return rows;
        }

        Schema.DescribeSObjectResult objectDescribe =
            globalMap.get(objectName).getDescribe();

        for (Schema.RecordTypeInfo recordTypeInfo :
            getAvailableRecordTypeInfos(objectDescribe)) {

            String recordTypeId =
                String.valueOf(recordTypeInfo.getRecordTypeId());
            String endpoint =
                '/ui-api/layout/' +
                EncodingUtil.urlEncode(objectName, 'UTF-8') +
                '?formFactor=Large' +
                '&layoutTypes=Full' +
                '&modes=View' +
                '&recordTypeId=' +
                EncodingUtil.urlEncode(recordTypeId, 'UTF-8');

            Map<String, Object> response =
                restGetJson(endpoint);
            Map<String, Object> layout =
                response.containsKey('layout')
                    ? (Map<String, Object>) response.get('layout')
                    : response;

            if (layout == null) {
                continue;
            }

            List<Map<String, Object>> sections =
                extractUiApiLayoutSections(layout);

            rows.add(
                new Map<String, Object>{
                    'name' => recordTypeInfo.getName(),
                    'recordType' => recordTypeInfo.getName(),
                    'recordTypeId' => recordTypeInfo.getRecordTypeId(),
                    'layoutId' => getString(layout, 'id', 'N/A'),
                    'layoutType' => getString(layout, 'layoutType', 'Full'),
                    'mode' => getString(layout, 'mode', 'View'),
                    'sections' => sections,
                    'fields' => collectLayoutFieldNames(sections),
                    'saveOptions' =>
                        getObjectList(layout, 'saveOptions')
                }
            );

        }

        return rows;

    }

    private static List<Schema.RecordTypeInfo>
    getAvailableRecordTypeInfos(
        Schema.DescribeSObjectResult objectDescribe
    ) {

        List<Schema.RecordTypeInfo> availableRecordTypes =
            new List<Schema.RecordTypeInfo>();

        for (Schema.RecordTypeInfo recordTypeInfo :
            objectDescribe.getRecordTypeInfos()) {

            if (recordTypeInfo.isAvailable()
                || recordTypeInfo.isMaster()) {
                availableRecordTypes.add(recordTypeInfo);
            }

        }

        if (availableRecordTypes.isEmpty()) {
            availableRecordTypes.addAll(
                objectDescribe.getRecordTypeInfos()
            );
        }

        return availableRecordTypes;

    }

    private static List<Map<String, Object>>
    extractUiApiLayoutSections(
        Map<String, Object> layout
    ) {

        List<Map<String, Object>> sections =
            new List<Map<String, Object>>();

        for (Object sectionObj :
            getPrimaryLayoutSections(layout)) {

            Map<String, Object> section =
                (Map<String, Object>) sectionObj;
            List<String> fields =
                new List<String>();

            for (Object rowObj :
                getObjectList(section, 'layoutRows')) {

                Map<String, Object> row =
                    (Map<String, Object>) rowObj;

                for (Object itemObj :
                    getObjectList(row, 'layoutItems')) {

                    Map<String, Object> item =
                        (Map<String, Object>) itemObj;

                    for (Object componentObj :
                        getObjectList(item, 'layoutComponents')) {

                        String fieldApiName =
                            extractLayoutFieldApiName(
                                (Map<String, Object>) componentObj
                            );

                        if (!String.isBlank(fieldApiName)) {
                            fields.add(fieldApiName);
                        }

                    }
                }
            }

            sections.add(
                new Map<String, Object>{
                    'heading' => getString(section, 'heading', 'Layout Section'),
                    'fields' => fields
                }
            );

        }

        return sections;

    }

    private static List<Map<String, Object>>
    getDocumentationPageLayoutsDescribe(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        Map<String, Object> data =
            restGetJson(
                '/sobjects/' +
                objectName +
                '/describe/layouts'
            );

        for (Object layoutObj :
            getObjectList(data, 'layouts')) {

            Map<String, Object> layout =
                (Map<String, Object>) layoutObj;
            List<Map<String, Object>> sections =
                extractDescribeLayoutSections(layout);

            rows.add(
                new Map<String, Object>{
                    'name' => getString(layout, 'label', 'Layout'),
                    'recordType' => 'Master',
                    'recordTypeId' => 'Master Layout',
                    'layoutId' => getString(layout, 'id', 'N/A'),
                    'layoutType' => 'Full',
                    'mode' => 'View',
                    'sections' => sections,
                    'fields' => collectLayoutFieldNames(sections),
                    'saveOptions' => getObjectList(layout, 'saveOptions')
                }
            );

        }

        return rows;

    }

    private static List<Map<String, Object>>
    extractDescribeLayoutSections(
        Map<String, Object> layout
    ) {

        List<Map<String, Object>> sections =
            new List<Map<String, Object>>();

        for (Object sectionObj :
            getObjectList(layout, 'layoutSections')) {

            Map<String, Object> section =
                (Map<String, Object>) sectionObj;
            List<String> fields =
                new List<String>();

            for (Object rowObj :
                getObjectList(section, 'layoutRows')) {

                Map<String, Object> row =
                    (Map<String, Object>) rowObj;

                for (Object itemObj :
                    getObjectList(row, 'layoutItems')) {

                    Map<String, Object> item =
                        (Map<String, Object>) itemObj;

                    for (Object componentObj :
                        getObjectList(item, 'layoutComponents')) {

                        String fieldApiName =
                            extractLayoutFieldApiName(
                                (Map<String, Object>) componentObj
                            );

                        if (!String.isBlank(fieldApiName)) {
                            fields.add(fieldApiName);
                        }

                    }
                }
            }

            sections.add(
                new Map<String, Object>{
                    'heading' => getString(section, 'heading', 'Layout Section'),
                    'fields' => fields
                }
            );

        }

        return sections;

    }

    private static String
    extractLayoutFieldApiName(
        Map<String, Object> component
    ) {

        if (component == null) {
            return '';
        }

        String componentType =
            getString(component, 'componentType', '');

        if (componentType != 'FIELD') {
            return '';
        }

        String fieldApiName =
            getString(component, 'apiName', '');

        if (!String.isBlank(fieldApiName)) {
            return fieldApiName;
        }

        fieldApiName =
            getString(component, 'value', '');

        if (!String.isBlank(fieldApiName)) {
            return fieldApiName;
        }

        if (component.containsKey('details')
            && component.get('details')
                instanceof Map<String, Object>) {

            Map<String, Object> details =
                (Map<String, Object>) component.get('details');

            fieldApiName =
                getString(details, 'name', '');

            if (!String.isBlank(fieldApiName)) {
                return fieldApiName;
            }

            return getString(details, 'apiName', '');
        }

        return '';

    }

    private static List<String>
    collectLayoutFieldNames(
        List<Map<String, Object>> sections
    ) {

        List<String> fieldNames =
            new List<String>();
        Set<String> seenFieldNames =
            new Set<String>();

        for (Map<String, Object> section : sections) {

            Object sectionFieldsValue =
                section.get('fields');

            if (sectionFieldsValue
                instanceof List<String>) {

                for (String fieldName :
                    (List<String>) sectionFieldsValue) {

                    if (String.isBlank(fieldName)
                        || seenFieldNames.contains(fieldName)) {
                        continue;
                    }

                    seenFieldNames.add(fieldName);
                    fieldNames.add(fieldName);

                }
            }

        }

        return fieldNames;

    }

    private static List<Map<String, Object>>
    getDocumentationAdditionalSections(
        String objectName,
        Map<String, Object> details
    ) {

        List<Map<String, Object>> sections =
            new List<Map<String, Object>>();

        sections.add(
            buildDocumentationSection(
                'details',
                buildDocumentationDetailsSection(
                    objectName,
                    details
                )
            )
        );
        sections.add(
            buildDocumentationSection(
                'recordTypes',
                buildDocumentationRecordTypesSection(
                    objectName
                )
            )
        );

        for (String sectionId :
            new List<String>{
                'flows',
                'lightningRecordPages',
                'buttonsLinksActions',
                'compactLayouts',
                'fieldSets',
                'objectLimits',
                'relatedLookupFilters',
                'searchLayouts',
                'listViewButtonLayout',
                'hierarchyColumns',
                'scopingRules'
            }) {

            sections.add(
                buildDocumentationSection(
                    sectionId,
                    getSectionData(
                        sectionId,
                        objectName
                    )
                )
            );

        }

        return sections;

    }

    private static Map<String, Object>
    buildDocumentationSection(
        String key,
        Map<String, Object> sectionData
    ) {

        Map<String, Object> decoratedSection =
            sectionData == null
                ? new Map<String, Object>()
                : sectionData;

        decoratedSection.put('key', key);

        return decoratedSection;

    }

    private static Map<String, Object>
    buildDocumentationDetailsSection(
        String objectName,
        Map<String, Object> details
    ) {

        return buildTableSection(
            'Details',
            objectName,
            new List<Map<String, String>>{
                buildColumn('property', 'Property'),
                buildColumn('value', 'Value')
            },
            new List<Map<String, Object>>{
                new Map<String, Object>{
                    'property' => 'Object Label',
                    'value' => getString(details, 'label', objectName)
                },
                new Map<String, Object>{
                    'property' => 'Plural Label',
                    'value' => getString(details, 'pluralLabel', 'N/A')
                },
                new Map<String, Object>{
                    'property' => 'API Name',
                    'value' => getString(details, 'apiName', objectName)
                },
                new Map<String, Object>{
                    'property' => 'Key Prefix',
                    'value' => getString(details, 'keyPrefix', 'N/A')
                },
                new Map<String, Object>{
                    'property' => 'Is Custom',
                    'value' => yesNo(getBoolean(details, 'isCustom'))
                },
                new Map<String, Object>{
                    'property' => 'Is Queryable',
                    'value' => yesNo(getBoolean(details, 'isQueryable'))
                },
                new Map<String, Object>{
                    'property' => 'Is Createable',
                    'value' => yesNo(getBoolean(details, 'isCreateable'))
                },
                new Map<String, Object>{
                    'property' => 'Is Updateable',
                    'value' => yesNo(getBoolean(details, 'isUpdateable'))
                },
                new Map<String, Object>{
                    'property' => 'Is Deletable',
                    'value' => yesNo(getBoolean(details, 'isDeletable'))
                }
            }
        );

    }

    private static Map<String, Object>
    buildDocumentationRecordTypesSection(String objectName) {

        List<Map<String, Object>> recordTypes =
            getRecordTypes(objectName);

        if (recordTypes.isEmpty()) {

            return buildMessageSection(
                'Record Types',
                objectName,
                'No record types are defined for this object.'
            );

        }

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Map<String, Object> recordType : recordTypes) {
            rows.add(
                new Map<String, Object>{
                    'name' => getString(recordType, 'name', 'N/A'),
                    'developerName' => getString(recordType, 'developerName', 'N/A'),
                    'active' => yesNo(getBoolean(recordType, 'isActive')),
                    'isDefault' => yesNo(getBoolean(recordType, 'isDefault'))
                }
            );
        }

        return buildTableSection(
            'Record Types',
            objectName,
            new List<Map<String, String>>{
                buildColumn('name', 'Record Type Name'),
                buildColumn('developerName', 'Developer Name'),
                buildColumn('active', 'Is Active'),
                buildColumn('isDefault', 'Is Default')
            },
            rows
        );

    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object>
    getImpactAnalysisMetadata(
        String targetType,
        String apiName,
        String objectApiName
    ) {

        String resolvedObjectName =
            targetType == 'field'
                ? objectApiName
                : apiName;

        return new Map<String, Object>{
            'flows' => getImpactFlowMetadata(resolvedObjectName),
            'validationRules' => getImpactValidationRuleMetadata(
                resolvedObjectName
            ),
            'apexClasses' => getImpactApexClassMetadata(
                apiName,
                resolvedObjectName
            ),
            'reports' => getImpactReportMetadata(
                apiName,
                resolvedObjectName
            ),
            'dashboards' => getImpactDashboardMetadata(
                apiName,
                resolvedObjectName
            ),
            'pageLayouts' => getImpactPageLayoutMetadata(
                resolvedObjectName
            ),
            'workflowRules' => getImpactWorkflowRuleMetadata(
                resolvedObjectName
            ),
            'formulas' => getImpactFormulaMetadata(
                resolvedObjectName
            )
        };

    }

    private static List<Map<String, Object>>
    getImpactFlowMetadata(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (String.isBlank(objectName)
            || !globalMap.containsKey(objectName)) {
            return rows;
        }

        try {
            String objectLabel =
                globalMap.get(objectName).getDescribe().getLabel();

            for (Map<String, Object> flow :
                databaseQuery(
                    'SELECT Id, Name, ApiName, FlowLabel, FlowType, Type ' +
                    'FROM FlowRecord ' +
                    'WHERE TriggerObjectOrEventLabel = \'' +
                    escapeSoql(objectLabel) +
                    '\' ' +
                    'ORDER BY FlowLabel'
                )) {

                rows.add(
                    new Map<String, Object>{
                        'id' => getString(flow, 'Id', ''),
                        'name' => getString(flow, 'Name', ''),
                        'label' => getString(flow, 'FlowLabel', 'Flow'),
                        'apiName' => getString(flow, 'ApiName', ''),
                        'isActive' => true,
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(flow, 'FlowLabel', ''),
                                getString(flow, 'ApiName', ''),
                                getString(flow, 'FlowType', ''),
                                getString(flow, 'Type', ''),
                                objectName
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact flow metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactValidationRuleMetadata(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            String entityDefinitionId =
                getEntityDefinitionDurableId(objectName);

            if (String.isBlank(entityDefinitionId)) {
                return rows;
            }

            try {
                for (Map<String, Object> rule :
                    toolingQuery(
                        'SELECT ValidationName, Active, ErrorConditionFormula, ErrorMessage ' +
                        'FROM ValidationRule ' +
                        'WHERE EntityDefinitionId = \'' +
                        escapeSoql(entityDefinitionId) +
                        '\' ' +
                        'ORDER BY ValidationName'
                    )) {

                    rows.add(
                        new Map<String, Object>{
                            'name' => getString(rule, 'ValidationName', 'Validation Rule'),
                            'formula' => getString(rule, 'ErrorConditionFormula', ''),
                            'errorMessage' => getString(rule, 'ErrorMessage', ''),
                            'isActive' => getBoolean(rule, 'Active'),
                            'referenceText' => buildImpactReferenceText(
                                new List<String>{
                                    getString(rule, 'ValidationName', ''),
                                    getString(rule, 'ErrorConditionFormula', ''),
                                    getString(rule, 'ErrorMessage', ''),
                                    objectName
                                }
                            )
                        }
                    );

                }
            } catch (Exception directQueryError) {
                for (Map<String, Object> rule :
                    toolingQuery(
                        'SELECT ValidationName, Active, Metadata ' +
                        'FROM ValidationRule ' +
                        'WHERE EntityDefinitionId = \'' +
                        escapeSoql(entityDefinitionId) +
                        '\' ' +
                        'ORDER BY ValidationName'
                    )) {

                    Map<String, Object> metadata =
                        getMap(rule, 'Metadata');
                    String formula =
                        getStringFromValue(metadata.get('errorConditionFormula'));
                    String errorMessage =
                        getStringFromValue(metadata.get('errorMessage'));

                    rows.add(
                        new Map<String, Object>{
                            'name' => getString(rule, 'ValidationName', 'Validation Rule'),
                            'formula' => formula,
                            'errorMessage' => errorMessage,
                            'isActive' => getBoolean(rule, 'Active'),
                            'referenceText' => buildImpactReferenceText(
                                new List<String>{
                                    getString(rule, 'ValidationName', ''),
                                    formula,
                                    errorMessage,
                                    JSON.serialize(metadata),
                                    objectName
                                }
                            )
                        }
                    );

                }
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact validation rule metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactApexClassMetadata(
        String apiName,
        String objectName
    ) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        String searchTerm =
            String.isBlank(apiName)
                ? objectName
                : apiName;

        if (String.isBlank(searchTerm)) {
            return rows;
        }

        try {
            for (Map<String, Object> apexClass :
                toolingQuery(
                    'SELECT Name, Body ' +
                    'FROM ApexClass ' +
                    'WHERE Body LIKE \'%' +
                    escapeSoql(searchTerm) +
                    '%\' ' +
                    'ORDER BY Name'
                )) {

                rows.add(
                    new Map<String, Object>{
                        'name' => getString(apexClass, 'Name', 'Apex Class'),
                        'body' => getString(apexClass, 'Body', ''),
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(apexClass, 'Name', ''),
                                getString(apexClass, 'Body', '')
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact Apex class metadata for ' +
                searchTerm +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactReportMetadata(
        String apiName,
        String objectName
    ) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        List<String> searchTerms =
            getImpactSearchTerms(apiName, objectName);

        if (searchTerms.isEmpty()) {
            return rows;
        }

        try {
            List<String> whereFragments =
                new List<String>();

            for (String term : searchTerms) {
                if (String.isBlank(term)) {
                    continue;
                }

                String escapedTerm =
                    escapeSoql(term);

                whereFragments.add(
                    'Name LIKE \'%' + escapedTerm + '%\''
                );
                whereFragments.add(
                    'DeveloperName LIKE \'%' + escapedTerm + '%\''
                );
                whereFragments.add(
                    'Description LIKE \'%' + escapedTerm + '%\''
                );
            }

            if (whereFragments.isEmpty()) {
                return rows;
            }

            for (Map<String, Object> reportRow :
                databaseQuery(
                    'SELECT Id, Name, DeveloperName, Description ' +
                    'FROM Report ' +
                    'WHERE ' +
                    String.join(whereFragments, ' OR ') +
                    ' ORDER BY Name'
                )) {

                rows.add(
                    new Map<String, Object>{
                        'id' => getString(reportRow, 'Id', ''),
                        'name' => getString(reportRow, 'Name', 'Report'),
                        'developerName' => getString(reportRow, 'DeveloperName', ''),
                        'description' => getString(reportRow, 'Description', ''),
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(reportRow, 'Name', ''),
                                getString(reportRow, 'DeveloperName', ''),
                                getString(reportRow, 'Description', '')
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact report metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactDashboardMetadata(
        String apiName,
        String objectName
    ) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        List<String> searchTerms =
            getImpactSearchTerms(apiName, objectName);

        if (searchTerms.isEmpty()) {
            return rows;
        }

        try {
            List<String> whereFragments =
                new List<String>();

            for (String term : searchTerms) {
                if (String.isBlank(term)) {
                    continue;
                }

                String escapedTerm =
                    escapeSoql(term);

                whereFragments.add(
                    'Title LIKE \'%' + escapedTerm + '%\''
                );
                whereFragments.add(
                    'Description LIKE \'%' + escapedTerm + '%\''
                );
            }

            if (whereFragments.isEmpty()) {
                return rows;
            }

            for (Map<String, Object> dashboard :
                databaseQuery(
                    'SELECT Id, Title, Description ' +
                    'FROM Dashboard ' +
                    'WHERE ' +
                    String.join(whereFragments, ' OR ') +
                    ' ORDER BY Title'
                )) {

                rows.add(
                    new Map<String, Object>{
                        'id' => getString(dashboard, 'Id', ''),
                        'name' => getString(dashboard, 'Title', 'Dashboard'),
                        'description' => getString(dashboard, 'Description', ''),
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(dashboard, 'Title', ''),
                                getString(dashboard, 'Description', '')
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact dashboard metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactPageLayoutMetadata(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            for (Map<String, Object> layout :
                getDocumentationPageLayouts(objectName)) {

                List<String> fieldNames =
                    new List<String>();
                Object fieldValue =
                    layout.get('fields');

                if (fieldValue instanceof List<String>) {
                    fieldNames.addAll(
                        (List<String>) fieldValue
                    );
                }

                rows.add(
                    new Map<String, Object>{
                        'name' => getString(layout, 'name', 'Page Layout'),
                        'recordType' => getString(layout, 'recordType', ''),
                        'fields' => fieldNames,
                        'sections' => getObjectList(layout, 'sections'),
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(layout, 'name', ''),
                                getString(layout, 'recordType', ''),
                                String.join(fieldNames, ' '),
                                JSON.serialize(getObjectList(layout, 'sections')),
                                objectName
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact page layout metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactWorkflowRuleMetadata(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            String entityDefinitionId =
                getEntityDefinitionDurableId(objectName);
            String whereClause =
                'WHERE TableEnumOrId = \'' +
                escapeSoql(objectName) +
                '\'';

            if (!String.isBlank(entityDefinitionId)
                && entityDefinitionId != objectName) {
                whereClause +=
                    ' OR TableEnumOrId = \'' +
                    escapeSoql(entityDefinitionId) +
                    '\'';
            }

            for (Map<String, Object> workflowRule :
                toolingQuery(
                    'SELECT Id, Name, TableEnumOrId, Metadata ' +
                    'FROM WorkflowRule ' +
                    whereClause +
                    ' ORDER BY Name'
                )) {

                Map<String, Object> metadata =
                    getMap(workflowRule, 'Metadata');
                Boolean isActive =
                    getBooleanFromValue(
                        metadata.get('active')
                    );

                rows.add(
                    new Map<String, Object>{
                        'id' => getString(workflowRule, 'Id', ''),
                        'name' => getString(workflowRule, 'Name', 'Workflow Rule'),
                        'isActive' => isActive,
                        'referenceText' => buildImpactReferenceText(
                            new List<String>{
                                getString(workflowRule, 'Name', ''),
                                JSON.serialize(metadata),
                                objectName
                            }
                        )
                    }
                );

            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to load impact workflow metadata for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getImpactFormulaMetadata(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap =
            getFieldMap(objectName);
        List<String> fieldNames =
            new List<String>();

        fieldNames.addAll(fieldMap.keySet());
        fieldNames.sort();

        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult fieldDescribe =
                fieldMap.get(fieldName).getDescribe();

            if (!fieldDescribe.isCalculated()) {
                continue;
            }

            String formula =
                fieldDescribe.getCalculatedFormula();

            rows.add(
                new Map<String, Object>{
                    'name' => fieldDescribe.getLabel(),
                    'apiName' => fieldDescribe.getName(),
                    'formula' => formula,
                    'referenceText' => buildImpactReferenceText(
                        new List<String>{
                            fieldDescribe.getLabel(),
                            fieldDescribe.getName(),
                            formula,
                            objectName
                        }
                    )
                }
            );
        }

        return rows;

    }

    private static List<String>
    getImpactSearchTerms(
        String apiName,
        String objectName
    ) {

        List<String> searchTerms =
            new List<String>();

        if (!String.isBlank(apiName)) {
            searchTerms.add(apiName);
        }

        if (!String.isBlank(objectName)
            && objectName != apiName) {
            searchTerms.add(objectName);
        }

        return searchTerms;

    }

    private static String
    buildImpactReferenceText(List<String> parts) {

        List<String> normalizedParts =
            new List<String>();

        for (String part : parts) {
            if (!String.isBlank(part)) {
                normalizedParts.add(part);
            }
        }

        return normalizedParts.isEmpty()
            ? ''
            : String.join(normalizedParts, ' ');

    }

    /* =========================================
       PLACEHOLDER SECTION DATA
       ========================================= */

    @AuraEnabled
    public static Map<String, Object>
    getSectionData(String sectionId, String objectName) {

        if (String.isBlank(sectionId)
            || String.isBlank(objectName)) {

            return buildMessageSection(
                'Metadata',
                objectName,
                'Object name or section id is missing.'
            );

        }

        try {

            if (sectionId == 'flows') {

                return getFlowsSection(objectName);

            }

            if (sectionId == 'pageLayouts') {

                return getPageLayoutsSection(objectName);

            }

            if (sectionId == 'lightningRecordPages') {

                return getLightningRecordPagesSection(objectName);

            }

            if (sectionId == 'buttonsLinksActions') {

                return getButtonsLinksActionsSection(objectName);

            }

            if (sectionId == 'compactLayouts') {

                return getCompactLayoutsSection(objectName);

            }

            if (sectionId == 'fieldSets') {

                return getFieldSetsSection(objectName);

            }

            if (sectionId == 'objectLimits') {

                return getObjectLimitsSection(objectName);

            }

            if (sectionId == 'validationRules') {

                return getValidationRulesSection(objectName);

            }

            if (sectionId == 'relatedLookupFilters') {

                return getRelatedLookupFiltersSection(objectName);

            }

            if (sectionId == 'searchLayouts') {

                return getSearchLayoutsSection(objectName);

            }

            if (sectionId == 'listViewButtonLayout') {

                return getListViewButtonLayoutSection(objectName);

            }

            if (sectionId == 'hierarchyColumns') {

                return getHierarchyColumnsSection(objectName);

            }

        } catch (Exception error) {

            return buildMessageSection(
                getSectionTitle(sectionId),
                objectName,
                'Salesforce metadata request failed: ' + error.getMessage()
            );

        }

        return buildMessageSection(
            getSectionTitle(sectionId),
            objectName,
            'This section is not available through the current Apex-backed metadata service yet.'
        );

    }

    private static Map<String, Schema.SObjectField>
    getFieldMap(String objectName) {

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return new Map<String, Schema.SObjectField>();

        }

        return globalMap
            .get(objectName)
            .getDescribe()
            .fields
            .getMap();

    }

    private static Map<String, Object>
    getFlowsSection(String objectName) {

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return buildMessageSection(
                'Flows',
                objectName,
                'No object definition was found for this object.'
            );

        }

        String objectLabel =
            globalMap.get(objectName).getDescribe().getLabel();

        List<Map<String, Object>> rows =
            databaseQuery(
                'SELECT Id, Name, ApiName, FlowLabel, FlowType, Type ' +
                'FROM FlowRecord ' +
                'WHERE TriggerObjectOrEventLabel = \'' + escapeSoql(objectLabel) + '\' ' +
                'ORDER BY FlowLabel'
            );

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Flows',
                objectName,
                'No object-triggered flows are associated with this object in this org.'
            );

        }

        return buildTableSection(
            'Flows',
            objectName,
            new List<Map<String, String>>{
                buildColumn('FlowLabel', 'Label'),
                buildColumn('ApiName', 'API Name'),
                buildColumn('FlowType', 'Flow Type'),
                buildColumn('Type', 'Trigger Type'),
                buildColumn('Id', 'Id')
            },
            rows
        );

    }

    private static Map<String, Object>
    getPageLayoutsSection(String objectName) {

        if (String.isBlank(objectName)) {

            return buildMessageSection(
                'Page Layouts',
                objectName,
                'Object name is missing.'
            );

        }

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        try {

            Map<String, Object> describe =
                restGetJson('/sobjects/' + objectName + '/describe');

            List<Object> recordTypeInfos =
                getObjectList(describe, 'recordTypeInfos');

            if (recordTypeInfos.isEmpty()) {

                Map<String, Object> layoutData =
                    restGetJson('/sobjects/' + objectName + '/describe/layouts');

                rows.addAll(
                    buildPageLayoutsFromLayoutData(
                        'Default',
                        '',
                        layoutData
                    )
                );

            } else {

                for (Object recordTypeObj : recordTypeInfos) {

                    Map<String, Object> recordType =
                        (Map<String, Object>) recordTypeObj;

                    String recordTypeName =
                        getString(
                            recordType,
                            'name',
                            getString(recordType, 'recordTypeName', 'Default')
                        );
                    String recordTypeId =
                        getString(recordType, 'recordTypeId', '');

                    String layoutUrl =
                        getString(
                            getMap(recordType, 'urls'),
                            'layout',
                            ''
                        );

                    if (String.isBlank(layoutUrl)) {
                        if (!String.isBlank(recordTypeId)) {
                            layoutUrl =
                                '/sobjects/' +
                                objectName +
                                '/describe/layouts/' +
                                recordTypeId;
                        } else {
                            layoutUrl =
                                '/sobjects/' + objectName + '/describe/layouts';
                        }
                    }

                    String relativePath =
                        normalizeMetadataPath(layoutUrl);

                    if (String.isBlank(relativePath)) {
                        continue;
                    }

                    Map<String, Object> layoutData =
                        restGetJson(relativePath);

                    rows.addAll(
                        buildPageLayoutsFromLayoutData(
                            recordTypeName,
                            recordTypeId,
                            layoutData
                        )
                    );

                }
            }

        } catch (Exception ex) {

            return buildMessageSection(
                'Page Layouts',
                objectName,
                'Unable to load page layout metadata: ' + ex.getMessage()
            );

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Page Layouts',
                objectName,
                'No page layouts were returned for this object.'
            );

        }

        return buildTableSection(
            'Page Layouts',
            objectName,
            new List<Map<String, String>>{
                buildColumn('recordType', 'Record Type'),
                buildColumn('recordTypeId', 'Record Type Id'),
                buildColumn('layoutId', 'Layout Id'),
                buildColumn('layoutType', 'Layout Type'),
                buildColumn('mode', 'Mode'),
                buildColumn('sections', 'Sections'),
                buildColumn('fields', 'Fields'),
                buildColumn('saveOptions', 'Save Options'),
                buildColumn('previewSections', 'Section Headings')
            },
            rows
        );

    }

    private static List<Map<String, Object>>
    buildPageLayoutsFromLayoutData(
        String recordTypeName,
        String recordTypeId,
        Map<String, Object> layoutData
    ) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (layoutData == null || layoutData.isEmpty()) {
            return rows;
        }

        if (layoutData.containsKey('layouts')) {

            for (Object layoutObj :
                getObjectList(layoutData, 'layouts')) {

                Map<String, Object> layout =
                    (Map<String, Object>) layoutObj;

                rows.add(
                    buildPageLayoutRow(
                        recordTypeName,
                        recordTypeId,
                        layout
                    )
                );

            }

            return rows;

        }

        rows.add(
            buildPageLayoutRow(
                recordTypeName,
                recordTypeId,
                layoutData
            )
        );

        return rows;

    }

    private static Map<String, Object>
    buildPageLayoutRow(
        String recordTypeName,
        String recordTypeId,
        Map<String, Object> layout
    ) {

        if (layout == null) {
            return new Map<String, Object>();
        }

        String layoutId =
            getString(layout, 'id', 'N/A');

        String layoutType =
            getString(layout, 'layoutType', 'Page Layout');
        String mode =
            getString(layout, 'mode', 'View');

        List<Object> sections =
            getPrimaryLayoutSections(layout);

        return new Map<String, Object>{
            'recordType' => String.isBlank(recordTypeName)
                ? 'Default'
                : recordTypeName,
            'recordTypeId' => String.isBlank(recordTypeId)
                ? 'Default'
                : recordTypeId,
            'layoutId' => layoutId,
            'layoutType' => String.isBlank(layoutType)
                ? 'Page Layout'
                : layoutType,
            'mode' => String.isBlank(mode)
                ? 'View'
                : mode,
            'sections' => getListSize(sections),
            'fields' => countLayoutFields(layout),
            'saveOptions' =>
                formatSaveOptions(
                    getObjectList(layout, 'saveOptions')
                ),
            'previewSections' => getPreviewSectionHeadings(layout)
        };

    }

    private static String
    formatSaveOptions(List<Object> saveOptions) {

        if (saveOptions == null
            || saveOptions.isEmpty()) {

            return 'None';

        }

        List<String> parts =
            new List<String>();

        for (Object optionObj : saveOptions) {

            if (!(optionObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> option =
                (Map<String, Object>) optionObj;

            String label =
                getString(option, 'label', '');

            if (String.isBlank(label)) {
                label =
                    getString(option, 'name', '');
            }

            if (String.isBlank(label)) {
                continue;
            }

            if (getBoolean(option, 'isDefault')) {
                label += ' (Default)';
            }

            parts.add(label);

        }

        return parts.isEmpty()
            ? 'None'
            : String.join(parts, ' | ');

    }

    private static List<Object>
    getPrimaryLayoutSections(Map<String, Object> layout) {

        List<Object> sections =
            new List<Object>();

        sections.addAll(
            getObjectList(layout, 'detailLayoutSections')
        );

        if (!sections.isEmpty()) {
            return sections;
        }

        sections.addAll(getObjectList(layout, 'sections'));
        sections.addAll(getObjectList(layout, 'layoutSections'));

        return sections;

    }

    private static String
    normalizeMetadataPath(String url) {

        if (String.isBlank(url)) {
            return '';
        }

        Integer baseIndex =
            url.indexOf('/services/data/');

        String relative =
            baseIndex >= 0
                ? url.substring(baseIndex)
                : url;

        if (!relative.startsWith('/services/data/')) {
            return relative.startsWith('/')
                ? relative
                : '/' + relative;
        }

        Integer slashAfterVersion =
            relative.indexOf('/', '/services/data/'.length());

        if (slashAfterVersion < 0) {
            return '';
        }

        return relative.substring(slashAfterVersion);

    }

    private static Map<String, Object>
    getPageLayoutsDescribeSection(String objectName) {

        Map<String, Object> data =
            restGetJson('/sobjects/' + objectName + '/describe/layouts');

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object layoutObj :
            getObjectList(data, 'layouts')) {

            Map<String, Object> layout =
                (Map<String, Object>) layoutObj;

            rows.add(new Map<String, Object>{
                'label' => getString(layout, 'label', 'N/A'),
                'name' => getString(layout, 'name', getString(layout, 'label', 'N/A')),
                'detailButtons' => getListSize(
                    getNestedList(
                        layout,
                        new List<String>{ 'buttonLayoutSection', 'detailButtons' }
                    )
                ),
                'relatedLists' => getListSize(
                    getObjectList(layout, 'relatedLists')
                ),
                'sections' => getListSize(
                    getObjectList(layout, 'layoutSections')
                )
            });

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Page Layouts',
                objectName,
                'No page layouts were returned for this object.'
            );

        }

        return buildTableSection(
            'Page Layouts',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Layout Label'),
                buildColumn('name', 'Layout Name'),
                buildColumn('sections', 'Sections'),
                buildColumn('detailButtons', 'Detail Buttons'),
                buildColumn('relatedLists', 'Related Lists')
            },
            rows
        );

    }

    private static Integer
    countLayoutFields(Map<String, Object> layout) {

        Integer fieldCount = 0;

        for (Object sectionObj :
            getPrimaryLayoutSections(layout)) {

            Map<String, Object> section =
                (Map<String, Object>) sectionObj;

            for (Object rowObj :
                getObjectList(section, 'layoutRows')) {

                Map<String, Object> row =
                    (Map<String, Object>) rowObj;

                for (Object itemObj :
                    getObjectList(row, 'layoutItems')) {

                    Map<String, Object> item =
                        (Map<String, Object>) itemObj;

                    for (Object componentObj :
                        getObjectList(item, 'layoutComponents')) {

                        Map<String, Object> component =
                            (Map<String, Object>) componentObj;

                        if (String.valueOf(
                            component.get('componentType')
                        ) == 'FIELD') {
                            fieldCount++;
                        }

                    }

                }

            }

        }

        return fieldCount;

    }

    private static String
    getPreviewSectionHeadings(Map<String, Object> layout) {

        List<String> headings = new List<String>();

        for (Object sectionObj :
            getObjectList(layout, 'sections')) {

            Map<String, Object> section =
                (Map<String, Object>) sectionObj;

            String heading =
                getString(section, 'heading', '');

            if (!String.isBlank(heading)) {
                headings.add(normalizeLayoutText(heading));
            }

            if (headings.size() >= 3) {
                break;
            }

        }

        return headings.isEmpty()
            ? 'N/A'
            : String.join(headings, ' | ');

    }

    private static String
    normalizeLayoutText(String value) {

        if (String.isBlank(value)) {
            return value;
        }

        return value
            .replace('&#124;', '|')
            .replace('&amp;', '&')
            .replace('&nbsp;', ' ');

    }

    private static Map<String, Object>
    getCompactLayoutsSection(String objectName) {

        Map<String, Object> data =
            restGetJson('/sobjects/' + objectName + '/describe/compactLayouts');

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object layoutObj :
            getObjectList(data, 'compactLayouts')) {

            Map<String, Object> layout =
                (Map<String, Object>) layoutObj;

            rows.add(new Map<String, Object>{
                'label' => getString(layout, 'label', 'N/A'),
                'name' => getString(layout, 'name', 'N/A'),
                'fieldCount' => getListSize(getObjectList(layout, 'fieldItems')),
                'actions' => getListSize(getObjectList(layout, 'actions'))
            });

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Compact Layouts',
                objectName,
                'No compact layouts were returned for this object.'
            );

        }

        return buildTableSection(
            'Compact Layouts',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Layout Label'),
                buildColumn('name', 'Layout Name'),
                buildColumn('fieldCount', 'Fields'),
                buildColumn('actions', 'Actions')
            },
            rows
        );

    }

    private static Map<String, Object>
    getButtonsLinksActionsSection(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();
        rows.addAll(
            getButtonsLinksActionLayoutRows(objectName)
        );
        rows.addAll(
            getButtonsLinksActionWebLinkRows(objectName)
        );
        rows.addAll(
            getButtonsLinksActionQuickActionRows(objectName)
        );
        rows.addAll(
            getButtonsLinksActionPublisherRows(objectName)
        );

        rows =
            normalizeButtonsLinksActionRows(rows);

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Buttons, Links, and Actions',
                objectName,
                'No object-level buttons, links, or actions were returned for this object.'
            );

        }

        return buildTableSection(
            'Buttons, Links, and Actions',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Label'),
                buildColumn('name', 'API Name'),
                buildColumn('source', 'Source'),
                buildColumn('extra', 'Details'),
                buildColumn('editAction', 'Edit')
            },
            rows
        );

    }

    private static List<Map<String, Object>>
    getButtonsLinksActionLayoutRows(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            Map<String, Object> data =
                restGetJson('/sobjects/' + objectName + '/describe/layouts');

            for (Object layoutObj :
                getObjectList(data, 'layouts')) {

                Map<String, Object> layout =
                    (Map<String, Object>) layoutObj;
                Map<String, Object> buttonSection =
                    getMap(layout, 'buttonLayoutSection');
                String layoutLabel =
                    getString(layout, 'label', getString(layout, 'name', 'Layout'));

                rows.addAll(
                    buildLayoutButtonRows(
                        objectName,
                        layoutLabel,
                        'Detail Button',
                        getObjectList(buttonSection, 'detailButtons')
                    )
                );
                rows.addAll(
                    buildLayoutButtonRows(
                        objectName,
                        layoutLabel,
                        'List Button',
                        getObjectList(buttonSection, 'listButtons')
                    )
                );
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to query layout buttons for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    buildLayoutButtonRows(
        String objectName,
        String layoutLabel,
        String buttonGroup,
        List<Object> buttonItems
    ) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object buttonObj : buttonItems) {

            if (!(buttonObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> button =
                (Map<String, Object>) buttonObj;

            String label =
                getFirstNonBlank(
                    new List<String>{
                        getString(button, 'label', ''),
                        getString(button, 'title', ''),
                        getString(button, 'name', '')
                    },
                    'N/A'
                );
            String apiName =
                getFirstNonBlank(
                    new List<String>{
                        getString(button, 'name', ''),
                        getString(button, 'apiName', ''),
                        getString(button, 'id', '')
                    },
                    'N/A'
                );
            String sourceType =
                resolveLayoutButtonSource(button);
            String actionToken =
                resolveButtonsLinksActionToken(button);
            if (sourceType == 'Standard Page') {
                actionToken =
                    getFirstNonBlank(
                        new List<String>{
                            normalizeButtonsLinksActionToken(
                                getString(button, 'name', '')
                            ),
                            normalizeButtonsLinksActionToken(
                                getString(button, 'apiName', '')
                            ),
                            actionToken
                        },
                        ''
                    );
            }
            String details =
                buttonGroup +
                ' | Layout: ' + layoutLabel +
                ' | Custom: ' +
                yesNo(
                    getBooleanFromValue(
                        button.containsKey('custom')
                            ? button.get('custom')
                            : button.get('isCustom')
                    )
                );
            String editUrl =
                buildButtonsLinksActionSetupUrl(
                    objectName,
                    actionToken,
                    sourceType
                );
            if (String.isBlank(editUrl)) {
                editUrl =
                    buildButtonsLinksActionsHomeUrl(objectName);
            }

            rows.add(
                new Map<String, Object>{
                    'source' => sourceType,
                    'label' => label,
                    'name' => apiName,
                    'extra' => details,
                    'editAction' => 'Edit',
                    'editUrl' => editUrl,
                    'canEdit' => !String.isBlank(editUrl)
                }
            );
        }

        return rows;

    }

    private static String
    resolveButtonsLinksActionToken(
        Map<String, Object> button
    ) {

        if (button == null) {
            return '';
        }

        String idToken =
            normalizeSalesforceId(
                getString(button, 'id', '')
            );

        if (!String.isBlank(idToken)) {
            return idToken;
        }

        String rawUrl =
            getString(button, 'url', '');

        if (!String.isBlank(rawUrl)) {
            String lidToken =
                extractQueryStringParameter(rawUrl, 'lid');
            String normalizedLid =
                normalizeSalesforceId(lidToken);

            if (!String.isBlank(normalizedLid)) {
                return normalizedLid;
            }
        }
        return '';

    }

    private static String
    resolveLayoutButtonSource(Map<String, Object> button) {

        if (button == null) {
            return 'Standard Page';
        }

        String contentSource =
            getString(button, 'contentSource', '').toLowerCase();
        Boolean isCustom =
            getBooleanFromValue(
                button.containsKey('custom')
                    ? button.get('custom')
                    : button.get('isCustom')
            );

        if (contentSource == 'url') {
            return 'URL';
        }

        if (isCustom) {
            return 'Custom Action';
        }

        return 'Standard Page';

    }

    private static String
    extractQueryStringParameter(
        String url,
        String key
    ) {

        if (String.isBlank(url)
            || String.isBlank(key)) {
            return '';
        }

        Pattern keyPattern =
            Pattern.compile(
                '(?i)(?:^|[?&])' +
                Pattern.quote(key) +
                '=([^&#]+)'
            );
        Matcher matcher =
            keyPattern.matcher(url);

        if (!matcher.find()) {
            return '';
        }

        return matcher.group(1);

    }

    private static String
    normalizeButtonsLinksActionToken(String token) {

        if (String.isBlank(token)) {
            return '';
        }

        String trimmed =
            token.trim();

        if (Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', trimmed)) {
            return trimmed;
        }

        return Pattern.matches('^[a-zA-Z0-9_]+$', trimmed)
            ? trimmed
            : '';

    }

    private static List<Map<String, Object>>
    normalizeButtonsLinksActionRows(
        List<Map<String, Object>> rows
    ) {

        if (rows == null || rows.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> cleanedRows =
            new List<Map<String, Object>>();
        Set<String> seenKeys =
            new Set<String>();

        for (Map<String, Object> row : rows) {

            String source =
                getString(row, 'source', 'N/A');
            String label =
                getString(row, 'label', 'N/A');
            String apiName =
                getString(row, 'name', 'N/A');
            String details =
                getString(row, 'extra', 'N/A');
            String uniqueKey =
                (
                    source + '|' +
                    label + '|' +
                    apiName + '|' +
                    details
                )
                .toLowerCase();

            if (seenKeys.contains(uniqueKey)) {
                continue;
            }

            seenKeys.add(uniqueKey);
            cleanedRows.add(row);
        }

        cleanedRows.sort(new ButtonsLinksActionComparator());
        return cleanedRows;

    }

    public class ButtonsLinksActionComparator
    implements Comparator<Map<String, Object>> {

        public Integer compare(
            Map<String, Object> firstRow,
            Map<String, Object> secondRow
        ) {

            String firstLabel =
                getString(firstRow, 'label', '');
            String secondLabel =
                getString(secondRow, 'label', '');

            Integer labelComparison =
                firstLabel.toLowerCase().compareTo(secondLabel.toLowerCase());
            if (labelComparison != 0) {
                return labelComparison;
            }

            String firstSource =
                getString(firstRow, 'source', '');
            String secondSource =
                getString(secondRow, 'source', '');
            return firstSource.toLowerCase().compareTo(secondSource.toLowerCase());

        }

    }

    private static List<Map<String, Object>>
    getButtonsLinksActionWebLinkRows(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            List<Map<String, Object>> webLinks =
                toolingQuery(
                    'SELECT Id, Name, MasterLabel, DisplayType, LinkType, OpenType ' +
                    'FROM WebLink ' +
                    'WHERE EntityDefinitionId = \'' +
                    escapeSoql(objectName) +
                    '\' ' +
                    'ORDER BY MasterLabel'
                );

            for (Map<String, Object> webLink : webLinks) {
                String webLinkId =
                    normalizeSalesforceId(getString(webLink, 'Id', ''));
                String webLinkName =
                    getString(webLink, 'Name', 'N/A');
                String webLinkLabel =
                    getString(webLink, 'MasterLabel', 'N/A');
                String editUrl =
                    buildButtonsLinksActionSetupUrl(
                        objectName,
                        webLinkId,
                        'Button/Link'
                    );

                rows.add(new Map<String, Object>{
                    'source' => 'Button/Link',
                    'label' => webLinkLabel,
                    'name' => webLinkName,
                    'extra' => formatWebLinkDetails(webLink),
                    'editAction' => 'Edit',
                    'editUrl' => editUrl,
            'canEdit' => !String.isBlank(editUrl)
        });
    }
} catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to query object buttons/links for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getButtonsLinksActionQuickActionRows(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            List<Map<String, Object>> quickActions =
                toolingQuery(
                    'SELECT Id, DeveloperName, MasterLabel, Type, ActionSubtype, TargetSobjectType ' +
                    'FROM QuickActionDefinition ' +
                    'WHERE SobjectType = \'' +
                    escapeSoql(objectName) +
                    '\' ' +
                    'ORDER BY MasterLabel'
                );

            for (Map<String, Object> quickAction : quickActions) {
                String quickActionId =
                    normalizeSalesforceId(getString(quickAction, 'Id', ''));
                String editUrl =
                    buildButtonsLinksActionSetupUrl(
                        objectName,
                        quickActionId,
                        'Action'
                    );

                rows.add(new Map<String, Object>{
                    'source' => 'Action',
                    'label' => getString(quickAction, 'MasterLabel', 'N/A'),
                    'name' => getString(quickAction, 'DeveloperName', 'N/A'),
                    'extra' => formatQuickActionDetails(quickAction),
                    'editAction' => 'Edit',
                    'editUrl' => editUrl,
                    'canEdit' => !String.isBlank(editUrl)
                });
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to query object actions for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static List<Map<String, Object>>
    getButtonsLinksActionPublisherRows(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        if (String.isBlank(objectName)) {
            return rows;
        }

        try {
            List<Map<String, Object>> publisherActions =
                toolingQuery(
                    'SELECT Id, DeveloperName, MasterLabel, DisplayType, ActionType, ActionSubtype, SobjectType ' +
                    'FROM PublisherAction ' +
                    'WHERE SobjectType = \'' +
                    escapeSoql(objectName) +
                    '\' ' +
                    'ORDER BY MasterLabel'
                );

            for (Map<String, Object> action : publisherActions) {
                String actionId =
                    normalizeSalesforceId(getString(action, 'Id', ''));
                String editUrl =
                    buildButtonsLinksActionSetupUrl(
                        objectName,
                        actionId,
                        'Publisher Action'
                    );

                rows.add(new Map<String, Object>{
                    'source' => 'Publisher Action',
                    'label' => getString(action, 'MasterLabel', 'N/A'),
                    'name' => getString(action, 'DeveloperName', 'N/A'),
                    'extra' => formatPublisherActionDetails(action),
                    'editAction' => 'Edit',
                    'editUrl' => editUrl,
                    'canEdit' => !String.isBlank(editUrl)
                });
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to query publisher actions for ' +
                objectName +
                ': ' +
                ex.getMessage()
            );
        }

        return rows;

    }

    private static String
    formatPublisherActionDetails(Map<String, Object> action) {

        List<String> parts =
            new List<String>();

        String displayType =
            getString(action, 'DisplayType', '');
        String actionType =
            getString(action, 'ActionType', '');
        String actionSubtype =
            getString(action, 'ActionSubtype', '');

        if (!String.isBlank(displayType)) {
            parts.add('Display: ' + displayType);
        }

        if (!String.isBlank(actionType)) {
            parts.add('Type: ' + actionType);
        }

        if (!String.isBlank(actionSubtype)) {
            parts.add('Subtype: ' + actionSubtype);
        }

        return parts.isEmpty()
            ? 'Publisher action'
            : String.join(parts, ' | ');

    }

    private static String
    buildButtonsLinksActionSetupUrl(
        String objectName,
        String actionId,
        String sourceType
    ) {

        if (String.isBlank(objectName)) {
            return '';
        }

        String normalizedActionId =
            normalizeButtonsLinksActionToken(actionId);

        if (String.isBlank(normalizedActionId)) {
            return '';
        }

        String normalizedSourceType =
            String.isBlank(sourceType)
                ? ''
                : sourceType.trim().toLowerCase();
        String actionPath =
            normalizedSourceType == 'standard page'
                ? '/editStandardAction'
                : '/edit';

        return '/lightning/setup/ObjectManager/' +
            EncodingUtil.urlEncode(objectName, 'UTF-8') +
            '/ButtonsLinksActions/' +
            EncodingUtil.urlEncode(normalizedActionId, 'UTF-8') +
            actionPath;

    }

    private static String
    buildButtonsLinksActionsHomeUrl(String objectName) {

        if (String.isBlank(objectName)) {
            return '';
        }

        return '/lightning/setup/ObjectManager/' +
            EncodingUtil.urlEncode(objectName, 'UTF-8') +
            '/ButtonsLinksActions/view';

    }

    private static String
    formatWebLinkDetails(Map<String, Object> webLink) {

        List<String> parts =
            new List<String>();

        String linkType =
            getString(webLink, 'LinkType', '');
        String displayType =
            getString(webLink, 'DisplayType', '');
        String openType =
            getString(webLink, 'OpenType', '');

        if (!String.isBlank(linkType)) {
            parts.add('Type: ' + linkType);
        }

        if (!String.isBlank(displayType)) {
            parts.add('Display: ' + displayType);
        }

        if (!String.isBlank(openType)) {
            parts.add('Open: ' + openType);
        }

        return parts.isEmpty()
            ? 'Custom button/link'
            : String.join(parts, ' | ');

    }

    private static String
    formatQuickActionDetails(Map<String, Object> quickAction) {

        List<String> parts =
            new List<String>();

        String actionType =
            getString(quickAction, 'Type', '');
        String actionSubtype =
            getString(quickAction, 'ActionSubtype', '');
        String targetSobjectType =
            getString(quickAction, 'TargetSobjectType', '');

        if (!String.isBlank(actionType)) {
            parts.add('Type: ' + actionType);
        }

        if (!String.isBlank(actionSubtype)) {
            parts.add('Subtype: ' + actionSubtype);
        }

        if (!String.isBlank(targetSobjectType)) {
            parts.add('Target: ' + targetSobjectType);
        }

        return parts.isEmpty()
            ? 'Object-specific action'
            : String.join(parts, ' | ');


            
    }

    private static Map<String, Object>
    getListViewButtonLayoutSection(String objectName) {

        Map<String, Object> data =
            restGetJson('/sobjects/' + objectName + '/describe/layouts');

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object layoutObj :
            getObjectList(data, 'layouts')) {

            Map<String, Object> layout =
                (Map<String, Object>) layoutObj;

            for (Object relatedListObj :
                getObjectList(layout, 'relatedLists')) {

                Map<String, Object> relatedList =
                    (Map<String, Object>) relatedListObj;

                for (Object buttonObj :
                    getObjectList(relatedList, 'buttons')) {

                    Map<String, Object> button =
                        (Map<String, Object>) buttonObj;

                    rows.add(new Map<String, Object>{
                        'relatedList' => getString(relatedList, 'label', 'N/A'),
                        'label' => getString(button, 'label', 'N/A'),
                        'name' => getString(button, 'name', 'N/A'),
                        'custom' => yesNo(getBoolean(button, 'custom'))
                    });

                }
            }
        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'List View Button Layout',
                objectName,
                'No related-list button layout metadata was returned for this object.'
            );

        }

        return buildTableSection(
            'List View Button Layout',
            objectName,
            new List<Map<String, String>>{
                buildColumn('relatedList', 'Related List'),
                buildColumn('label', 'Button Label'),
                buildColumn('name', 'API Name'),
                buildColumn('custom', 'Custom')
            },
            rows
        );

    }

    private static Map<String, Object>
    getSearchLayoutsSection(String objectName) {

        Map<String, Object> data =
            restGetJson('/search/layout?q=' + EncodingUtil.urlEncode(objectName, 'UTF-8'));

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object layoutObj :
            getObjectList(data, 'value')) {

            Map<String, Object> layout =
                (Map<String, Object>) layoutObj;

            for (Object columnObj :
                getObjectList(layout, 'searchColumns')) {

                Map<String, Object> column =
                    (Map<String, Object>) columnObj;

                rows.add(new Map<String, Object>{
                    'layout' => getString(layout, 'label', 'N/A'),
                    'label' => getString(column, 'label', 'N/A'),
                    'apiName' => getString(column, 'name', 'N/A'),
                    'sourceField' => getString(column, 'field', 'N/A')
                });

            }
        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Search Layouts',
                objectName,
                'No search layout columns were returned for this object.'
            );

        }

        return buildTableSection(
            'Search Layouts',
            objectName,
            new List<Map<String, String>>{
                buildColumn('layout', 'Layout'),
                buildColumn('label', 'Column Label'),
                buildColumn('apiName', 'API Name'),
                buildColumn('sourceField', 'Source Field')
            },
            rows
        );

    }

    private static Map<String, Object>
    getLightningRecordPagesSection(String objectName) {

        List<Map<String, Object>> entityRows =
            toolingQuery(
                'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = \'' +
                escapeSoql(objectName) +
                '\' LIMIT 1'
            );

        if (entityRows.isEmpty()) {

            return buildMessageSection(
                'Lightning Record Pages',
                objectName,
                'No entity definition was found for this object.'
            );

        }

        String entityDefinitionId =
            String.valueOf(entityRows[0].get('DurableId'));

        List<Map<String, Object>> rows =
            toolingQuery(
                'SELECT Id, DeveloperName, MasterLabel, Type, EntityDefinitionId ' +
                'FROM FlexiPage ' +
                'WHERE Type = \'RecordPage\' ' +
                'AND EntityDefinitionId = \'' + escapeSoql(entityDefinitionId) + '\' ' +
                'ORDER BY MasterLabel'
            );

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Lightning Record Pages',
                objectName,
                'No Lightning Record Pages are associated with this object in this org.'
            );

        }

        return buildTableSection(
            'Lightning Record Pages',
            objectName,
            new List<Map<String, String>>{
                buildColumn('MasterLabel', 'Label'),
                buildColumn('DeveloperName', 'Developer Name'),
                buildColumn('Type', 'Type'),
                buildColumn('Id', 'Page Id')
            },
            rows
        );

    }

    private static Map<String, Object>
    getFieldSetsSection(String objectName) {

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectName)) {

            return buildMessageSection(
                'Field Sets',
                objectName,
                'No entity definition was found for this object.'
            );

        }

        Schema.DescribeSObjectResult objectDescribe =
            globalMap.get(objectName).getDescribe();

        Map<String, Schema.FieldSet> fieldSetMap =
            objectDescribe.fieldSets.getMap();

        List<String> fieldSetNames =
            new List<String>();

        fieldSetNames.addAll(fieldSetMap.keySet());
        fieldSetNames.sort();

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (String fieldSetName : fieldSetNames) {

            Schema.FieldSet fieldSet =
                fieldSetMap.get(fieldSetName);

            Integer requiredFieldCount = 0;

            for (Schema.FieldSetMember fieldMember :
                fieldSet.getFields()) {

                if (fieldMember.getRequired()) {
                    requiredFieldCount++;
                }

            }

            rows.add(new Map<String, Object>{
                'label' => fieldSet.getLabel(),
                'developerName' => fieldSet.getName(),
                'fieldCount' => fieldSet.getFields().size(),
                'requiredFieldCount' => requiredFieldCount
            });

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Field Sets',
                objectName,
                'No field sets are defined for this object.'
            );

        }

        return buildTableSection(
            'Field Sets',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Field Set Label'),
                buildColumn('developerName', 'Developer Name'),
                buildColumn('fieldCount', 'Fields'),
                buildColumn('requiredFieldCount', 'Required Fields')
            },
            rows
        );

    }

    private static Map<String, Object>
    getObjectLimitsSection(String objectName) {

        Map<String, Object> limits =
            getObjectLimits(objectName);

        if (limits.isEmpty()) {

            return buildMessageSection(
                'Object Limits',
                objectName,
                'No describe metadata was returned for this object.'
            );

        }

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>{
                new Map<String, Object>{
                    'metric' => 'Fields Defined',
                    'value' => limits.get('fieldCount')
                },
                new Map<String, Object>{
                    'metric' => 'Custom Fields Defined',
                    'value' => limits.get('customFieldCount')
                },
                new Map<String, Object>{
                    'metric' => 'Child Relationships',
                    'value' => limits.get('childRelationshipCount')
                },
                new Map<String, Object>{
                    'metric' => 'Record Types',
                    'value' => limits.get('recordTypeCount')
                },
                new Map<String, Object>{
                    'metric' => 'Field Sets',
                    'value' => limits.get('fieldSetCount')
                }
            };

        return buildTableSection(
            'Object Limits',
            objectName,
            new List<Map<String, String>>{
                buildColumn('metric', 'Metric'),
                buildColumn('value', 'Value')
            },
            rows
        );

    }

    private static Map<String, Object>
    getValidationRulesSection(String objectName) {

        List<Map<String, Object>> entityRows =
            toolingQuery(
                'SELECT DurableId FROM EntityDefinition WHERE QualifiedApiName = \'' +
                escapeSoql(objectName) +
                '\' LIMIT 1'
            );

        if (entityRows.isEmpty()) {

            return buildMessageSection(
                'Validation Rules',
                objectName,
                'No entity definition was found for this object.'
            );

        }

        String entityDefinitionId =
            getString(entityRows[0], 'DurableId', '');

        if (String.isBlank(entityDefinitionId)) {
            return buildMessageSection(
                'Validation Rules',
                objectName,
                'Entity definition id was not returned for this object.'
            );
        }

        List<Map<String, Object>> rules =
            toolingQuery(
                'SELECT Id, ValidationName, Active, Description, ErrorDisplayField, ErrorMessage ' +
                'FROM ValidationRule ' +
                'WHERE EntityDefinitionId = \'' + escapeSoql(entityDefinitionId) + '\' ' +
                'ORDER BY ValidationName'
            );

        if (rules.isEmpty()) {

            return buildMessageSection(
                'Validation Rules',
                objectName,
                'No validation rules are defined for this object.'
            );

        }

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Map<String, Object> rule : rules) {
            rows.add(new Map<String, Object>{
                'label' => getString(rule, 'ValidationName', 'N/A'),
                'active' => yesNo(getBoolean(rule, 'Active')),
                'errorField' => getString(rule, 'ErrorDisplayField', 'Top of Page'),
                'errorMessage' => getString(rule, 'ErrorMessage', 'N/A'),
                'description' => getString(rule, 'Description', 'N/A'),
                'id' => getString(rule, 'Id', 'N/A')
            });
        }

        return buildTableSection(
            'Validation Rules',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Rule Name'),
                buildColumn('active', 'Active'),
                buildColumn('errorField', 'Error Location'),
                buildColumn('errorMessage', 'Error Message'),
                buildColumn('description', 'Description'),
                buildColumn('id', 'Id')
            },
            rows
        );

    }

    private static Map<String, Object>
    getRelatedLookupFiltersSection(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Schema.SObjectField fieldRef :
            getFieldMap(objectName).values()) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldRef.getDescribe();

            if (fieldDescribe.getFilteredLookupInfo()
                == null) {

                continue;

            }

            List<String> references =
                new List<String>();

            for (Schema.SObjectType referenceType :
                fieldDescribe.getReferenceTo()) {

                references.add(
                    referenceType.getDescribe().getName()
                );

            }

            Map<String, Object> row =
                new Map<String, Object>();

            row.put('label', fieldDescribe.getLabel());
            row.put('apiName', fieldDescribe.getName());
            row.put(
                'referenceTo',
                references.isEmpty()
                    ? 'N/A'
                    : String.join(references, ', ')
            );
            row.put('status', 'Configured');

            rows.add(row);

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Related Lookup Filters',
                objectName,
                'No lookup filters were found for this object.'
            );

        }

        return buildTableSection(
            'Related Lookup Filters',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Field Label'),
                buildColumn('apiName', 'API Name'),
                buildColumn('referenceTo', 'References'),
                buildColumn('status', 'Filter Status')
            },
            rows
        );

    }

    private static Map<String, Object>
    getHierarchyColumnsSection(String objectName) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Schema.SObjectField fieldRef :
            getFieldMap(objectName).values()) {

            Schema.DescribeFieldResult fieldDescribe =
                fieldRef.getDescribe();

            Boolean isSelfReferencing = false;

            for (Schema.SObjectType referenceType :
                fieldDescribe.getReferenceTo()) {

                if (referenceType.getDescribe().getName()
                    == objectName) {

                    isSelfReferencing = true;
                    break;

                }

            }

            if (!isSelfReferencing) {

                continue;

            }

            Map<String, Object> row =
                new Map<String, Object>();

            row.put('label', fieldDescribe.getLabel());
            row.put('apiName', fieldDescribe.getName());
            row.put(
                'relationshipName',
                String.isBlank(fieldDescribe.getRelationshipName())
                    ? 'N/A'
                    : fieldDescribe.getRelationshipName()
            );
            row.put(
                'type',
                String.valueOf(fieldDescribe.getType())
            );

            rows.add(row);

        }

        if (rows.isEmpty()) {

            return buildMessageSection(
                'Hierarchy Columns',
                objectName,
                'No self-referencing hierarchy fields were found for this object.'
            );

        }

        return buildTableSection(
            'Hierarchy Columns',
            objectName,
            new List<Map<String, String>>{
                buildColumn('label', 'Field Label'),
                buildColumn('apiName', 'API Name'),
                buildColumn('relationshipName', 'Relationship Name'),
                buildColumn('type', 'Field Type')
            },
            rows
        );

    }

    private static Map<String, String>
    buildColumn(String key, String label) {

        return new Map<String, String>{
            'key' => key,
            'label' => label
        };

    }

    private static String
    escapeSoql(String value) {

        return String.valueOf(value).replace('\'', '\\\'');

    }

    private static String
    escapeXml(String value) {

        String safe =
            value == null
                ? ''
                : value;

        safe =
            safe.replace('&', '&amp;');
        safe =
            safe.replace('<', '&lt;');
        safe =
            safe.replace('>', '&gt;');
        safe =
            safe.replace('"', '&quot;');
        safe =
            safe.replace('\'', '&apos;');

        return safe;

    }

    private static String
    yesNo(Boolean value) {

        return value ? 'Yes' : 'No';

    }

    private static Map<String, Object>
    restGetJson(String path) {

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            'callout:'
            + SALESFORCE_NAMED_CREDENTIAL
            + '/services/data/'
            + API_VERSION
            + path
        );
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');

        HttpResponse response =
            new Http().send(request);

        if (response.getStatusCode() < 200
            || response.getStatusCode() >= 300) {

            throw new MetadataRequestException(
                parseErrorMessage(response)
            );

        }

        return (Map<String, Object>) JSON.deserializeUntyped(
            response.getBody()
        );

    }

    private static Map<String, Object>
    restPostJson(String path, Object payload) {

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            'callout:'
            + SALESFORCE_NAMED_CREDENTIAL
            + '/services/data/'
            + API_VERSION
            + path
        );
        request.setMethod('POST');
        request.setHeader('Accept', 'application/json');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(
            JSON.serialize(payload)
        );

        HttpResponse response =
            new Http().send(request);

        if (response.getStatusCode() < 200
            || response.getStatusCode() >= 300) {

            throw new MetadataRequestException(
                parseErrorMessage(response)
            );

        }

        if (String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }

        Object parsed =
            JSON.deserializeUntyped(
                response.getBody()
            );

        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }

        return new Map<String, Object>{
            'rawResponse' => response.getBody()
        };

    }

    private static void
    restDelete(String path) {

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            'callout:'
            + SALESFORCE_NAMED_CREDENTIAL
            + '/services/data/'
            + API_VERSION
            + path
        );
        request.setMethod('DELETE');
        request.setHeader('Accept', 'application/json');

        HttpResponse response =
            new Http().send(request);

        Integer statusCode =
            response.getStatusCode();

        if (statusCode < 200
            || statusCode >= 300) {

            throw new MetadataRequestException(
                parseErrorMessage(response)
            );

        }

    }

    private static List<Map<String, Object>>
    databaseQuery(String soql) {

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (SObject row :
            Database.query(soql)) {

            rows.add(row.getPopulatedFieldsAsMap());

        }

        return rows;

    }

    private static List<Map<String, Object>>
    toolingQuery(String soql) {

        Map<String, Object> data =
            restGetJson(
                '/tooling/query?q='
                + EncodingUtil.urlEncode(soql, 'UTF-8')
            );

        List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        for (Object rowObj :
            getObjectList(data, 'records')) {

            rows.add((Map<String, Object>) rowObj);

        }

        return rows;

    }

    private static String
    parseErrorMessage(HttpResponse response) {

        try {
            Object parsed =
                JSON.deserializeUntyped(response.getBody());

            if (parsed instanceof List<Object>) {

                List<Object> items =
                    (List<Object>) parsed;

                if (!items.isEmpty()) {

                    Map<String, Object> firstError =
                        (Map<String, Object>) items[0];

                    if (firstError.containsKey('message')) {

                        return String.valueOf(firstError.get('message'));

                    }

                }

            }

            if (parsed instanceof Map<String, Object>) {

                Map<String, Object> body =
                    (Map<String, Object>) parsed;

                if (body.containsKey('message')) {

                    return String.valueOf(body.get('message'));

                }

            }
        } catch (Exception ignored) {
        }

        return 'Request failed with status ' + response.getStatusCode();

    }

    private static List<Object>
    getObjectList(
        Map<String, Object> source,
        String key
    ) {

        if (source == null
            || !source.containsKey(key)
            || source.get(key) == null) {

            return new List<Object>();

        }

        return (List<Object>) source.get(key);

    }

    private static List<Object>
    getNestedList(
        Map<String, Object> source,
        List<String> path
    ) {

        Object current =
            source;

        for (String pathPart : path) {

            if (!(current instanceof Map<String, Object>)) {

                return new List<Object>();

            }

            Map<String, Object> currentMap =
                (Map<String, Object>) current;

            if (!currentMap.containsKey(pathPart)
                || currentMap.get(pathPart) == null) {

                return new List<Object>();

            }

            current = currentMap.get(pathPart);

        }

        return current instanceof List<Object>
            ? (List<Object>) current
            : new List<Object>();

    }

    private static Integer
    getListSize(List<Object> values) {

        return values == null
            ? 0
            : values.size();

    }

    private static Map<String, Object>
    getMap(
        Map<String, Object> source,
        String key
    ) {

        if (source == null
            || !source.containsKey(key)
            || !(source.get(key)
                instanceof Map<String, Object>)) {

            return new Map<String, Object>();

        }

        return (Map<String, Object>) source.get(key);

    }

    private static String
    getStringFromValue(Object value) {

        return value == null
            ? ''
            : String.valueOf(value);

    }

    private static String
    getFirstNonBlank(
        List<String> candidates,
        String fallbackValue
    ) {

        if (candidates == null) {
            return fallbackValue;
        }

        for (String candidate : candidates) {
            if (!String.isBlank(candidate)) {
                return candidate;
            }
        }

        return fallbackValue;

    }

    private static String
    getString(
        Map<String, Object> source,
        String key,
        String fallbackValue
    ) {

        if (source == null
            || !source.containsKey(key)
            || source.get(key) == null) {

            return fallbackValue;

        }

        return String.valueOf(source.get(key));

    }

    private static Boolean
    getBoolean(
        Map<String, Object> source,
        String key
    ) {

        if (source == null
            || !source.containsKey(key)
            || source.get(key) == null) {

            return false;

        }

        return (Boolean) source.get(key);

    }

    private static Boolean
    getBooleanFromValue(Object value) {

        if (value == null) {
            return false;
        }

        if (value instanceof Boolean) {
            return (Boolean) value;
        }

        String normalized =
            String.valueOf(value).trim().toLowerCase();

        return normalized == 'true'
            || normalized == '1'
            || normalized == 'yes';

    }

    private static Map<String, Object>
    buildTableSection(
        String title,
        String objectName,
        List<Map<String, String>> columns,
        List<Map<String, Object>> rows
    ) {

        return new Map<String, Object>{
            'title' => title,
            'objectName' => objectName,
            'type' => 'table',
            'columns' => columns,
            'rows' => rows
        };

    }

    private static Map<String, Object>
    buildMessageSection(
        String title,
        String objectName,
        String message
    ) {

        return new Map<String, Object>{
            'title' => title,
            'objectName' => objectName,
            'type' => 'message',
            'message' => message
        };

    }

    private static String
    getSectionTitle(String sectionId) {

        Map<String, String> sectionTitles =
            new Map<String, String>{
                'flows' => 'Flows',
                'pageLayouts' => 'Page Layouts',
                'lightningRecordPages' => 'Lightning Record Pages',
                'buttonsLinksActions' => 'Buttons, Links, and Actions',
                'compactLayouts' => 'Compact Layouts',
                'fieldSets' => 'Field Sets',
                'objectLimits' => 'Object Limits',
                'validationRules' => 'Validation Rules',
                'relatedLookupFilters' => 'Related Lookup Filters',
                'searchLayouts' => 'Search Layouts',
                'listViewButtonLayout' => 'List View Button Layout',
                'hierarchyColumns' => 'Hierarchy Columns',
                'scopingRules' => 'Scoping Rules'
            };

        return sectionTitles.containsKey(sectionId)
            ? sectionTitles.get(sectionId)
            : 'Metadata';

    }

}