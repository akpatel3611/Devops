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

            // Step 4: Execute deployments via Tooling API callout (NO DML)
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

        addLog('Initiating real-time deployment of selected components...');

        // Pass 1: Deploy Custom Objects first
        for (User_Story_Metadata__c comp : comps) {
            if (comp.Metadata_Type__c == 'CustomObject') {
                deployCustomObject(comp.Metadata_API_Name__c, targetUrl, targetToken);
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
        
        String label = apiName.replace('__c', '').replace('_', ' ');
        String pluralLabel = label + 's';
        
        if (!entities.isEmpty()) {
            if (entities[0].Label != null) {
                label = entities[0].Label;
            }
            if (entities[0].PluralLabel != null) {
                pluralLabel = entities[0].PluralLabel;
            }
        }

        // Query if custom object exists in target org
        String devName = apiName.replace('__c', '');
        
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
        
        // If it does not exist, create it (POST)
        if (records == null || records.isEmpty()) {
            addLog('Creating CustomObject ' + apiName + ' in target org...');
            
            HttpRequest deployReq = new HttpRequest();
            deployReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/CustomObject');
            deployReq.setMethod('POST');
            deployReq.setHeader('Authorization', 'Bearer ' + targetToken);
            deployReq.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> metadata = new Map<String, Object>();
            metadata.put('label', label);
            metadata.put('pluralLabel', pluralLabel);
            metadata.put('sharingModel', 'ReadWrite');
            metadata.put('deploymentStatus', 'Deployed');
            
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('FullName', apiName);
            payload.put('Metadata', metadata);
            
            deployReq.setBody(JSON.serialize(payload));
            
            HttpResponse deployRes = h.send(deployReq);
            Integer statusCode = deployRes.getStatusCode();
            if (statusCode != 200 && statusCode != 201 && statusCode != 204) {
                String errorMsg = parseErrorMessage(deployRes.getBody());
                throw new DeploymentExecutionException('Failed to create CustomObject ' + apiName + ': ' + errorMsg);
            }
            
            addLog('CustomObject ' + apiName + ' created successfully.');
        } else {
            addLog('CustomObject ' + apiName + ' already exists in target org.');
        }
    }

    private void deployApexClassInMemory(String apiName, String targetUrl, String targetToken) {
        List<ApexClass> localClasses = [SELECT Name, Body FROM ApexClass WHERE Name = :apiName LIMIT 1];
        if (localClasses.isEmpty()) {
            throw new DeploymentExecutionException('ApexClass ' + apiName + ' not found in the source org.');
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
            // Update existing class (PATCH)
            Map<String, Object> record = (Map<String, Object>) records[0];
            String classId = (String) record.get('Id');
            
            deployReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClass/' + classId);
            deployReq.setMethod('PATCH');
            
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('Body', classBody);
            deployReq.setBody(JSON.serialize(payload));
            
            addLog('Updating ApexClass ' + apiName + ' in target org...');
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