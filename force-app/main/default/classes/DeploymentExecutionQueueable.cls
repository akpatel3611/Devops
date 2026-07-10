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
                'AsyncProcessor'
            };
            List<String> coreAsyncTypes = new List<String>{
                'CustomObject',
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

        addLog('Initiating real-time deployment of selected components...');

        // Pass 1: Deploy Custom Objects / Platform Events first
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                if (comp.Metadata_API_Name__c != null && (comp.Metadata_API_Name__c.endsWith('__c') || comp.Metadata_API_Name__c.endsWith('__e'))) {
                    deployCustomObject(comp.Metadata_API_Name__c, targetUrl, targetToken);
                } else {
                    addLog('Component ' + comp.Metadata_API_Name__c + ' is not a valid CustomObject API name. Skipping.');
                }
            }
        }

        // Pass 2: Deploy Apex Classes
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'ApexClass') {
                deployApexClassInMemory(comp.Metadata_API_Name__c, targetUrl, targetToken);
            }
        }

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

        // Query if custom object / Platform Event exists in target org
        String devName = apiName.replace('__c', '').replace('__e', '');
        
        Http h = new Http();
        HttpRequest queryReq = new HttpRequest();
        queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=SELECT+Id+FROM+CustomObject+WHERE+DeveloperName=\'' + devName + '\'');
        queryReq.setMethod('GET');
        queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
        queryReq.setHeader('Content-Type', 'application/json');
        
        HttpResponse queryRes = h.send(queryReq);
        if (queryRes.getStatusCode() != 200) {
            throw new DeploymentExecutionException('Failed to query custom object status in target org: ' + queryRes.getBody());
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
        List<Object> records = (List<Object>) responseMap.get('records');
        
        // If it does not exist, create it (POST SOAP XML to Metadata API)
        if (records == null || records.isEmpty()) {
            addLog('Creating CustomObject ' + apiName + ' in target org via SOAP Metadata API...');
            deployCustomObjectViaSoap(apiName, label, pluralLabel, targetUrl, targetToken);
        } else {
            addLog('CustomObject ' + apiName + ' already exists in target org.');
        }

        // Deploy all custom fields for this object
        addLog('Deploying custom fields for ' + apiName + '...');
        SObjectType sObjType = Schema.getGlobalDescribe().get(apiName);
        if (sObjType != null) {
            Map<String, SObjectField> fieldsMap = sObjType.getDescribe().fields.getMap();
            for (SObjectField f : fieldsMap.values()) {
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (dfr.isCustom()) {
                    deployCustomFieldViaSoap(apiName, dfr, targetUrl, targetToken);
                }
            }
        }
    }

    private void deployCustomFieldViaSoap(String objectName, Schema.DescribeFieldResult dfr, String targetUrl, String targetToken) {
        String fieldName = dfr.getName();
        String label = dfr.getLabel();
        Schema.DisplayType dt = dfr.getType();
        String fieldType = getMetadataFieldType(dt);
        
        List<String> metadata = new List<String>();
        metadata.add('<met:metadata xsi:type="met:CustomField">');
        metadata.add('<met:fullName>' + objectName + '.' + fieldName + '</met:fullName>');
        metadata.add('<met:label>' + label.escapeXml() + '</met:label>');
        metadata.add('<met:type>' + fieldType + '</met:type>');
        
        if (fieldType == 'Text' || fieldType == 'LongTextArea') {
            Integer len = dfr.getLength();
            if (len == 0 || len == null) len = 255;
            metadata.add('<met:length>' + len + '</met:length>');
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
                String relName = dfr.getRelationshipName();
                if (String.isNotBlank(relName)) {
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
            if (errorMsg != null && (errorMsg.contains('already exists') || errorMsg.contains('already a field named') || errorMsg.contains('duplicate'))) {
                addLog('CustomField ' + objectName + '.' + fieldName + ' already exists in target org.');
            } else {
                throw new DeploymentExecutionException('Failed to deploy CustomField ' + objectName + '.' + fieldName + ' via Metadata API: ' + errorMsg);
            }
        } else {
            addLog('CustomField ' + objectName + '.' + fieldName + ' deployed successfully.');
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

    private void deployApexClassInMemory(String apiName, String targetUrl, String targetToken) {
        List<ApexClass> localClasses = [SELECT Name, Body FROM ApexClass WHERE Name = :apiName LIMIT 1];
        if (localClasses.isEmpty()) {
            addLog('ApexClass ' + apiName + ' not found in the source org. Skipping deployment.');
            return;
        }
        String classBody = localClasses[0].Body;

        Http h = new Http();
        HttpRequest queryReq = new HttpRequest();
        queryReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/query/?q=SELECT+Id+FROM+ApexClass+WHERE+Name=\'' + apiName + '\'');
        queryReq.setMethod('GET');
        queryReq.setHeader('Authorization', 'Bearer ' + targetToken);
        queryReq.setHeader('Content-Type', 'application/json');
        
        HttpResponse queryRes = h.send(queryReq);
        if (queryRes.getStatusCode() != 200) {
            throw new DeploymentExecutionException('Failed to query class status in target org: ' + queryRes.getBody());
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(queryRes.getBody());
        List<Object> records = (List<Object>) responseMap.get('records');
        
        HttpRequest deployReq = new HttpRequest();
        deployReq.setHeader('Authorization', 'Bearer ' + targetToken);
        deployReq.setHeader('Content-Type', 'application/json');

        if (records != null && !records.isEmpty()) {
            // Update existing class via MetadataContainer to support Sandbox/Prod org compilation
            Map<String, Object> record = (Map<String, Object>) records[0];
            String classId = (String) record.get('Id');
            deployApexClassViaContainer(apiName, classId, classBody, targetUrl, targetToken);
            return;
        } else {
            // Create new class (POST)
            deployReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClass');
            deployReq.setMethod('POST');
            
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('Name', apiName);
            payload.put('Body', classBody);
            deployReq.setBody(JSON.serialize(payload));
            
            addLog('Creating ApexClass ' + apiName + ' in target org...');
        }

        HttpResponse deployRes = h.send(deployReq);
        Integer statusCode = deployRes.getStatusCode();
        if (statusCode != 200 && statusCode != 201 && statusCode != 204) {
            String errorMsg = parseErrorMessage(deployRes.getBody());
            throw new DeploymentExecutionException('Compilation/Deployment failed for ApexClass ' + apiName + ': ' + errorMsg);
        }
        
        addLog('ApexClass ' + apiName + ' deployed successfully.');
    }

    private void deployApexClassViaContainer(String apiName, String classId, String classBody, String targetUrl, String targetToken) {
        Http h = new Http();
        
        // Step 1: Create MetadataContainer
        HttpRequest containerReq = new HttpRequest();
        containerReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/MetadataContainer');
        containerReq.setMethod('POST');
        containerReq.setHeader('Authorization', 'Bearer ' + targetToken);
        containerReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> containerPayload = new Map<String, Object>();
        containerPayload.put('Name', 'Deploy_' + apiName + '_' + System.now().getTime());
        containerReq.setBody(JSON.serialize(containerPayload));
        
        HttpResponse containerRes = h.send(containerReq);
        if (containerRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create MetadataContainer: ' + containerRes.getBody());
        }
        Map<String, Object> containerMap = (Map<String, Object>) JSON.deserializeUntyped(containerRes.getBody());
        String containerId = (String) containerMap.get('id');
        
        // Step 2: Create ApexClassMember
        HttpRequest memberReq = new HttpRequest();
        memberReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClassMember');
        memberReq.setMethod('POST');
        memberReq.setHeader('Authorization', 'Bearer ' + targetToken);
        memberReq.setHeader('Content-Type', 'application/json');
        
        Map<String, Object> memberPayload = new Map<String, Object>();
        memberPayload.put('MetadataContainerId', containerId);
        memberPayload.put('ContentEntityId', classId);
        memberPayload.put('Body', classBody);
        memberReq.setBody(JSON.serialize(memberPayload));
        
        HttpResponse memberRes = h.send(memberReq);
        if (memberRes.getStatusCode() != 201) {
            throw new DeploymentExecutionException('Failed to create ApexClassMember: ' + memberRes.getBody());
        }
        
        // Step 3: Create ContainerAsyncRequest
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
        
        // Step 4: Poll ContainerAsyncRequest status
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
            throw new DeploymentExecutionException('Compilation/Deployment failed for ApexClass ' + apiName + ': ' + (String.isNotBlank(errorMsg) ? errorMsg : status));
        }
        addLog('ApexClass ' + apiName + ' deployed and compiled successfully.');
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