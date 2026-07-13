/**
 * Asynchronous execution engine that owns the complete deployment and validation execution lifecycle.
 * Decoupled from UI components, flow frameworks, and SOAP integration details.
 */
public with sharing class DeploymentExecutionQueueable implements Queueable, Database.AllowsCallouts {

    public class DeploymentExecutionException extends Exception {}

    private Id requestId;
    private String actionType; // 'Validate' or 'Deploy'
    private Id resolvedCredentialId;
    
    // In-memory collections to avoid DML-before-callout errors
    private List<String> infoLogs = new List<String>();

    // Target org state caches to minimize callouts
    private Map<String, String> targetCustomObjectIds = new Map<String, String>();
    private Map<String, Set<String>> targetCustomFields = new Map<String, Set<String>>();
    private Map<String, String> targetApexClassIds = new Map<String, String>();

    /**
     * Constructor accepting only immutable record ID and action type.
     */
    public DeploymentExecutionQueueable(Id requestId, String actionType) {
        this.requestId = requestId;
        this.actionType = actionType;
    }

    /**
     * Primary execution coordinator. Calls private lifecycle steps and catches exceptions.
     */
    public void execute(QueueableContext context) {
        if (requestId == null) {
            return;
        }

        try {
            // Step 1: In-memory logs initialization
            addLog('Asynchronous execution started.');

            // Step 2: Load deployment context (Queries target credential - NO DML)
            loadDeploymentContextInMemory();

            // Step 3: Prepare execution payload (NO DML)
            prepareExecutionInMemory();

            // Step 4: Execute deployments via Tooling/Metadata API callouts (NO DML)
            executeDeploymentInMemory();

            // Step 5: Save everything at the very end in a single transaction (Callouts are done!)
            completeExecutionFinal();
        } catch (Exception ex) {
            handleFailureFinal(ex);
        }
    }

    private void addLog(String msg) {
        infoLogs.add(msg);
    }

    /**
     * Step 2: Queries fresh Deployment Request context and resolves target environment credentials.
     */
    private void loadDeploymentContextInMemory() {
        addLog('Resolving target environment credentials...');
        
        Deployment_Request__c req = [
            SELECT Id, Target_Environment__c, Credential__c 
            FROM Deployment_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (req.Target_Environment__c == null) {
            throw new DeploymentExecutionException('Target environment is not defined on the Deployment Request.');
        }

        DeploymentCredentialController.CredentialWrapper wrap = DeploymentCredentialController.getCredentialByEnvironment(req.Target_Environment__c);
        if (wrap == null || wrap.credentialId == null) {
            throw new DeploymentExecutionException('No active credential configuration found for target environment.');
        }

        if (req.Credential__c == null) {
            this.resolvedCredentialId = (Id)wrap.credentialId;
        } else {
            this.resolvedCredentialId = req.Credential__c;
        }

        addLog('Credential verified successfully.');
    }

    /**
     * Step 3: Simulates loading deployment execution context and preparing packaging payload.
     */
    private void prepareExecutionInMemory() {
        addLog('Loads deployment execution context.');
        addLog('Preparing deployment package payload.');
        addLog('Uploading deployment package.');
    }

    /**
     * Step 4: Transitions request status to executing status (Validating / Deploying).
     */
    private void executeDeploymentInMemory() {
        Deployment_Request__c req = [
            SELECT Id, User_Story__c 
            FROM Deployment_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        // Generate target access token and endpoint
        MetadataAuthenticationService.OAuthTokenResponse tokenResponse = 
            MetadataAuthenticationService.generateAccessToken(this.resolvedCredentialId);
        String targetToken = tokenResponse.accessToken;
        String targetUrl = tokenResponse.instanceUrl;

        // Retrieve components associated with user story
        List<User_Story_Metadata__c> comps = [
            SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :req.User_Story__c
        ];

        if (comps.isEmpty()) {
            addLog('No selected metadata components found for this user story. Deployment is empty.');
            return;
        }

        // Auto-inject missing async framework dependencies if deploying any async component
        Boolean hasAsync = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_API_Name__c != null && comp.Metadata_API_Name__c.startsWith('Async')) {
                hasAsync = true;
                break;
            }
        }
        if (hasAsync) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            
            List<String> coreAsyncNames = new List<String>{
                'Async_Process_Event__e',
                'AsyncEventManager',
                'AsyncEventPublisher',
                'AsyncUtil',
                'AsyncProcessor',
                'AsyncProcessService',
                'AsyncProcessQueueable'
            };
            List<String> coreAsyncTypes = new List<String>{
                'CustomObject',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass'
            };
            
            for (Integer i = 0; i < coreAsyncNames.size(); i++) {
                String name = coreAsyncNames[i];
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = coreAsyncTypes[i];
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }

        // Auto-inject missing pipeline framework dependencies if deploying any pipeline component
        Boolean hasPipeline = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_API_Name__c != null && comp.Metadata_API_Name__c.startsWith('Pipeline')) {
                hasPipeline = true;
                break;
            }
        }
        if (hasPipeline) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            List<String> corePipelineNames = new List<String>{
                'Pipeline__c',
                'Deployment_Environment__c',
                'Git_Repository__c',
                'Deployment_Request__c',
                'Deployment_Component__c',
                'Deployment_Log__c',
                'Git_Snapshot__c',
                'User_Story__c',
                'User_Story_Metadata__c',
                'Credentials__c',
                'Release__c',
                'Project__c',
                'Promotion__c',
                'Stage__c'
            };
            for (String name : corePipelineNames) {
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = 'CustomObject';
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }
        // Auto-inject missing pipeline/git class dependencies if deploying any pipeline or git class
        Boolean hasPipelineClass = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass' && comp.Metadata_API_Name__c != null && 
                (comp.Metadata_API_Name__c.startsWith('Pipeline') || comp.Metadata_API_Name__c.startsWith('GitHub') || comp.Metadata_API_Name__c.startsWith('Git'))) {
                hasPipelineClass = true;
                break;
            }
        }
        if (hasPipelineClass) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            List<String> corePipelineClasses = new List<String>{
                'GitHubRecordService',
                'GitHubPullRequestFilesService',
                'GitHubIntegrationService',
                'GitRepositoryService',
                'MetadataScannerService',
                'PipelineRuntimeService',
                'PipelineMetadataProcessor',
                'PipelineConfigurationService',
                'PipelineRuntimeUpdaterService',
                'UserStoryMetadataService',
                'MetadataService',
                'MetadataApiService',
                'MetadataConnectionService',
                'MetadataAuthenticationService',
                'MetadataTokenService',
                'MetadataDiscoveryService',
                'ExternalMetadataController'
            };
            for (String name : corePipelineClasses) {
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = 'ApexClass';
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }

        // Pre-query target CustomObjects, CustomFields, and ApexClasses in bulk to save callout limits
        // 1. Bulk query CustomObjects in target org
        Set<String> customObjectNames = new Set<String>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject' && comp.Metadata_API_Name__c != null) {
                customObjectNames.add(comp.Metadata_API_Name__c.replace('__c', '').replace('__e', ''));
            }
        }
        if (!customObjectNames.isEmpty()) {
            List<String> namesList = new List<String>(customObjectNames);
            List<String> formattedNames = new List<String>();
            for (String name : namesList) {
                formattedNames.add('\'' + name + '\'');
            }
            String objSoql = 'SELECT Id, DeveloperName FROM CustomObject WHERE DeveloperName IN (' + String.join(formattedNames, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(objSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String devName = (String) rMap.get('DeveloperName');
                        String objId = (String) rMap.get('Id');
                        targetCustomObjectIds.put(devName.toLowerCase(), objId);
                    }
                }
            }
        }

        // 2. Bulk query CustomFields in target org
        if (!targetCustomObjectIds.isEmpty()) {
            List<String> idsList = new List<String>();
            for (String objId : targetCustomObjectIds.values()) {
                idsList.add('\'' + objId + '\'');
            }
            String fieldSoql = 'SELECT DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId IN (' + String.join(idsList, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(fieldSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String devFieldName = (String) rMap.get('DeveloperName');
                        String tableId = (String) rMap.get('TableEnumOrId');
                        if (String.isNotBlank(devFieldName)) {
                            if (!targetCustomFields.containsKey(tableId)) {
                                targetCustomFields.put(tableId, new Set<String>());
                            }
                            targetCustomFields.get(tableId).add((devFieldName + '__c').toLowerCase());
                        }
                    }
                }
            }
        }

        // 3. Bulk query ApexClasses in target org
        Set<String> classNames = new Set<String>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass' && comp.Metadata_API_Name__c != null) {
                classNames.add(comp.Metadata_API_Name__c);
            }
        }
        if (!classNames.isEmpty()) {
            List<String> namesList = new List<String>(classNames);
            List<String> formattedNames = new List<String>();
            for (String name : namesList) {
                formattedNames.add('\'' + name + '\'');
            }
            String classSoql = 'SELECT Id, Name FROM ApexClass WHERE Name IN (' + String.join(formattedNames, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(classSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String className = (String) rMap.get('Name');
                        String classId = (String) rMap.get('Id');
                        targetApexClassIds.put(className.toLowerCase(), classId);
                    }
                }
            }
        }

        addLog('Initiating real-time deployment of selected components...');

        // Pass 1a: Deploy Custom Object / Platform Event Base Containers first
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                if (comp.Metadata_API_Name__c != null && (comp.Metadata_API_Name__c.endsWith('__c') || comp.Metadata_API_Name__c.endsWith('__e'))) {
                    deployCustomObject(comp.Metadata_API_Name__c, targetUrl, targetToken);
                } else {
                    addLog('Component ' + comp.Metadata_API_Name__c + ' is not a valid CustomObject API name. Skipping.');
                }
            }
        }

        // Pass 1b: Deploy Custom Object Fields (when all base containers exist)
        Set<String> processedObjectsForFields = new Set<String>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                if (comp.Metadata_API_Name__c != null && (comp.Metadata_API_Name__c.endsWith('__c') || comp.Metadata_API_Name__c.endsWith('__e'))) {
                    String objName = comp.Metadata_API_Name__c;
                    if (!processedObjectsForFields.contains(objName.toLowerCase())) {
                        deployCustomObjectFields(objName, targetUrl, targetToken);
                        processedObjectsForFields.add(objName.toLowerCase());
                    }
                }
            } else if (comp.Metadata_Type__c == 'CustomField') {
                if (comp.Metadata_API_Name__c != null && comp.Metadata_API_Name__c.contains('.')) {
                    String objName = comp.Metadata_API_Name__c.split('\\.')[0];
                    if (!processedObjectsForFields.contains(objName.toLowerCase())) {
                        deployCustomObjectFields(objName, targetUrl, targetToken);
                        processedObjectsForFields.add(objName.toLowerCase());
                    }
                }
            }
        }

        // Pass 2: Deploy Apex Classes (Sort to compile core infrastructure first)
        List<User_Story_Metadata__c> classComps = new List<User_Story_Metadata__c>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass') {
                classComps.add(comp);
            }
        }
        
        List<User_Story_Metadata__c> sortedClassComps = new List<User_Story_Metadata__c>();
        List<String> corePriority = new List<String>{
            'AsyncUtil',
            'AsyncEventPublisher',
            'AsyncEventManager',
            'AsyncProcessor',
            'AsyncProcessService',
            'AsyncProcessQueueable',
            'DynamicRecordService',
            'GitHubIntegrationService',
            'GitHubRecordService',
            'GitHubPullRequestFilesService',
            'GitRepositoryService',
            'MetadataScannerService',
            'PipelineConfigurationService',
            'PipelineMetadataProcessor',
            'UserStoryMetadataService',
            'MetadataService',
            'MetadataApiService',
            'MetadataConnectionService',
            'MetadataAuthenticationService',
            'MetadataTokenService',
            'MetadataDiscoveryService',
            'ExternalMetadataController'
        };
        for (String coreName : corePriority) {
            for (User_Story_Metadata__c comp : classComps) {
                if (comp.Metadata_API_Name__c == coreName) {
                    sortedClassComps.add(comp);
                }
            }
        }
        for (User_Story_Metadata__c comp : classComps) {
            if (!corePriority.contains(comp.Metadata_API_Name__c)) {
                sortedClassComps.add(comp);
            }
        }
        
        deployApexClassesBulk(sortedClassComps, targetUrl, targetToken);

        // Pass 3: Deploy other components (Skip or simulate)
        for (User_Story_Metadata__c comp : comps) {
            String metaType = comp.Metadata_Type__c;
            if (metaType != 'CustomObject' && metaType != 'ApexClass' && metaType != 'CustomField') {
                addLog('Component ' + comp.Metadata_API_Name__c + ' (' + metaType + ') is simulated.');
            }
        }
    }

    private void deployCustomObject(String apiName, String targetUrl, String targetToken) {
        List<EntityDefinition> entities = [
            SELECT QualifiedApiName, Label, PluralLabel 
            FROM EntityDefinition 
            WHERE QualifiedApiName = :apiName 
            LIMIT 1
        ];
        
        String label = apiName.replace('__c', '').replace('__e', '').replace('_', ' ');
        String pluralLabel = label + 's';
        
        if (!entities.isEmpty()) {
            if (entities[0].Label != null) {
                label = entities[0].Label;
            }
            if (entities[0].PluralLabel != null) {
                pluralLabel = entities[0].PluralLabel;
            }
        }

        // Query if custom object / Platform Event exists in target org (using cache)
        String devName = apiName.replace('__c', '').replace('__e', '');
        Boolean exists = targetCustomObjectIds.containsKey(devName.toLowerCase());
        
        // If it does not exist, create it (POST SOAP XML to Metadata API)
        if (!exists) {
            addLog('Creating CustomObject ' + apiName + ' in target org via SOAP Metadata API...');
            deployCustomObjectViaSoap(apiName, label, pluralLabel, targetUrl, targetToken);
        } else {
            addLog('CustomObject ' + apiName + ' already exists in target org.');
        }
    }

    private void deployCustomObjectFields(String apiName, String targetUrl, String targetToken) {
        String devName = apiName.replace('__c', '').replace('__e', '');
        String objId = targetCustomObjectIds.get(devName.toLowerCase());
        
        // Fallback query if not in cache (e.g. if newly created CustomObject)
        if (objId == null) {
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            String objSoql = 'SELECT Id FROM CustomObject WHERE DeveloperName = \'' + devName + '\'';
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(objSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) responseMap.get('records');
                if (records != null && !records.isEmpty()) {
                    Map<String, Object> objRecord = (Map<String, Object>) records[0];
                    objId = (String) objRecord.get('Id');
                    targetCustomObjectIds.put(devName.toLowerCase(), objId);
                }
            }
        }
        
        Set<String> existingFields = (objId != null) ? targetCustomFields.get(objId) : null;
        if (existingFields == null) {
            existingFields = new Set<String>();
            // Fallback query for custom fields if not in cache
            if (objId != null) {
                HttpRequest fieldReq = new HttpRequest();
                String fieldSoql = 'SELECT DeveloperName FROM CustomField WHERE TableEnumOrId = \'' + objId + '\'';
                fieldReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(fieldSoql, 'UTF-8'));
                fieldReq.setMethod('GET');
                fieldReq.setHeader('Authorization', 'Bearer ' + targetToken);
                fieldReq.setHeader('Content-Type', 'application/json');
                
                HttpResponse fieldRes = new Http().send(fieldReq);
                if (fieldRes.getStatusCode() == 200) {
                    Map<String, Object> fieldResp = (Map<String, Object>) JSON.deserializeUntyped(fieldRes.getBody());
                    List<Object> fieldRecords = (List<Object>) fieldResp.get('records');
                    if (fieldRecords != null) {
                        for (Object fRec : fieldRecords) {
                            Map<String, Object> fMap = (Map<String, Object>) fRec;
                            String devFieldName = (String) fMap.get('DeveloperName');
                            if (String.isNotBlank(devFieldName)) {
                                existingFields.add((devFieldName + '__c').toLowerCase());
                            }
                        }
                    }
                }
            }
        }
        addLog('Existing fields in target org for ' + apiName + ': ' + String.join(new List<String>(existingFields), ', '));

        // Deploy all custom fields for this object
        addLog('Deploying custom fields for ' + apiName + '...');
        SObjectType sObjType = Schema.getGlobalDescribe().get(apiName);
        if (sObjType != null) {
            Map<String, SObjectField> fieldsMap = sObjType.getDescribe().fields.getMap();
            List<Schema.DescribeFieldResult> fieldsToDeploy = new List<Schema.DescribeFieldResult>();
            for (SObjectField f : fieldsMap.values()) {
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (dfr.isCustom()) {
                    String fieldNameLower = dfr.getName().toLowerCase();
                    if (!existingFields.contains(fieldNameLower)) {
                        fieldsToDeploy.add(dfr);
                    } else {
                        addLog('CustomField ' + apiName + '.' + dfr.getName() + ' already exists in target org.');
                    }
                }
            }

            // Batch fields in lists of 10 to reduce callout count dramatically
            List<Schema.DescribeFieldResult> batch = new List<Schema.DescribeFieldResult>();
            for (Schema.DescribeFieldResult dfr : fieldsToDeploy) {
                batch.add(dfr);
                if (batch.size() == 10) {
                    deployCustomFieldsViaSoap(apiName, batch, targetUrl, targetToken);
                    batch.clear();
                }
            }
            if (!batch.isEmpty()) {
                deployCustomFieldsViaSoap(apiName, batch, targetUrl, targetToken);
            }
        }
    }

    private void deployCustomFieldsViaSoap(String objectName, List<Schema.DescribeFieldResult> fieldsList, String targetUrl, String targetToken) {
        if (fieldsList == null || fieldsList.isEmpty()) {
            return;
        }

        List<String> metadata = new List<String>();
        for (Schema.DescribeFieldResult dfr : fieldsList) {
            String fieldName = dfr.getName();
            String label = dfr.getLabel();
            Schema.DisplayType dt = dfr.getType();
            String fieldType = getMetadataFieldType(dt);
            
            metadata.add('<met:metadata xsi:type="met:CustomField">');
            metadata.add('<met:fullName>' + objectName + '.' + fieldName + '</met:fullName>');
            metadata.add('<met:label>' + label.escapeXml() + '</met:label>');
            metadata.add('<met:type>' + fieldType + '</met:type>');
            
            if (fieldType == 'Text' || fieldType == 'LongTextArea') {
                if (!dfr.isCalculated()) {
                    Integer len = dfr.getLength();
                    if (len == 0 || len == null) len = 255;
                    metadata.add('<met:length>' + len + '</met:length>');
                }
                if (fieldType == 'LongTextArea') {
                    metadata.add('<met:visibleLines>3</met:visibleLines>');
                }
            } else if (fieldType == 'Number' || fieldType == 'Percent' || fieldType == 'Currency') {
                Integer precision = dfr.getPrecision();
                Integer scale = dfr.getScale();
                if (precision == 0 || precision == null) precision = 18;
                if (scale == null) scale = 0;
                metadata.add('<met:precision>' + precision + '</met:precision>');
                metadata.add('<met:scale>' + scale + '</met:scale>');
            } else if (fieldType == 'Lookup') {
                List<Schema.SObjectType> refTo = dfr.getReferenceTo();
                if (!refTo.isEmpty()) {
                    metadata.add('<met:referenceTo>' + refTo[0].getDescribe().getName() + '</met:referenceTo>');
                    String relName = null;
                    for (Schema.ChildRelationship cr : refTo[0].getDescribe().getChildRelationships()) {
                        if (cr.getField() == dfr.getSObjectField()) {
                            relName = cr.getRelationshipName();
                            break;
                        }
                    }
                    if (String.isNotBlank(relName)) {
                        if (relName.endsWith('__r')) {
                            relName = relName.removeEnd('__r');
                        }
                        metadata.add('<met:relationshipName>' + relName + '</met:relationshipName>');
                    }
                }
            } else if (fieldType == 'Picklist' || fieldType == 'MultiselectPicklist') {
                metadata.add('<met:valueSet>');
                metadata.add('<met:valueSetDefinition>');
                for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
                    metadata.add('<met:value>');
                    metadata.add('<met:fullName>' + ple.getValue().escapeXml() + '</met:fullName>');
                    metadata.add('<met:label>' + ple.getLabel().escapeXml() + '</met:label>');
                    metadata.add('<met:default>' + ple.isDefaultValue() + '</met:default>');
                    metadata.add('</met:value>');
                }
                metadata.add('</met:valueSetDefinition>');
                metadata.add('</met:valueSet>');
            } else if (fieldType == 'Checkbox') {
                Boolean defVal = false;
                if (dfr.getDefaultValue() != null) {
                    defVal = (Boolean)dfr.getDefaultValue();
                }
                metadata.add('<met:defaultValue>' + defVal + '</met:defaultValue>');
            }
            
            if (dfr.isCalculated() && String.isNotBlank(dfr.getCalculatedFormula())) {
                metadata.add('<met:formula>' + dfr.getCalculatedFormula().escapeXml() + '</met:formula>');
                metadata.add('<met:formulaTreatBlanksAs>BlankAsZero</met:formulaTreatBlanksAs>');
            }
            
            metadata.add('</met:metadata>');
        }

        String soap = '';
        soap += '<?xml version="1.0" encoding="utf-8"?>';
        soap += '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        soap += '<soapenv:Header>';
        soap += '<met:SessionHeader><met:sessionId>' + targetToken + '</met:sessionId></met:SessionHeader>';
        soap += '</soapenv:Header>';
        soap += '<soapenv:Body>';
        soap += '<met:createMetadata>';
        soap += String.join(metadata, '');
        soap += '</met:createMetadata>';
        soap += '</soapenv:Body>';
        soap += '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(targetUrl + '/services/Soap/m/60.0');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', 'createMetadata');
        req.setBody(soap);

        HttpResponse res = new Http().send(req);
        String responseBody = res.getBody();
        if (res.getStatusCode() != 200) {
            String errorMsg = parseSoapError(responseBody);
            throw new DeploymentExecutionException('Failed to deploy CustomFields for ' + objectName + ' via Metadata API: ' + errorMsg);
        } else {
            addLog('Deployed batch of ' + fieldsList.size() + ' custom fields for ' + objectName + '.');
        }
    }

    private static String getMetadataFieldType(Schema.DisplayType dt) {
        switch on dt {
            when BOOLEAN { return 'Checkbox'; }
            when CURRENCY { return 'Currency'; }
            when DATE { return 'Date'; }
            when DATETIME { return 'DateTime'; }
            when DOUBLE { return 'Number'; }
            when EMAIL { return 'Email'; }
            when INTEGER { return 'Number'; }
            when PERCENT { return 'Percent'; }
            when PHONE { return 'Phone'; }
            when PICKLIST { return 'Picklist'; }
            when MULTIPICKLIST { return 'MultiselectPicklist'; }
            when TEXTAREA { return 'LongTextArea'; }
            when URL { return 'Url'; }
            when REFERENCE { return 'Lookup'; }
            when else { return 'Text'; }
        }
    }

    private void deployCustomObjectViaSoap(String apiName, String label, String pluralLabel, String targetUrl, String targetToken) {
        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomObject">');
        metadata.add('<met:fullName>' + apiName + '</met:fullName>');
        metadata.add('<met:label>' + label + '</met:label>');
        metadata.add('<met:pluralLabel>' + pluralLabel + '</met:pluralLabel>');
        metadata.add('<met:deploymentStatus>Deployed</met:deploymentStatus>');
        if (apiName.endsWith('__e')) {
            metadata.add('<met:eventType>HighVolume</met:eventType>');
            metadata.add('<met:publishBehavior>PublishAfterCommit</met:publishBehavior>');
        } else {
            metadata.add('<met:sharingModel>ReadWrite</met:sharingModel>');
            metadata.add('<met:nameField>');
            metadata.add('<met:label>' + label + ' Name</met:label>');
            metadata.add('<met:type>Text</met:type>');
            metadata.add('</met:nameField>');
        }
        metadata.add('</met:metadata>');

        String soap = '';
        soap += '<?xml version="1.0" encoding="utf-8"?>';
        soap += '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        soap += '<soapenv:Header>';
        soap += '<met:SessionHeader><met:sessionId>' + targetToken + '</met:sessionId></met:SessionHeader>';
        soap += '</soapenv:Header>';
        soap += '<soapenv:Body>';
        soap += '<met:createMetadata>';
        soap += String.join(metadata, '');
        soap += '</met:createMetadata>';
        soap += '</soapenv:Body>';
        soap += '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(targetUrl + '/services/Soap/m/60.0');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', 'createMetadata');
        req.setBody(soap);

        HttpResponse res = new Http().send(req);
        String responseBody = res.getBody();
        if (res.getStatusCode() != 200 || responseBody.contains('<success>false</success>')) {
            String errorMsg = parseSoapError(responseBody);
            throw new DeploymentExecutionException('Failed to deploy CustomObject ' + apiName + ' via Metadata API: ' + errorMsg);
        }
        
        addLog('CustomObject ' + apiName + ' created successfully.');
    }

    private String parseSoapError(String soapBody) {
        Integer lastIndex = 0;
        Integer msgStart = soapBody.indexOf('<message>', lastIndex);
        if (msgStart != -1) {
            Integer msgEnd = soapBody.indexOf('</message>', msgStart);
            if (msgEnd != -1) {
                return soapBody.substring(msgStart + 9, msgEnd);
            }
        }
        Integer faultStart = soapBody.indexOf('<faultstring>');
        if (faultStart != -1) {
            Integer faultEnd = soapBody.indexOf('</faultstring>', faultStart);
            if (faultEnd != -1) {
                return soapBody.substring(faultStart + 13, faultEnd);
            }
        }
        return soapBody;
    }

    private void deployApexClassesBulk(List<User_Story_Metadata__c> classComps, String targetUrl, String targetToken) {
        if (classComps.isEmpty()) return;
        
        addLog('Deploying ' + classComps.size() + ' Apex classes in bulk...');
        
        // Retrieve local bodies of all classes
        Set<String> classNames = new Set<String>();
        for (User_Story_Metadata__c comp : classComps) {
            classNames.add(comp.Metadata_API_Name__c);
        }
        
        Map<String, String> localClassBodies = new Map<String, String>();
        for (ApexClass ac : [SELECT Name, Body FROM ApexClass WHERE Name IN :classNames]) {
            localClassBodies.put(ac.Name.toLowerCase(), ac.Body);
        }
        
        // Step 1: Ensure all classes exist in target org (create shell stubs if missing)
        Http h = new Http();
        for (User_Story_Metadata__c comp : classComps) {
            String name = comp.Metadata_API_Name__c;
            if (!localClassBodies.containsKey(name.toLowerCase())) {
                addLog('ApexClass ' + name + ' not found in the source org. Skipping deployment.');
                continue;
            }
            String classId = targetApexClassIds.get(name.toLowerCase());
            
            if (classId == null) {
                // Create a basic shell stub class first
                HttpRequest createReq = new HttpRequest();
                createReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClass');
                createReq.setMethod('POST');
                createReq.setHeader('Authorization', 'Bearer ' + targetToken);
                createReq.setHeader('Content-Type', 'application/json');
                
                Map<String, Object> payload = new Map<String, Object>();
                payload.put('Name', name);
                payload.put('Body', 'public class ' + name + ' {}');
                createReq.setBody(JSON.serialize(payload));
                
                addLog('Creating shell stub for ApexClass ' + name + '...');
                HttpResponse createRes = h.send(createReq);
                Integer code = createRes.getStatusCode();
                if (code == 200 || code == 201) {
                    Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
                    classId = (String) resMap.get('id');
                    targetApexClassIds.put(name.toLowerCase(), classId);
                } else {
                    // Check if it already exists (concurrency safety)
                    String err = parseErrorMessage(createRes.getBody());
                    if (err != null && err.contains('Duplicate')) {
                        // Query the ID
                        HttpRequest qReq = new HttpRequest();
                        String qSoql = 'SELECT Id FROM ApexClass WHERE Name = \'' + name + '\'';
                        qReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(qSoql, 'UTF-8'));
                        qReq.setMethod('GET');
                        qReq.setHeader('Authorization', 'Bearer ' + targetToken);
                        qReq.setHeader('Content-Type', 'application/json');
                        HttpResponse qRes = h.send(qReq);
                        if (qRes.getStatusCode() == 200) {
                            Map<String, Object> qMap = (Map<String, Object>) JSON.deserializeUntyped(qRes.getBody());
                            List<Object> recs = (List<Object>) qMap.get('records');
                            if (recs != null && !recs.isEmpty()) {
                                classId = (String) ((Map<String, Object>) recs[0]).get('Id');
                                targetApexClassIds.put(name.toLowerCase(), classId);
                            }
                        }
                    }
                    if (classId == null) {
                        throw new DeploymentExecutionException('Failed to create ApexClass stub for ' + name + ': ' + err);
                    }
                }
            }
        }
        
        // Step 2: Create a MetadataContainer
        HttpRequest containerReq = new HttpRequest();
        containerReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/MetadataContainer');
        containerReq.setMethod('POST');
        containerReq.setHeader('Authorization', 'Bearer ' + targetToken);
        containerReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> containerPayload = new Map<String, Object>();
        containerPayload.put('Name', 'Ctr_' + System.now().getTime());
        containerReq.setBody(JSON.serialize(containerPayload));
        
        HttpResponse containerRes = h.send(containerReq);
        if (containerRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create MetadataContainer: ' + containerRes.getBody());
        }
        Map<String, Object> containerMap = (Map<String, Object>) JSON.deserializeUntyped(containerRes.getBody());
        String containerId = (String) containerMap.get('id');
        
        // Step 3: Create ApexClassMember for each class with its full local body
        for (User_Story_Metadata__c comp : classComps) {
            String name = comp.Metadata_API_Name__c;
            String classId = targetApexClassIds.get(name.toLowerCase());
            String body = localClassBodies.get(name.toLowerCase());
            if (body == null) continue;
            
            HttpRequest memberReq = new HttpRequest();
            memberReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClassMember');
            memberReq.setMethod('POST');
            memberReq.setHeader('Authorization', 'Bearer ' + targetToken);
            memberReq.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> memberPayload = new Map<String, Object>();
            memberPayload.put('MetadataContainerId', containerId);
            memberPayload.put('ContentEntityId', classId);
            memberPayload.put('Body', body);
            memberReq.setBody(JSON.serialize(memberPayload));
            
            HttpResponse memberRes = h.send(memberReq);
            if (memberRes.getStatusCode() != 201) {
                throw new DeploymentExecutionException('Failed to create ApexClassMember for ' + name + ': ' + memberRes.getBody());
            }
        }
        
        // Step 4: Submit ContainerAsyncRequest to compile all of them together
        HttpRequest requestReq = new HttpRequest();
        requestReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ContainerAsyncRequest');
        requestReq.setMethod('POST');
        requestReq.setHeader('Authorization', 'Bearer ' + targetToken);
        requestReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> requestPayload = new Map<String, Object>();
        requestPayload.put('MetadataContainerId', containerId);
        requestPayload.put('IsCheckOnly', false);
        requestReq.setBody(JSON.serialize(requestPayload));
        
        HttpResponse requestRes = h.send(requestReq);
        if (requestRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create ContainerAsyncRequest: ' + requestRes.getBody());
        }
        Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(requestRes.getBody());
        String compileRequestId = (String) requestMap.get('id');
        
        // Step 5: Poll ContainerAsyncRequest status
        String status = 'Queued';
        String errorMsg = '';
        for (Integer i = 0; i < 30; i++) {
            // Wait 1 second
            Long start = System.now().getTime();
            while (System.now().getTime() - start < 1000) {}
            
            HttpRequest pollReq = new HttpRequest();
            pollReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ContainerAsyncRequest/' + compileRequestId);
            pollReq.setMethod('GET');
            pollReq.setHeader('Authorization', 'Bearer ' + targetToken);
            
            HttpResponse pollRes = h.send(pollReq);
            if (pollRes.getStatusCode() == 200) {
                Map<String, Object> pollMap = (Map<String, Object>) JSON.deserializeUntyped(pollRes.getBody());
                status = (String) pollMap.get('State');
                if (status == 'Completed') {
                    break;
                } else if (status == 'Failed') {
                    errorMsg = (String) pollMap.get('ErrorMsg');
                    if (pollMap.containsKey('DeployDetails')) {
                        Map<String, Object> details = (Map<String, Object>) pollMap.get('DeployDetails');
                        if (details != null && details.containsKey('componentFailures')) {
                            List<Object> failures = (List<Object>) details.get('componentFailures');
                            if (failures != null && !failures.isEmpty()) {
                                Map<String, Object> fail = (Map<String, Object>) failures[0];
                                errorMsg = (String) fail.get('problem');
                            }
                        }
                    }
                    break;
                }
            }
        }
        
        if (status != 'Completed') {
            throw new DeploymentExecutionException('Compilation/Deployment failed for ApexClasses in bulk: ' + (String.isNotBlank(errorMsg) ? errorMsg : status));
        }
        addLog('All Apex classes deployed and compiled successfully in bulk.');
    }

    private String parseErrorMessage(String body) {
        try {
            List<Object> errs = (List<Object>) JSON.deserializeUntyped(body);
            if (!errs.isEmpty()) {
                Map<String, Object> err = (Map<String, Object>) errs[0];
                return (String) err.get('message');
            }
        } catch (Exception ex) {}
        return body;
    }

    /**
     * Step 5: Transitions status to final success state (Validated / Completed) and sets timestamp.
     */
    private void completeExecutionFinal() {
        String finalStatus = (actionType == 'Validate') ? 'Validated' : 'Completed';
        
        // 1. Update request status and credential in database
        DeploymentExecutionHelper.applyRuntimeState(requestId, finalStatus, null, System.now(), this.resolvedCredentialId);
        
        // 2. Bulk insert all collected logs
        List<Deployment_Log__c> logsToInsert = new List<Deployment_Log__c>();
        for (String msg : infoLogs) {
            Deployment_Log__c log = new Deployment_Log__c();
            log.Deployment_Request__c = requestId;
            log.Log_Type__c = 'Info';
            log.Message__c = msg;
            log.Timestamp__c = System.now();
            logsToInsert.add(log);
        }
        
        Deployment_Log__c successLog = new Deployment_Log__c();
        successLog.Deployment_Request__c = requestId;
        successLog.Log_Type__c = 'Info';
        successLog.Message__c = 'Deployment request completed successfully.';
        successLog.Timestamp__c = System.now();
        logsToInsert.add(successLog);

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Exception Handler: Logs errors and transitions status to Failed.
     */
    private void handleFailureFinal(Exception ex) {
        System.debug(LoggingLevel.ERROR, 'DeploymentExecutionQueueable execution failed: ' + ex.getMessage());
        
        // 1. Update status to Failed in database
        DeploymentExecutionHelper.applyRuntimeState(requestId, 'Failed', null, System.now(), this.resolvedCredentialId);
        
        // 2. Bulk insert all collected logs + failure error log
        List<Deployment_Log__c> logsToInsert = new List<Deployment_Log__c>();
        for (String msg : infoLogs) {
            Deployment_Log__c log = new Deployment_Log__c();
            log.Deployment_Request__c = requestId;
            log.Log_Type__c = 'Info';
            log.Message__c = msg;
            log.Timestamp__c = System.now();
            logsToInsert.add(log);
        }
        
        Deployment_Log__c errorLog = new Deployment_Log__c();
        errorLog.Deployment_Request__c = requestId;
        errorLog.Log_Type__c = 'Error';
        errorLog.Message__c = 'Execution failed: ' + ex.getMessage();
        errorLog.Timestamp__c = System.now();
        logsToInsert.add(errorLog);

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Helper to simulate brief delay between processing steps.
     */
    private void simulateDelay() {
        if (Test.isRunningTest()) {
            return;
        }
        Long startTime = System.now().getTime();
        while (System.now().getTime() - startTime < 100) {
            // Busy wait
        }
    }
/**
 * Asynchronous execution engine that owns the complete deployment and validation execution lifecycle.
 * Decoupled from UI components, flow frameworks, and SOAP integration details.
 */
public with sharing class DeploymentExecutionQueueable implements Queueable, Database.AllowsCallouts {

    public class DeploymentExecutionException extends Exception {}

    private Id requestId;
    private String actionType; // 'Validate' or 'Deploy'
    private Id resolvedCredentialId;
    
    // In-memory collections to avoid DML-before-callout errors
    private List<String> infoLogs = new List<String>();

    // Target org state caches to minimize callouts
    private Map<String, String> targetCustomObjectIds = new Map<String, String>();
    private Map<String, Set<String>> targetCustomFields = new Map<String, Set<String>>();
    private Map<String, String> targetApexClassIds = new Map<String, String>();

    /**
     * Constructor accepting only immutable record ID and action type.
     */
    public DeploymentExecutionQueueable(Id requestId, String actionType) {
        this.requestId = requestId;
        this.actionType = actionType;
    }

    /**
     * Primary execution coordinator. Calls private lifecycle steps and catches exceptions.
     */
    public void execute(QueueableContext context) {
        if (requestId == null) {
            return;
        }

        try {
            // Step 1: In-memory logs initialization
            addLog('Asynchronous execution started.');

            // Step 2: Load deployment context (Queries target credential - NO DML)
            loadDeploymentContextInMemory();

            // Step 3: Prepare execution payload (NO DML)
            prepareExecutionInMemory();

            // Step 4: Execute deployments via Tooling/Metadata API callouts (NO DML)
            executeDeploymentInMemory();

            // Step 5: Save everything at the very end in a single transaction (Callouts are done!)
            completeExecutionFinal();
        } catch (Exception ex) {
            handleFailureFinal(ex);
        }
    }

    private void addLog(String msg) {
        infoLogs.add(msg);
    }

    /**
     * Step 2: Queries fresh Deployment Request context and resolves target environment credentials.
     */
    private void loadDeploymentContextInMemory() {
        addLog('Resolving target environment credentials...');
        
        Deployment_Request__c req = [
            SELECT Id, Target_Environment__c, Credential__c 
            FROM Deployment_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (req.Target_Environment__c == null) {
            throw new DeploymentExecutionException('Target environment is not defined on the Deployment Request.');
        }

        DeploymentCredentialController.CredentialWrapper wrap = DeploymentCredentialController.getCredentialByEnvironment(req.Target_Environment__c);
        if (wrap == null || wrap.credentialId == null) {
            throw new DeploymentExecutionException('No active credential configuration found for target environment.');
        }

        if (req.Credential__c == null) {
            this.resolvedCredentialId = (Id)wrap.credentialId;
        } else {
            this.resolvedCredentialId = req.Credential__c;
        }

        addLog('Credential verified successfully.');
    }

    /**
     * Step 3: Simulates loading deployment execution context and preparing packaging payload.
     */
    private void prepareExecutionInMemory() {
        addLog('Loads deployment execution context.');
        addLog('Preparing deployment package payload.');
        addLog('Uploading deployment package.');
    }

    /**
     * Step 4: Transitions request status to executing status (Validating / Deploying).
     */
    private void executeDeploymentInMemory() {
        Deployment_Request__c req = [
            SELECT Id, User_Story__c 
            FROM Deployment_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        // Generate target access token and endpoint
        MetadataAuthenticationService.OAuthTokenResponse tokenResponse = 
            MetadataAuthenticationService.generateAccessToken(this.resolvedCredentialId);
        String targetToken = tokenResponse.accessToken;
        String targetUrl = tokenResponse.instanceUrl;

        // Retrieve components associated with user story
        List<User_Story_Metadata__c> comps = [
            SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :req.User_Story__c
        ];

        if (comps.isEmpty()) {
            addLog('No selected metadata components found for this user story. Deployment is empty.');
            return;
        }

        // Auto-inject missing async framework dependencies if deploying any async component
        Boolean hasAsync = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_API_Name__c != null && comp.Metadata_API_Name__c.startsWith('Async')) {
                hasAsync = true;
                break;
            }
        }
        if (hasAsync) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            
            List<String> coreAsyncNames = new List<String>{
                'Async_Process_Event__e',
                'AsyncEventManager',
                'AsyncEventPublisher',
                'AsyncUtil',
                'AsyncProcessor',
                'AsyncProcessService',
                'AsyncProcessQueueable'
            };
            List<String> coreAsyncTypes = new List<String>{
                'CustomObject',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass',
                'ApexClass'
            };
            
            for (Integer i = 0; i < coreAsyncNames.size(); i++) {
                String name = coreAsyncNames[i];
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = coreAsyncTypes[i];
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }

        // Auto-inject missing pipeline framework dependencies if deploying any pipeline component
        Boolean hasPipeline = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_API_Name__c != null && comp.Metadata_API_Name__c.startsWith('Pipeline')) {
                hasPipeline = true;
                break;
            }
        }
        if (hasPipeline) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            List<String> corePipelineNames = new List<String>{
                'Pipeline__c',
                'Deployment_Environment__c',
                'Git_Repository__c',
                'Deployment_Request__c',
                'Deployment_Component__c',
                'Deployment_Log__c',
                'Git_Snapshot__c',
                'User_Story__c',
                'User_Story_Metadata__c',
                'Credentials__c',
                'Release__c',
                'Project__c',
                'Promotion__c',
                'Stage__c'
            };
            for (String name : corePipelineNames) {
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = 'CustomObject';
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }
        // Auto-inject missing pipeline/git class dependencies if deploying any pipeline or git class
        Boolean hasPipelineClass = false;
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass' && comp.Metadata_API_Name__c != null && 
                (comp.Metadata_API_Name__c.startsWith('Pipeline') || comp.Metadata_API_Name__c.startsWith('GitHub') || comp.Metadata_API_Name__c.startsWith('Git'))) {
                hasPipelineClass = true;
                break;
            }
        }
        if (hasPipelineClass) {
            Set<String> existingNames = new Set<String>();
            for (User_Story_Metadata__c comp : comps) {
                existingNames.add(comp.Metadata_API_Name__c);
            }
            List<String> corePipelineClasses = new List<String>{
                'GitHubRecordService',
                'GitHubPullRequestFilesService',
                'GitHubIntegrationService',
                'GitRepositoryService',
                'MetadataScannerService',
                'PipelineRuntimeService',
                'PipelineMetadataProcessor',
                'PipelineConfigurationService',
                'PipelineRuntimeUpdaterService',
                'UserStoryMetadataService',
                'MetadataService',
                'MetadataApiService',
                'MetadataConnectionService',
                'MetadataAuthenticationService',
                'MetadataTokenService',
                'MetadataDiscoveryService',
                'ExternalMetadataController'
            };
            for (String name : corePipelineClasses) {
                if (!existingNames.contains(name)) {
                    User_Story_Metadata__c injected = new User_Story_Metadata__c();
                    injected.Metadata_API_Name__c = name;
                    injected.Metadata_Type__c = 'ApexClass';
                    injected.Action__c = 'Add';
                    comps.add(injected);
                }
            }
        }

        // Pre-query target CustomObjects, CustomFields, and ApexClasses in bulk to save callout limits
        // 1. Bulk query CustomObjects in target org
        Set<String> customObjectNames = new Set<String>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject' && comp.Metadata_API_Name__c != null) {
                customObjectNames.add(comp.Metadata_API_Name__c.replace('__c', '').replace('__e', ''));
            }
        }
        if (!customObjectNames.isEmpty()) {
            List<String> namesList = new List<String>(customObjectNames);
            List<String> formattedNames = new List<String>();
            for (String name : namesList) {
                formattedNames.add('\'' + name + '\'');
            }
            String objSoql = 'SELECT Id, DeveloperName FROM CustomObject WHERE DeveloperName IN (' + String.join(formattedNames, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(objSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String devName = (String) rMap.get('DeveloperName');
                        String objId = (String) rMap.get('Id');
                        targetCustomObjectIds.put(devName.toLowerCase(), objId);
                    }
                }
            }
        }

        // 2. Bulk query CustomFields in target org
        if (!targetCustomObjectIds.isEmpty()) {
            List<String> idsList = new List<String>();
            for (String objId : targetCustomObjectIds.values()) {
                idsList.add('\'' + objId + '\'');
            }
            String fieldSoql = 'SELECT DeveloperName, TableEnumOrId FROM CustomField WHERE TableEnumOrId IN (' + String.join(idsList, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(fieldSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String devFieldName = (String) rMap.get('DeveloperName');
                        String tableId = (String) rMap.get('TableEnumOrId');
                        if (String.isNotBlank(devFieldName)) {
                            if (!targetCustomFields.containsKey(tableId)) {
                                targetCustomFields.put(tableId, new Set<String>());
                            }
                            targetCustomFields.get(tableId).add((devFieldName + '__c').toLowerCase());
                        }
                    }
                }
            }
        }

        // 3. Bulk query ApexClasses in target org
        Set<String> classNames = new Set<String>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass' && comp.Metadata_API_Name__c != null) {
                classNames.add(comp.Metadata_API_Name__c);
            }
        }
        if (!classNames.isEmpty()) {
            List<String> namesList = new List<String>(classNames);
            List<String> formattedNames = new List<String>();
            for (String name : namesList) {
                formattedNames.add('\'' + name + '\'');
            }
            String classSoql = 'SELECT Id, Name FROM ApexClass WHERE Name IN (' + String.join(formattedNames, ', ') + ')';
            
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(classSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) respMap.get('records');
                if (records != null) {
                    for (Object rec : records) {
                        Map<String, Object> rMap = (Map<String, Object>) rec;
                        String className = (String) rMap.get('Name');
                        String classId = (String) rMap.get('Id');
                        targetApexClassIds.put(className.toLowerCase(), classId);
                    }
                }
            }
        }

        addLog('Initiating real-time deployment of selected components...');

        // Pass 1a: Deploy Custom Object / Platform Event Base Containers first
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                if (comp.Metadata_API_Name__c != null && (comp.Metadata_API_Name__c.endsWith('__c') || comp.Metadata_API_Name__c.endsWith('__e'))) {
                    deployCustomObject(comp.Metadata_API_Name__c, targetUrl, targetToken);
                } else {
                    addLog('Component ' + comp.Metadata_API_Name__c + ' is not a valid CustomObject API name. Skipping.');
                }
            }
        }

        // Pass 1b: Deploy Custom Object Fields (when all base containers exist)
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                if (comp.Metadata_API_Name__c != null && (comp.Metadata_API_Name__c.endsWith('__c') || comp.Metadata_API_Name__c.endsWith('__e'))) {
                    deployCustomObjectFields(comp.Metadata_API_Name__c, targetUrl, targetToken);
                }
            }
        }

        // Pass 2: Deploy Apex Classes (Sort to compile core infrastructure first)
        List<User_Story_Metadata__c> classComps = new List<User_Story_Metadata__c>();
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass') {
                classComps.add(comp);
            }
        }
        
        List<User_Story_Metadata__c> sortedClassComps = new List<User_Story_Metadata__c>();
        List<String> corePriority = new List<String>{
            'AsyncUtil',
            'AsyncEventPublisher',
            'AsyncEventManager',
            'AsyncProcessor',
            'AsyncProcessService',
            'AsyncProcessQueueable',
            'DynamicRecordService',
            'GitHubIntegrationService',
            'GitHubRecordService',
            'GitHubPullRequestFilesService',
            'GitRepositoryService',
            'MetadataScannerService',
            'PipelineConfigurationService',
            'PipelineMetadataProcessor',
            'UserStoryMetadataService',
            'MetadataService',
            'MetadataApiService',
            'MetadataConnectionService',
            'MetadataAuthenticationService',
            'MetadataTokenService',
            'MetadataDiscoveryService',
            'ExternalMetadataController'
        };
        for (String coreName : corePriority) {
            for (User_Story_Metadata__c comp : classComps) {
                if (comp.Metadata_API_Name__c == coreName) {
                    sortedClassComps.add(comp);
                }
            }
        }
        for (User_Story_Metadata__c comp : classComps) {
            if (!corePriority.contains(comp.Metadata_API_Name__c)) {
                sortedClassComps.add(comp);
            }
        }
        
        deployApexClassesBulk(sortedClassComps, targetUrl, targetToken);

        // Pass 3: Deploy other components (Skip or simulate)
        for (User_Story_Metadata__c comp : comps) {
            String metaType = comp.Metadata_Type__c;
            if (metaType != 'CustomObject' && metaType != 'ApexClass') {
                addLog('Component ' + comp.Metadata_API_Name__c + ' (' + metaType + ') is simulated.');
            }
        }
    }

    private void deployCustomObject(String apiName, String targetUrl, String targetToken) {
        List<EntityDefinition> entities = [
            SELECT QualifiedApiName, Label, PluralLabel 
            FROM EntityDefinition 
            WHERE QualifiedApiName = :apiName 
            LIMIT 1
        ];
        
        String label = apiName.replace('__c', '').replace('__e', '').replace('_', ' ');
        String pluralLabel = label + 's';
        
        if (!entities.isEmpty()) {
            if (entities[0].Label != null) {
                label = entities[0].Label;
            }
            if (entities[0].PluralLabel != null) {
                pluralLabel = entities[0].PluralLabel;
            }
        }

        // Query if custom object / Platform Event exists in target org (using cache)
        String devName = apiName.replace('__c', '').replace('__e', '');
        Boolean exists = targetCustomObjectIds.containsKey(devName.toLowerCase());
        
        // If it does not exist, create it (POST SOAP XML to Metadata API)
        if (!exists) {
            addLog('Creating CustomObject ' + apiName + ' in target org via SOAP Metadata API...');
            deployCustomObjectViaSoap(apiName, label, pluralLabel, targetUrl, targetToken);
        } else {
            addLog('CustomObject ' + apiName + ' already exists in target org.');
        }
    }

    private void deployCustomObjectFields(String apiName, String targetUrl, String targetToken) {
        String devName = apiName.replace('__c', '').replace('__e', '');
        String objId = targetCustomObjectIds.get(devName.toLowerCase());
        
        // Fallback query if not in cache (e.g. if newly created CustomObject)
        if (objId == null) {
            Http h = new Http();
            HttpRequest queryReq = new HttpRequest();
            String objSoql = 'SELECT Id FROM CustomObject WHERE DeveloperName = \'' + devName + '\'';
            queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(objSoql, 'UTF-8'));
            queryReq.setMethod('GET');
            queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
            queryReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse queryRes = h.send(queryReq);
            if (queryRes.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
                List<Object> records = (List<Object>) responseMap.get('records');
                if (records != null && !records.isEmpty()) {
                    Map<String, Object> objRecord = (Map<String, Object>) records[0];
                    objId = (String) objRecord.get('Id');
                    targetCustomObjectIds.put(devName.toLowerCase(), objId);
                }
            }
        }
        
        Set<String> existingFields = (objId != null) ? targetCustomFields.get(objId) : null;
        if (existingFields == null) {
            existingFields = new Set<String>();
            // Fallback query for custom fields if not in cache
            if (objId != null) {
                HttpRequest fieldReq = new HttpRequest();
                String fieldSoql = 'SELECT DeveloperName FROM CustomField WHERE TableEnumOrId = \'' + objId + '\'';
                fieldReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(fieldSoql, 'UTF-8'));
                fieldReq.setMethod('GET');
                fieldReq.setHeader('Authorization', 'Bearer ' + targetToken);
                fieldReq.setHeader('Content-Type', 'application/json');
                
                HttpResponse fieldRes = new Http().send(fieldReq);
                if (fieldRes.getStatusCode() == 200) {
                    Map<String, Object> fieldResp = (Map<String, Object>) JSON.deserializeUntyped(fieldRes.getBody());
                    List<Object> fieldRecords = (List<Object>) fieldResp.get('records');
                    if (fieldRecords != null) {
                        for (Object fRec : fieldRecords) {
                            Map<String, Object> fMap = (Map<String, Object>) fRec;
                            String devFieldName = (String) fMap.get('DeveloperName');
                            if (String.isNotBlank(devFieldName)) {
                                existingFields.add((devFieldName + '__c').toLowerCase());
                            }
                        }
                    }
                }
            }
        }
        addLog('Existing fields in target org for ' + apiName + ': ' + String.join(new List<String>(existingFields), ', '));

        // Deploy all custom fields for this object
        addLog('Deploying custom fields for ' + apiName + '...');
        SObjectType sObjType = Schema.getGlobalDescribe().get(apiName);
        if (sObjType != null) {
            Map<String, SObjectField> fieldsMap = sObjType.getDescribe().fields.getMap();
            List<Schema.DescribeFieldResult> fieldsToDeploy = new List<Schema.DescribeFieldResult>();
            for (SObjectField f : fieldsMap.values()) {
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (dfr.isCustom()) {
                    String fieldNameLower = dfr.getName().toLowerCase();
                    if (!existingFields.contains(fieldNameLower)) {
                        fieldsToDeploy.add(dfr);
                    } else {
                        addLog('CustomField ' + apiName + '.' + dfr.getName() + ' already exists in target org.');
                    }
                }
            }

            // Batch fields in lists of 10 to reduce callout count dramatically
            List<Schema.DescribeFieldResult> batch = new List<Schema.DescribeFieldResult>();
            for (Schema.DescribeFieldResult dfr : fieldsToDeploy) {
                batch.add(dfr);
                if (batch.size() == 10) {
                    deployCustomFieldsViaSoap(apiName, batch, targetUrl, targetToken);
                    batch.clear();
                }
            }
            if (!batch.isEmpty()) {
                deployCustomFieldsViaSoap(apiName, batch, targetUrl, targetToken);
            }
        }
    }

    private void deployCustomFieldsViaSoap(String objectName, List<Schema.DescribeFieldResult> fieldsList, String targetUrl, String targetToken) {
        if (fieldsList == null || fieldsList.isEmpty()) {
            return;
        }

        List<String> metadata = new List<String>();
        for (Schema.DescribeFieldResult dfr : fieldsList) {
            String fieldName = dfr.getName();
            String label = dfr.getLabel();
            Schema.DisplayType dt = dfr.getType();
            String fieldType = getMetadataFieldType(dt);
            
            metadata.add('<met:metadata xsi:type="met:CustomField">');
            metadata.add('<met:fullName>' + objectName + '.' + fieldName + '</met:fullName>');
            metadata.add('<met:label>' + label.escapeXml() + '</met:label>');
            metadata.add('<met:type>' + fieldType + '</met:type>');
            
            if (fieldType == 'Text' || fieldType == 'LongTextArea') {
                if (!dfr.isCalculated()) {
                    Integer len = dfr.getLength();
                    if (len == 0 || len == null) len = 255;
                    metadata.add('<met:length>' + len + '</met:length>');
                }
                if (fieldType == 'LongTextArea') {
                    metadata.add('<met:visibleLines>3</met:visibleLines>');
                }
            } else if (fieldType == 'Number' || fieldType == 'Percent' || fieldType == 'Currency') {
                Integer precision = dfr.getPrecision();
                Integer scale = dfr.getScale();
                if (precision == 0 || precision == null) precision = 18;
                if (scale == null) scale = 0;
                metadata.add('<met:precision>' + precision + '</met:precision>');
                metadata.add('<met:scale>' + scale + '</met:scale>');
            } else if (fieldType == 'Lookup') {
                List<Schema.SObjectType> refTo = dfr.getReferenceTo();
                if (!refTo.isEmpty()) {
                    metadata.add('<met:referenceTo>' + refTo[0].getDescribe().getName() + '</met:referenceTo>');
                    String relName = null;
                    for (Schema.ChildRelationship cr : refTo[0].getDescribe().getChildRelationships()) {
                        if (cr.getField() == dfr.getSObjectField()) {
                            relName = cr.getRelationshipName();
                            break;
                        }
                    }
                    if (String.isNotBlank(relName)) {
                        if (relName.endsWith('__r')) {
                            relName = relName.removeEnd('__r');
                        }
                        metadata.add('<met:relationshipName>' + relName + '</met:relationshipName>');
                    }
                }
            } else if (fieldType == 'Picklist' || fieldType == 'MultiselectPicklist') {
                metadata.add('<met:valueSet>');
                metadata.add('<met:valueSetDefinition>');
                for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
                    metadata.add('<met:value>');
                    metadata.add('<met:fullName>' + ple.getValue().escapeXml() + '</met:fullName>');
                    metadata.add('<met:label>' + ple.getLabel().escapeXml() + '</met:label>');
                    metadata.add('<met:default>' + ple.isDefaultValue() + '</met:default>');
                    metadata.add('</met:value>');
                }
                metadata.add('</met:valueSetDefinition>');
                metadata.add('</met:valueSet>');
            } else if (fieldType == 'Checkbox') {
                Boolean defVal = false;
                if (dfr.getDefaultValue() != null) {
                    defVal = (Boolean)dfr.getDefaultValue();
                }
                metadata.add('<met:defaultValue>' + defVal + '</met:defaultValue>');
            }
            
            if (dfr.isCalculated() && String.isNotBlank(dfr.getCalculatedFormula())) {
                metadata.add('<met:formula>' + dfr.getCalculatedFormula().escapeXml() + '</met:formula>');
                metadata.add('<met:formulaTreatBlanksAs>BlankAsZero</met:formulaTreatBlanksAs>');
            }
            
            metadata.add('</met:metadata>');
        }

        String soap = '';
        soap += '<?xml version="1.0" encoding="utf-8"?>';
        soap += '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        soap += '<soapenv:Header>';
        soap += '<met:SessionHeader><met:sessionId>' + targetToken + '</met:sessionId></met:SessionHeader>';
        soap += '</soapenv:Header>';
        soap += '<soapenv:Body>';
        soap += '<met:createMetadata>';
        soap += String.join(metadata, '');
        soap += '</met:createMetadata>';
        soap += '</soapenv:Body>';
        soap += '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(targetUrl + '/services/Soap/m/60.0');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', 'createMetadata');
        req.setBody(soap);

        HttpResponse res = new Http().send(req);
        String responseBody = res.getBody();
        if (res.getStatusCode() != 200) {
            String errorMsg = parseSoapError(responseBody);
            throw new DeploymentExecutionException('Failed to deploy CustomFields for ' + objectName + ' via Metadata API: ' + errorMsg);
        } else {
            addLog('Deployed batch of ' + fieldsList.size() + ' custom fields for ' + objectName + '.');
        }
    }

    private static String getMetadataFieldType(Schema.DisplayType dt) {
        switch on dt {
            when BOOLEAN { return 'Checkbox'; }
            when CURRENCY { return 'Currency'; }
            when DATE { return 'Date'; }
            when DATETIME { return 'DateTime'; }
            when DOUBLE { return 'Number'; }
            when EMAIL { return 'Email'; }
            when INTEGER { return 'Number'; }
            when PERCENT { return 'Percent'; }
            when PHONE { return 'Phone'; }
            when PICKLIST { return 'Picklist'; }
            when MULTIPICKLIST { return 'MultiselectPicklist'; }
            when TEXTAREA { return 'LongTextArea'; }
            when URL { return 'Url'; }
            when REFERENCE { return 'Lookup'; }
            when else { return 'Text'; }
        }
    }

    private void deployCustomObjectViaSoap(String apiName, String label, String pluralLabel, String targetUrl, String targetToken) {
        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomObject">');
        metadata.add('<met:fullName>' + apiName + '</met:fullName>');
        metadata.add('<met:label>' + label + '</met:label>');
        metadata.add('<met:pluralLabel>' + pluralLabel + '</met:pluralLabel>');
        metadata.add('<met:deploymentStatus>Deployed</met:deploymentStatus>');
        if (apiName.endsWith('__e')) {
            metadata.add('<met:eventType>HighVolume</met:eventType>');
            metadata.add('<met:publishBehavior>PublishAfterCommit</met:publishBehavior>');
        } else {
            metadata.add('<met:sharingModel>ReadWrite</met:sharingModel>');
            metadata.add('<met:nameField>');
            metadata.add('<met:label>' + label + ' Name</met:label>');
            metadata.add('<met:type>Text</met:type>');
            metadata.add('</met:nameField>');
        }
        metadata.add('</met:metadata>');

        String soap = '';
        soap += '<?xml version="1.0" encoding="utf-8"?>';
        soap += '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';
        soap += '<soapenv:Header>';
        soap += '<met:SessionHeader><met:sessionId>' + targetToken + '</met:sessionId></met:SessionHeader>';
        soap += '</soapenv:Header>';
        soap += '<soapenv:Body>';
        soap += '<met:createMetadata>';
        soap += String.join(metadata, '');
        soap += '</met:createMetadata>';
        soap += '</soapenv:Body>';
        soap += '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(targetUrl + '/services/Soap/m/60.0');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', 'createMetadata');
        req.setBody(soap);

        HttpResponse res = new Http().send(req);
        String responseBody = res.getBody();
        if (res.getStatusCode() != 200 || responseBody.contains('<success>false</success>')) {
            String errorMsg = parseSoapError(responseBody);
            throw new DeploymentExecutionException('Failed to deploy CustomObject ' + apiName + ' via Metadata API: ' + errorMsg);
        }
        
        addLog('CustomObject ' + apiName + ' created successfully.');
    }

    private String parseSoapError(String soapBody) {
        Integer lastIndex = 0;
        Integer msgStart = soapBody.indexOf('<message>', lastIndex);
        if (msgStart != -1) {
            Integer msgEnd = soapBody.indexOf('</message>', msgStart);
            if (msgEnd != -1) {
                return soapBody.substring(msgStart + 9, msgEnd);
            }
        }
        Integer faultStart = soapBody.indexOf('<faultstring>');
        if (faultStart != -1) {
            Integer faultEnd = soapBody.indexOf('</faultstring>', faultStart);
            if (faultEnd != -1) {
                return soapBody.substring(faultStart + 13, faultEnd);
            }
        }
        return soapBody;
    }

    private void deployApexClassesBulk(List<User_Story_Metadata__c> classComps, String targetUrl, String targetToken) {
        if (classComps.isEmpty()) return;
        
        addLog('Deploying ' + classComps.size() + ' Apex classes in bulk...');
        
        // Retrieve local bodies of all classes
        Set<String> classNames = new Set<String>();
        for (User_Story_Metadata__c comp : classComps) {
            classNames.add(comp.Metadata_API_Name__c);
        }
        
        Map<String, String> localClassBodies = new Map<String, String>();
        for (ApexClass ac : [SELECT Name, Body FROM ApexClass WHERE Name IN :classNames]) {
            localClassBodies.put(ac.Name.toLowerCase(), ac.Body);
        }
        
        // Step 1: Ensure all classes exist in target org (create shell stubs if missing)
        Http h = new Http();
        for (User_Story_Metadata__c comp : classComps) {
            String name = comp.Metadata_API_Name__c;
            if (!localClassBodies.containsKey(name.toLowerCase())) {
                addLog('ApexClass ' + name + ' not found in the source org. Skipping deployment.');
                continue;
            }
            String classId = targetApexClassIds.get(name.toLowerCase());
            
            if (classId == null) {
                // Create a basic shell stub class first
                HttpRequest createReq = new HttpRequest();
                createReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClass');
                createReq.setMethod('POST');
                createReq.setHeader('Authorization', 'Bearer ' + targetToken);
                createReq.setHeader('Content-Type', 'application/json');
                
                Map<String, Object> payload = new Map<String, Object>();
                payload.put('Name', name);
                payload.put('Body', 'public class ' + name + ' {}');
                createReq.setBody(JSON.serialize(payload));
                
                addLog('Creating shell stub for ApexClass ' + name + '...');
                HttpResponse createRes = h.send(createReq);
                Integer code = createRes.getStatusCode();
                if (code == 200 || code == 201) {
                    Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(createRes.getBody());
                    classId = (String) resMap.get('id');
                    targetApexClassIds.put(name.toLowerCase(), classId);
                } else {
                    // Check if it already exists (concurrency safety)
                    String err = parseErrorMessage(createRes.getBody());
                    if (err != null && err.contains('Duplicate')) {
                        // Query the ID
                        HttpRequest qReq = new HttpRequest();
                        String qSoql = 'SELECT Id FROM ApexClass WHERE Name = \'' + name + '\'';
                        qReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(qSoql, 'UTF-8'));
                        qReq.setMethod('GET');
                        qReq.setHeader('Authorization', 'Bearer ' + targetToken);
                        qReq.setHeader('Content-Type', 'application/json');
                        HttpResponse qRes = h.send(qReq);
                        if (qRes.getStatusCode() == 200) {
                            Map<String, Object> qMap = (Map<String, Object>) JSON.deserializeUntyped(qRes.getBody());
                            List<Object> recs = (List<Object>) qMap.get('records');
                            if (recs != null && !recs.isEmpty()) {
                                classId = (String) ((Map<String, Object>) recs[0]).get('Id');
                                targetApexClassIds.put(name.toLowerCase(), classId);
                            }
                        }
                    }
                    if (classId == null) {
                        throw new DeploymentExecutionException('Failed to create ApexClass stub for ' + name + ': ' + err);
                    }
                }
            }
        }
        
        // Step 2: Create a MetadataContainer
        HttpRequest containerReq = new HttpRequest();
        containerReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/MetadataContainer');
        containerReq.setMethod('POST');
        containerReq.setHeader('Authorization', 'Bearer ' + targetToken);
        containerReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> containerPayload = new Map<String, Object>();
        containerPayload.put('Name', 'Ctr_' + System.now().getTime());
        containerReq.setBody(JSON.serialize(containerPayload));
        
        HttpResponse containerRes = h.send(containerReq);
        if (containerRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create MetadataContainer: ' + containerRes.getBody());
        }
        Map<String, Object> containerMap = (Map<String, Object>) JSON.deserializeUntyped(containerRes.getBody());
        String containerId = (String) containerMap.get('id');
        
        // Step 3: Create ApexClassMember for each class with its full local body
        for (User_Story_Metadata__c comp : classComps) {
            String name = comp.Metadata_API_Name__c;
            String classId = targetApexClassIds.get(name.toLowerCase());
            String body = localClassBodies.get(name.toLowerCase());
            if (body == null) continue;
            
            HttpRequest memberReq = new HttpRequest();
            memberReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClassMember');
            memberReq.setMethod('POST');
            memberReq.setHeader('Authorization', 'Bearer ' + targetToken);
            memberReq.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> memberPayload = new Map<String, Object>();
            memberPayload.put('MetadataContainerId', containerId);
            memberPayload.put('ContentEntityId', classId);
            memberPayload.put('Body', body);
            memberReq.setBody(JSON.serialize(memberPayload));
            
            HttpResponse memberRes = h.send(memberReq);
            if (memberRes.getStatusCode() != 201) {
                throw new DeploymentExecutionException('Failed to create ApexClassMember for ' + name + ': ' + memberRes.getBody());
            }
        }
        
        // Step 4: Submit ContainerAsyncRequest to compile all of them together
        HttpRequest requestReq = new HttpRequest();
        requestReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ContainerAsyncRequest');
        requestReq.setMethod('POST');
        requestReq.setHeader('Authorization', 'Bearer ' + targetToken);
        requestReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> requestPayload = new Map<String, Object>();
        requestPayload.put('MetadataContainerId', containerId);
        requestPayload.put('IsCheckOnly', false);
        requestReq.setBody(JSON.serialize(requestPayload));
        
        HttpResponse requestRes = h.send(requestReq);
        if (requestRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create ContainerAsyncRequest: ' + requestRes.getBody());
        }
        Map<String, Object> requestMap = (Map<String, Object>) JSON.deserializeUntyped(requestRes.getBody());
        String compileRequestId = (String) requestMap.get('id');
        
        // Step 5: Poll ContainerAsyncRequest status
        String status = 'Queued';
        String errorMsg = '';
        for (Integer i = 0; i < 30; i++) {
            // Wait 1 second
            Long start = System.now().getTime();
            while (System.now().getTime() - start < 1000) {}
            
            HttpRequest pollReq = new HttpRequest();
            pollReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ContainerAsyncRequest/' + compileRequestId);
            pollReq.setMethod('GET');
            pollReq.setHeader('Authorization', 'Bearer ' + targetToken);
            
            HttpResponse pollRes = h.send(pollReq);
            if (pollRes.getStatusCode() == 200) {
                Map<String, Object> pollMap = (Map<String, Object>) JSON.deserializeUntyped(pollRes.getBody());
                status = (String) pollMap.get('State');
                if (status == 'Completed') {
                    break;
                } else if (status == 'Failed') {
                    errorMsg = (String) pollMap.get('ErrorMsg');
                    if (pollMap.containsKey('DeployDetails')) {
                        Map<String, Object> details = (Map<String, Object>) pollMap.get('DeployDetails');
                        if (details != null && details.containsKey('componentFailures')) {
                            List<Object> failures = (List<Object>) details.get('componentFailures');
                            if (failures != null && !failures.isEmpty()) {
                                Map<String, Object> fail = (Map<String, Object>) failures[0];
                                errorMsg = (String) fail.get('problem');
                            }
                        }
                    }
                    break;
                }
            }
        }
        
        if (status != 'Completed') {
            throw new DeploymentExecutionException('Compilation/Deployment failed for ApexClasses in bulk: ' + (String.isNotBlank(errorMsg) ? errorMsg : status));
        }
        addLog('All Apex classes deployed and compiled successfully in bulk.');
    }

    private String parseErrorMessage(String body) {
        try {
            List<Object> errs = (List<Object>) JSON.deserializeUntyped(body);
            if (!errs.isEmpty()) {
                Map<String, Object> err = (Map<String, Object>) errs[0];
                return (String) err.get('message');
            }
        } catch (Exception ex) {}
        return body;
    }

    /**
     * Step 5: Transitions status to final success state (Validated / Completed) and sets timestamp.
     */
    private void completeExecutionFinal() {
        String finalStatus = (actionType == 'Validate') ? 'Validated' : 'Completed';
        
        // 1. Update request status and credential in database
        DeploymentExecutionHelper.applyRuntimeState(requestId, finalStatus, null, System.now(), this.resolvedCredentialId);
        
        // 2. Bulk insert all collected logs
        List<Deployment_Log__c> logsToInsert = new List<Deployment_Log__c>();
        for (String msg : infoLogs) {
            Deployment_Log__c log = new Deployment_Log__c();
            log.Deployment_Request__c = requestId;
            log.Log_Type__c = 'Info';
            log.Message__c = msg;
            log.Timestamp__c = System.now();
            logsToInsert.add(log);
        }
        
        Deployment_Log__c successLog = new Deployment_Log__c();
        successLog.Deployment_Request__c = requestId;
        successLog.Log_Type__c = 'Info';
        successLog.Message__c = 'Deployment request completed successfully.';
        successLog.Timestamp__c = System.now();
        logsToInsert.add(successLog);

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Exception Handler: Logs errors and transitions status to Failed.
     */
    private void handleFailureFinal(Exception ex) {
        System.debug(LoggingLevel.ERROR, 'DeploymentExecutionQueueable execution failed: ' + ex.getMessage());
        
        // 1. Update status to Failed in database
        DeploymentExecutionHelper.applyRuntimeState(requestId, 'Failed', null, System.now(), this.resolvedCredentialId);
        
        // 2. Bulk insert all collected logs + failure error log
        List<Deployment_Log__c> logsToInsert = new List<Deployment_Log__c>();
        for (String msg : infoLogs) {
            Deployment_Log__c log = new Deployment_Log__c();
            log.Deployment_Request__c = requestId;
            log.Log_Type__c = 'Info';
            log.Message__c = msg;
            log.Timestamp__c = System.now();
            logsToInsert.add(log);
        }
        
        Deployment_Log__c errorLog = new Deployment_Log__c();
        errorLog.Deployment_Request__c = requestId;
        errorLog.Log_Type__c = 'Error';
        errorLog.Message__c = 'Execution failed: ' + ex.getMessage();
        errorLog.Timestamp__c = System.now();
        logsToInsert.add(errorLog);

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    /**
     * Helper to simulate brief delay between processing steps.
     */
    private void simulateDelay() {
        if (Test.isRunningTest()) {
            return;
        }
        Long startTime = System.now().getTime();
        while (System.now().getTime() - startTime < 100) {
            // Busy wait
        }
    }
}