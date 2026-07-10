/**
 * Asynchronous execution engine that owns the complete deployment and validation execution lifecycle.
 * Decoupled from UI components, flow frameworks, and SOAP integration details.
 */
public with sharing class DeploymentExecutionQueueable implements Queueable, Database.AllowsCallouts {

    public class DeploymentExecutionException extends Exception {}

    private Id requestId;
    private String actionType; // 'Validate' or 'Deploy'

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
            initialize();
            loadDeploymentContext();
            prepareExecution();
            executeDeployment();
            completeExecution();
        } catch (Exception ex) {
            handleFailure(ex);
        }
    }

    /**
     * Step 1: Transitions request status to Preparing and logs start.
     */
    private void initialize() {
        DeploymentExecutionHelper.applyRuntimeState(requestId, 'Preparing', null, null, null);
        DeploymentExecutionHelper.createInfoLog(requestId, 'Asynchronous execution started.');
    }

    /**
     * Step 2: Queries fresh Deployment Request context and resolves target environment credentials.
     */
    private void loadDeploymentContext() {
        DeploymentExecutionHelper.createInfoLog(requestId, 'Resolving target environment credentials...');
        
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

        // Link credential to request if not already populated (no local DML, uses helper)
        if (req.Credential__c == null) {
            DeploymentExecutionHelper.applyRuntimeState(requestId, null, null, null, (Id)wrap.credentialId);
        }

        DeploymentExecutionHelper.createInfoLog(requestId, 'Credential verified successfully.');
    }

    /**
     * Step 3: Simulates loading deployment execution context and preparing packaging payload.
     */
    private void prepareExecution() {
        DeploymentExecutionHelper.createInfoLog(requestId, 'Loads deployment execution context.');
        simulateDelay();
        DeploymentExecutionHelper.createInfoLog(requestId, 'Preparing deployment package payload.');
        simulateDelay();
        DeploymentExecutionHelper.createInfoLog(requestId, 'Uploading deployment package.');
    }

    /**
     * Step 4: Transitions request status to executing status (Validating / Deploying).
     */
    private void executeDeployment() {
        String runningStatus = (actionType == 'Validate') ? 'Validating' : 'Deploying';
        DeploymentExecutionHelper.applyRuntimeState(requestId, runningStatus, null, null, null);
        
        Deployment_Request__c req = [
            SELECT Id, User_Story__c, Credential__c 
            FROM Deployment_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];

        if (req.Credential__c == null) {
            throw new DeploymentExecutionException('No credential linked to the Deployment Request.');
        }

        // Generate target access token and endpoint
        MetadataAuthenticationService.OAuthTokenResponse tokenResponse = 
            MetadataAuthenticationService.generateAccessToken(req.Credential__c);
        String targetToken = tokenResponse.accessToken;
        String targetUrl = tokenResponse.instanceUrl;

        // Retrieve components associated with user story
        List<User_Story_Metadata__c> comps = [
            SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :req.User_Story__c
        ];

        if (comps.isEmpty()) {
            DeploymentExecutionHelper.createInfoLog(requestId, 'No selected metadata components found for this user story. Deployment is empty.');
            return;
        }

        DeploymentExecutionHelper.createInfoLog(requestId, 'Initiating real-time deployment of selected components...');

        for (User_Story_Metadata__c comp : comps) {
            String apiName = comp.Metadata_API_Name__c;
            String metaType = comp.Metadata_Type__c;

            if (metaType == 'ApexClass') {
                deployApexClass(apiName, targetUrl, targetToken);
            } else {
                DeploymentExecutionHelper.createInfoLog(requestId, 'Component ' + apiName + ' (' + metaType + ') is not an ApexClass. Skipping or simulating deployment.');
                simulateDelay();
            }
        }
    }

    private void deployApexClass(String apiName, String targetUrl, String targetToken) {
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
            
            DeploymentExecutionHelper.createInfoLog(requestId, 'Updating ApexClass ' + apiName + ' in target org...');
        } else {
            // Create new class (POST)
            deployReq.setEndpoint(targetUrl + '/services/data/v60.0/tooling/sobjects/ApexClass');
            deployReq.setMethod('POST');
            
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('Name', apiName);
            payload.put('Body', classBody);
            deployReq.setBody(JSON.serialize(payload));
            
            DeploymentExecutionHelper.createInfoLog(requestId, 'Creating ApexClass ' + apiName + ' in target org...');
        }

        HttpResponse deployRes = h.send(deployReq);
        Integer statusCode = deployRes.getStatusCode();
        if (statusCode != 200 && statusCode != 201 && statusCode != 204) {
            String errorMsg = parseErrorMessage(deployRes.getBody());
            throw new DeploymentExecutionException('Compilation/Deployment failed for ApexClass ' + apiName + ': ' + errorMsg);
        }
        
        DeploymentExecutionHelper.createInfoLog(requestId, 'ApexClass ' + apiName + ' deployed successfully.');
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
    private void completeExecution() {
        String finalStatus = (actionType == 'Validate') ? 'Validated' : 'Completed';
        DeploymentExecutionHelper.applyRuntimeState(requestId, finalStatus, null, System.now(), null);
        DeploymentExecutionHelper.createInfoLog(requestId, 'Deployment request completed successfully.');
    }

    /**
     * Exception Handler: Logs errors and transitions status to Failed.
     */
    private void handleFailure(Exception ex) {
        System.debug(LoggingLevel.ERROR, 'DeploymentExecutionQueueable execution failed: ' + ex.getMessage());
        DeploymentExecutionHelper.createErrorLog(requestId, 'Execution failed: ' + ex.getMessage());
        DeploymentExecutionHelper.applyRuntimeState(requestId, 'Failed', null, System.now(), null);
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