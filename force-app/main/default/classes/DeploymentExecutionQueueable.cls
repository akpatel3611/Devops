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
        DeploymentExecutionHelper.createInfoLog(requestId, 'Simulating metadata payload deployment execution...');
        simulateDelay();

        // =================================================================
        // FUTURE SOAP DEPLOYMENT HOOK
        // =================================================================
    }

    /**
     * Step 5: Transitions status to final success state (Validated / Completed) and sets timestamp.
     */
    private void completeExecution() {
        String finalStatus = (actionType == 'Validate') ? 'Validated' : 'Completed';
        DeploymentExecutionHelper.applyRuntimeState(requestId, finalStatus, null, System.now(), null);
        DeploymentExecutionHelper.createInfoLog(requestId, 'Simulated deployment request completed successfully.');
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