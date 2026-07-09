/**
 * Pure persistence utility class responsible for DML updates and logging on Deployment Request records.
 * 
 * Crucial Constraints:
 * - MUST NOT contain business decisions or validation rules.
 * - MUST NOT perform credential resolution.
 * - MUST NOT handle execution sequencing, queueable orchestration, or flow logic.
 * - Responsibility is strictly limited to updating Deployment_Request__c and inserting Deployment_Log__c records.
 */
public with sharing class DeploymentExecutionHelper {

    // Log Type Constants
    public static final String LOG_INFO = 'Info';
    public static final String LOG_ERROR = 'Error';

    /**
     * Updates the status, timestamps, and credential mappings for a given Deployment Request.
     * Note: status parameter is optional; Status__c is updated only when status is not null.
     * DML update executes only if at least one field change is made.
     */
    public static void applyRuntimeState(
        Id requestId, 
        String status, 
        Datetime startedOn, 
        Datetime completedOn, 
        Id credentialId
    ) {
        if (requestId == null) {
            return;
        }

        try {
            Deployment_Request__c req = new Deployment_Request__c(Id = requestId);
            Boolean hasChanges = false;
            
            if (status != null) {
                req.Status__c = status;
                hasChanges = true;
            }
            if (startedOn != null) {
                req.Started_On__c = startedOn;
                hasChanges = true;
            }
            if (completedOn != null) {
                req.Completed_On__c = completedOn;
                hasChanges = true;
            }
            if (credentialId != null) {
                req.Credential__c = credentialId;
                hasChanges = true;
            }
            
            if (hasChanges) {
                update req;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'DeploymentExecutionHelper.applyRuntimeState failed: ' + ex.getMessage());
            throw ex;
        }
    }

    /**
     * Inserts a deployment log record linked to the target request.
     * Ignores blank or null messages to prevent empty log records.
     */
    public static void writeLog(Id requestId, String logType, String message) {
        if (requestId == null || String.isBlank(message)) {
            return;
        }

        try {
            Deployment_Log__c log = new Deployment_Log__c();
            log.Deployment_Request__c = requestId;
            log.Log_Type__c = (logType != null) ? logType : LOG_INFO;
            log.Message__c = message.left(255);
            log.Timestamp__c = System.now();
            insert log;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'DeploymentExecutionHelper.writeLog failed: ' + ex.getMessage());
        }
    }

    /**
     * Inserts an Info-level deployment log.
     */
    public static void createInfoLog(Id requestId, String message) {
        writeLog(requestId, LOG_INFO, message);
    }

    /**
     * Inserts an Error-level deployment log.
     */
    public static void createErrorLog(Id requestId, String message) {
        writeLog(requestId, LOG_ERROR, message);
    }
}