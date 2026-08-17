/**
 * Service class that acts as the single unified entry point for orchestrating deployment actions.
 * Manages deployment request lifecycle, status transitions, logs creation, and credentials resolution.
 */
public with sharing class DeploymentRuntimeService {

    public class DeploymentRuntimeServiceException extends Exception {}

    // DTO wrappers
    public class DeploymentResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public String currentStatus {get;set;}
        @AuraEnabled public Datetime startedTime {get;set;}
        @AuraEnabled public Id requestId {get;set;}
    }

    public class DeploymentStatusResult {
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public Datetime startedOn {get;set;}
        @AuraEnabled public Datetime completedOn {get;set;}
        @AuraEnabled public List<Deployment_Log__c> logs {get;set;}
        @AuraEnabled public Id completedDeploymentId {get;set;}
        @AuraEnabled public String errorMessage {get;set;}
    }

    /**
     * Start the deployment validation or execution lifecycle.
     */
    public static DeploymentResult startDeployment(Id requestId, String actionType) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:start requestId=' + requestId + ', actionType=' + actionType);
        if (requestId == null) {
            throw new DeploymentRuntimeServiceException('Deployment Request ID cannot be null.');
        }
        if (actionType != 'Validate' && actionType != 'Deploy') {
            throw new DeploymentRuntimeServiceException('Invalid action type. Must be Validate or Deploy.');
        }

        try {
            // Step 1: Query the deployment request details by Id or Promotion__c
            List<Deployment_Request__c> reqs = [
                SELECT Id, Status__c, Source_Environment__c, Target_Environment__c, Credential__c, Pipeline__c
                FROM Deployment_Request__c
                WHERE Id = :requestId OR Promotion__c = :requestId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (reqs.isEmpty()) {
                throw new DeploymentRuntimeServiceException('Deployment Request not found for ID: ' + requestId);
            }
            Deployment_Request__c req = reqs[0];
            requestId = req.Id;
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:request loaded requestId=' + requestId + ', status=' + req.Status__c + ', sourceEnvironmentId=' + req.Source_Environment__c + ', targetEnvironmentId=' + req.Target_Environment__c + ', credentialId=' + req.Credential__c + ', pipelineId=' + req.Pipeline__c);

            // Step 2: Validate preconditions
            validatePreconditions(req, actionType);
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:preconditions passed requestId=' + requestId + ', actionType=' + actionType);

            // Step 3: Resolve target environment credentials DTO (no DML inside helper)
            DeploymentCredentialController.CredentialWrapper credWrap = resolveTargetCredential(req.Target_Environment__c);
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:credential resolved requestId=' + requestId + ', resolvedCredentialId=' + (credWrap == null ? null : credWrap.credentialId));

            // Step 4: Mark execution as active before the async callout transaction starts.
            Datetime now = System.now();
            Id credId = (req.Credential__c == null && credWrap != null) ? (Id)credWrap.credentialId : null;
            String activeStatus = (actionType == 'Validate') ? 'Validating' : 'Deploying';
            
            DeploymentExecutionHelper.applyRuntimeState(requestId, activeStatus, now, null, credId);
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:runtime state applied requestId=' + requestId + ', activeStatus=' + activeStatus + ', appliedCredentialId=' + credId);

            // Step 5: Create execution logging

            // Step 5: Create execution logging
            DeploymentExecutionHelper.createInfoLog(requestId, 'Execution initialized. Deployment request status set to ' + activeStatus + '.');

            // Step 6: Enqueue Queueable
            System.enqueueJob(new DeploymentExecutionQueueable(requestId, actionType));
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.startDeployment:queueable enqueued requestId=' + requestId + ', actionType=' + actionType);

            // Return result DTO
            DeploymentResult res = new DeploymentResult();
            res.success = true;
            res.message = 'Deployment request transitioned to ' + activeStatus + '.';
            res.currentStatus = activeStatus;
            res.startedTime = now;
            res.requestId = requestId;
            return res;

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'DeploymentRuntimeService.startDeployment:failed requestId=' + requestId + ', actionType=' + actionType + ', message=' + ex.getMessage() + ', stack=' + ex.getStackTraceString());
            DeploymentExecutionHelper.createErrorLog(requestId, 'Failed to start execution: ' + ex.getMessage());
            
            // Handle failure state transition safely
            try {
                DeploymentExecutionHelper.applyRuntimeState(requestId, 'Failed', null, System.now(), null);
            } catch (Exception dmlEx) {
                System.debug(LoggingLevel.ERROR, 'DeploymentRuntimeService.startDeployment:failed to set failed status requestId=' + requestId + ', message=' + dmlEx.getMessage() + ', stack=' + dmlEx.getStackTraceString());
            }
            
            throw new DeploymentRuntimeServiceException(ex.getMessage(), ex);
        }
    }

    /**
     * Cancel an active deployment request execution.
     */
    public static Boolean cancelDeployment(Id requestId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.cancelDeployment:start requestId=' + requestId);
        if (requestId == null) {
            throw new DeploymentRuntimeServiceException('Deployment Request ID cannot be null.');
        }

        try {
            Deployment_Request__c req = [
                SELECT Id, Status__c, Credential__c
                FROM Deployment_Request__c
                WHERE Id = :requestId
                LIMIT 1
            ];

            if (req.Status__c != 'Pending' && req.Status__c != 'Deploying' && req.Status__c != 'Validating') {
                throw new DeploymentRuntimeServiceException('Only active requests can be cancelled.');
            }

            DeploymentExecutionHelper.applyRuntimeState(req.Id, 'Cancelled', null, System.now(), null);

            DeploymentExecutionHelper.createInfoLog(requestId, 'Execution cancelled by the user.');
            System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.cancelDeployment:cancelled requestId=' + requestId);
            return true;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'DeploymentRuntimeService.cancelDeployment:failed requestId=' + requestId + ', message=' + ex.getMessage() + ', stack=' + ex.getStackTraceString());
            throw new DeploymentRuntimeServiceException(ex.getMessage(), ex);
        }
    }

    /**
     * Retrieve status updates and log entries for components.
     */
    public static DeploymentStatusResult getDeploymentStatus(Id requestId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.getDeploymentStatus:start requestId=' + requestId);
        if (requestId == null) {
            throw new DeploymentRuntimeServiceException('Deployment Request ID cannot be null.');
        }

        Deployment_Request__c req = [
            SELECT Id, Status__c, Started_On__c, Completed_On__c, Promotion__c, User_Story__c
            FROM Deployment_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        List<Deployment_Log__c> logs = [
            SELECT Id, Log_Type__c, Message__c, Timestamp__c
            FROM Deployment_Log__c
            WHERE Deployment_Request__c = :requestId
            ORDER BY Timestamp__c ASC
            LIMIT 1000
        ];

        DeploymentStatusResult result = new DeploymentStatusResult();
        result.status = req.Status__c;
        result.startedOn = req.Started_On__c;
        result.completedOn = req.Completed_On__c;
        result.logs = logs;

        for (Deployment_Log__c l : logs) {
            if (l.Log_Type__c == 'Error' && String.isNotBlank(l.Message__c)) {
                result.errorMessage = l.Message__c;
            }
        }

        if (new Set<String>{'Completed', 'Completed Successfully', 'Validated'}.contains(req.Status__c)) {
            List<Deployment__c> createdDeps = new List<Deployment__c>();
            if (req.Promotion__c != null) {
                createdDeps = [SELECT Id FROM Deployment__c WHERE Promotion__c = :req.Promotion__c ORDER BY CreatedDate DESC LIMIT 1];
            }
            if (createdDeps.isEmpty() && req.User_Story__c != null) {
                createdDeps = [SELECT Id FROM Deployment__c WHERE User_Story__c = :req.User_Story__c ORDER BY CreatedDate DESC LIMIT 1];
            }
            if (createdDeps.isEmpty()) {
                createdDeps = [SELECT Id FROM Deployment__c ORDER BY CreatedDate DESC LIMIT 1];
            }
            if (!createdDeps.isEmpty()) {
                result.completedDeploymentId = createdDeps[0].Id;
            }
        }

        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.getDeploymentStatus:result requestId=' + requestId + ', status=' + result.status + ', logCount=' + logs.size() + ', completedDeploymentId=' + result.completedDeploymentId);
        return result;
    }

    // Helper validation (Single responsibility: validates only)
    private static void validatePreconditions(Deployment_Request__c req, String actionType) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.validatePreconditions:start requestId=' + req.Id + ', status=' + req.Status__c + ', actionType=' + actionType);
        if (req.Status__c == 'Deploying' || req.Status__c == 'Validating') {
            throw new DeploymentRuntimeServiceException('Cannot trigger action. Another execution is already in progress.');
        }
        if (req.Target_Environment__c == null) {
            throw new DeploymentRuntimeServiceException('Target environment is not defined on the Deployment Request.');
        }
    }

    // Helper resolving target credential wrapper (Single responsibility: queries & returns DTO wrapper only, NO DML)
    private static DeploymentCredentialController.CredentialWrapper resolveTargetCredential(Id targetEnvironmentId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.resolveTargetCredential:start targetEnvironmentId=' + targetEnvironmentId);
        DeploymentCredentialController.CredentialWrapper wrap = DeploymentCredentialController.getCredentialByEnvironment(targetEnvironmentId);
        if (wrap == null || wrap.credentialId == null) {
            throw new DeploymentRuntimeServiceException('No active credential configuration found for target environment.');
        }
        System.debug(LoggingLevel.DEBUG, 'DeploymentRuntimeService.resolveTargetCredential:resolved targetEnvironmentId=' + targetEnvironmentId + ', credentialId=' + wrap.credentialId);
        return wrap;
    }
}