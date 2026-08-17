/**
 * Invocable Action class that bridges Salesforce Flow record actions to DeploymentRuntimeService.
 * Contains zero business logic, DML, or credentials resolution.
 */
public with sharing class DeploymentRuntimeFlowAction {

    public class ActionRequest {
        @InvocableVariable(required=true label='Deployment Request ID' description='ID of the Deployment Request record')
        public Id recordId;

        @InvocableVariable(required=true label='Action Type' description='Action to perform: Validate, Deploy, or Cancel')
        public String actionType;
    }

    public class ActionResult {
        @InvocableVariable(label='Success Flag' description='True if action succeeded')
        public Boolean success;

        @InvocableVariable(label='Response Message' description='Status details or error messages')
        public String message;

        @InvocableVariable(label='Current Status' description='Current record status after execution')
        public String currentStatus;

        @InvocableVariable(label='Deployment Request ID' description='ID of the Deployment Request record')
        public Id requestId;
    }

    /**
     * Executes the requested action for the Deployment Request.
     */
    @InvocableMethod(label='Execute Deployment Action' category='Deployment' description='Triggers validation, deployment, or cancellation for a Deployment Request')
    public static List<ActionResult> execute(List<ActionRequest> requests) {
        System.debug(LoggingLevel.INFO, '[DeploymentRuntimeFlowAction.execute] START - Requests Count: ' + (requests != null ? requests.size() : 0));
        List<ActionResult> results = new List<ActionResult>();
        if (requests == null || requests.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[DeploymentRuntimeFlowAction.execute] Warning: requests list is empty or null.');
            return results;
        }

        for (ActionRequest req : requests) {
            System.debug(LoggingLevel.DEBUG, '[DeploymentRuntimeFlowAction.execute] Processing request - RecordID: ' + req.recordId + ' | ActionType: ' + req.actionType);
            ActionResult res = new ActionResult();
            res.requestId = req.recordId;
            try {
                if (req.actionType == 'Validate' || req.actionType == 'Deploy') {
                    DeploymentRuntimeService.DeploymentResult startRes = DeploymentRuntimeService.startDeployment(req.recordId, req.actionType);
                    res.success = startRes.success;
                    res.message = startRes.message;
                    res.currentStatus = startRes.currentStatus;
                    System.debug(LoggingLevel.FINE, '[DeploymentRuntimeFlowAction.execute] StartDeployment result - Success: ' + res.success + ' | Status: ' + res.currentStatus);
                } else if (req.actionType == 'Cancel') {
                    res.success = DeploymentRuntimeService.cancelDeployment(req.recordId);
                    res.message = 'Deployment request cancelled successfully.';
                    res.currentStatus = 'Cancelled';
                    System.debug(LoggingLevel.FINE, '[DeploymentRuntimeFlowAction.execute] CancelDeployment result - Success: ' + res.success);
                } else {
                    res.success = false;
                    res.message = 'Invalid action type: ' + req.actionType;
                    res.currentStatus = 'Failed';
                    System.debug(LoggingLevel.WARN, '[DeploymentRuntimeFlowAction.execute] Warning: Invalid action type: ' + req.actionType);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, '[DeploymentRuntimeFlowAction.execute] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
                res.success = false;
                res.message = ex.getMessage();
                res.currentStatus = 'Failed';
            }
            results.add(res);
        }
        System.debug(LoggingLevel.INFO, '[DeploymentRuntimeFlowAction.execute] SUCCESS - Executed ' + results.size() + ' Flow action requests.');
        return results;
    }
}