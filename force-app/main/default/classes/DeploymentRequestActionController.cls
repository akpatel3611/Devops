/**
 * Controller class serving as the minimal integration gateway for Salesforce standard record actions.
 * Contains zero business logic and forwards invocations directly to DeploymentRuntimeService.
 */
public with sharing class DeploymentRequestActionController {

    public class ActionRequest {
        @InvocableVariable(required=true label='Deployment Request ID')
        public Id requestId;

        @InvocableVariable(required=true label='Action Type (Validate, Deploy, Cancel)')
        public String actionType;
    }

    public class ActionResult {
        @InvocableVariable(label='Success Flag')
        public Boolean success;

        @InvocableVariable(label='Response Message')
        public String message;
    }

    /**
     * Aura-Enabled endpoint to trigger validation.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentResult validateRequest(Id requestId) {
        return DeploymentRuntimeService.startDeployment(requestId, 'Validate');
    }

    /**
     * Aura-Enabled endpoint to trigger deployment.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentResult deployRequest(Id requestId) {
        return DeploymentRuntimeService.startDeployment(requestId, 'Deploy');
    }

    /**
     * Aura-Enabled endpoint to cancel an active request.
     */
    @AuraEnabled
    public static Boolean cancelRequest(Id requestId) {
        return DeploymentRuntimeService.cancelDeployment(requestId);
    }

    /**
     * Aura-Enabled endpoint to get status and logs of a request.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentStatusResult getDeploymentStatus(Id requestId) {
        return DeploymentRuntimeService.getDeploymentStatus(requestId);
    }

    /**
     * Invocable action allowing standard Salesforce declarative actions (Flows) to execute the service.
     */
    @InvocableMethod(label='Execute Deployment Action' description='Triggers validation, deployment, or cancellation for a Deployment Request')
    public static List<ActionResult> executeAction(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (ActionRequest req : requests) {
            ActionResult res = new ActionResult();
            try {
                if (req.actionType == 'Validate' || req.actionType == 'Deploy') {
                    DeploymentRuntimeService.DeploymentResult startRes = DeploymentRuntimeService.startDeployment(req.requestId, req.actionType);
                    res.success = startRes.success;
                    res.message = startRes.message;
                } else if (req.actionType == 'Cancel') {
                    res.success = DeploymentRuntimeService.cancelDeployment(req.requestId);
                    res.message = 'Deployment request cancelled successfully.';
                } else {
                    res.success = false;
                    res.message = 'Invalid action type specified.';
                }
            } catch (Exception ex) {
                res.success = false;
                res.message = ex.getMessage();
            }
            results.add(res);
        }
        return results;
    }
/**
 * Controller class serving as the minimal integration gateway for Salesforce standard record actions.
 * Contains zero business logic and forwards invocations directly to DeploymentRuntimeService.
 */
public with sharing class DeploymentRequestActionController {

    public class ActionRequest {
        @InvocableVariable(required=true label='Deployment Request ID')
        public Id requestId;

        @InvocableVariable(required=true label='Action Type (Validate, Deploy, Cancel)')
        public String actionType;
    }

    public class ActionResult {
        @InvocableVariable(label='Success Flag')
        public Boolean success;

        @InvocableVariable(label='Response Message')
        public String message;
    }

    /**
     * Aura-Enabled endpoint to trigger validation.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentResult validateRequest(Id requestId) {
        return DeploymentRuntimeService.startDeployment(requestId, 'Validate');
    }

    /**
     * Aura-Enabled endpoint to trigger deployment.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentResult deployRequest(Id requestId) {
        return DeploymentRuntimeService.startDeployment(requestId, 'Deploy');
    }

    /**
     * Aura-Enabled endpoint to cancel an active request.
     */
    @AuraEnabled
    public static Boolean cancelRequest(Id requestId) {
        return DeploymentRuntimeService.cancelDeployment(requestId);
    }

    /**
     * Aura-Enabled endpoint to get status and logs of a request.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentStatusResult getDeploymentStatus(Id requestId) {
        return DeploymentRuntimeService.getDeploymentStatus(requestId);
    }

    /**
     * Invocable action allowing standard Salesforce declarative actions (Flows) to execute the service.
     */
    @InvocableMethod(label='Execute Deployment Action' description='Triggers validation, deployment, or cancellation for a Deployment Request')
    public static List<ActionResult> executeAction(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (ActionRequest req : requests) {
            ActionResult res = new ActionResult();
            try {
                if (req.actionType == 'Validate' || req.actionType == 'Deploy') {
                    DeploymentRuntimeService.DeploymentResult startRes = DeploymentRuntimeService.startDeployment(req.requestId, req.actionType);
                    res.success = startRes.success;
                    res.message = startRes.message;
                } else if (req.actionType == 'Cancel') {
                    res.success = DeploymentRuntimeService.cancelDeployment(req.requestId);
                    res.message = 'Deployment request cancelled successfully.';
                } else {
                    res.success = false;
                    res.message = 'Invalid action type specified.';
                }
            } catch (Exception ex) {
                res.success = false;
                res.message = ex.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}