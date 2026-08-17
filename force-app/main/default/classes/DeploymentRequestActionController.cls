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
        System.debug(LoggingLevel.DEBUG, 'DeploymentRequestActionController.validateRequest:start requestId=' + requestId);
        return DeploymentRuntimeService.startDeployment(requestId, 'Validate');
    }

    /**
     * Aura-Enabled endpoint to trigger deployment.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentResult deployRequest(Id requestId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRequestActionController.deployRequest:start requestId=' + requestId);
        return DeploymentRuntimeService.startDeployment(requestId, 'Deploy');
    }

    /**
     * Aura-Enabled endpoint to cancel an active request.
     */
    @AuraEnabled
    public static Boolean cancelRequest(Id requestId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRequestActionController.cancelRequest:start requestId=' + requestId);
        return DeploymentRuntimeService.cancelDeployment(requestId);
    }

    /**
     * Aura-Enabled endpoint to get status and logs of a request.
     */
    @AuraEnabled
    public static DeploymentRuntimeService.DeploymentStatusResult getDeploymentStatus(Id requestId) {
        System.debug(LoggingLevel.DEBUG, 'DeploymentRequestActionController.getDeploymentStatus:start requestId=' + requestId);
        DeploymentRuntimeService.DeploymentStatusResult result = DeploymentRuntimeService.getDeploymentStatus(requestId);
        System.debug(LoggingLevel.DEBUG, 'DeploymentRequestActionController.getDeploymentStatus:result requestId=' + requestId + ', status=' + result.status + ', logCount=' + (result.logs == null ? 0 : result.logs.size()));
        return result;
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
     * Aura-Enabled endpoint to fetch GitHub PR details and mergeability status.
     */
    @AuraEnabled
    public static Map<String, Object> getPRDetails(Id deploymentRequestId) {
        System.debug(LoggingLevel.INFO, '[DeploymentRequestActionController.getPRDetails] START - deploymentRequestId: ' + deploymentRequestId);
        Map<String, Object> response = new Map<String, Object>();
        response.put('success', false);

        if (deploymentRequestId == null) {
            System.debug(LoggingLevel.WARN, '[DeploymentRequestActionController.getPRDetails] Warning: deploymentRequestId is null.');
            response.put('message', 'Deployment Request ID cannot be null.');
            return response;
        }

        try {
            // Resolve User_Story__c or Deployment_Request__c or Promotion__c
            Id dreqId = deploymentRequestId;
            if (String.valueOf(deploymentRequestId).startsWith('a0a')) { // Promotion__c
                List<Deployment_Request__c> dreqs = [
                    SELECT Id FROM Deployment_Request__c 
                    WHERE Promotion__c = :deploymentRequestId 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                ];
                if (!dreqs.isEmpty()) {
                    dreqId = dreqs[0].Id;
                    System.debug(LoggingLevel.DEBUG, '[DeploymentRequestActionController.getPRDetails] Promotion resolved to deploymentRequestId: ' + dreqId);
                }
            }

            List<Deployment_Request__c> dreqs = [
                SELECT Id, Status__c, Promotion__c, User_Story__c, User_Story__r.Name, User_Story__r.Feature_Branch__c, User_Story__r.Base_Branch__c, 
                       User_Story__r.PR_Status__c, User_Story__r.PR_Number__c, User_Story__r.PR_Url__c
                FROM Deployment_Request__c
                WHERE Id = :dreqId
                LIMIT 1
            ];

            if (dreqs.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[DeploymentRequestActionController.getPRDetails] Warning: Deployment Request record not found. resolvedId: ' + dreqId);
                response.put('message', 'Deployment Request record not found.');
                return response;
            }

            Deployment_Request__c req = dreqs[0];
            User_Story__c story = req.User_Story__r;

            if (story == null && req.Promotion__c != null) {
                List<User_Story__c> promoStories = [
                    SELECT PR_Number__c, PR_Url__c, PR_Status__c 
                    FROM User_Story__c 
                    WHERE Promotion__c = :req.Promotion__c
                    AND (PR_Number__c != null OR PR_Url__c != null)
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];
                if (!promoStories.isEmpty()) {
                    story = promoStories[0];
                    System.debug(LoggingLevel.DEBUG, '[DeploymentRequestActionController.getPRDetails] PR story resolved from promotion. promotionId: ' + req.Promotion__c);
                }
            }

            String repoOwner = 'akpatel3611';
            String repoName = 'Devops';

            List<Git_Repository__c> repos = [
                SELECT Repository_Owner__c, Repository_Name__c 
                FROM Git_Repository__c 
                WHERE Repository_Owner__c != null AND Repository_Name__c != null
                LIMIT 1
            ];
            if (!repos.isEmpty()) {
                if (String.isNotBlank(repos[0].Repository_Owner__c)) repoOwner = repos[0].Repository_Owner__c;
                if (String.isNotBlank(repos[0].Repository_Name__c)) repoName = repos[0].Repository_Name__c;
            }
            System.debug(LoggingLevel.DEBUG, '[DeploymentRequestActionController.getPRDetails] Repository resolved - owner: ' + repoOwner + ' | repo: ' + repoName);

            Integer prNumber = null;
            String prUrl = null;

            if (story != null && String.isNotBlank(story.PR_Number__c) && story.PR_Number__c.isNumeric()) {
                prNumber = Integer.valueOf(story.PR_Number__c);
            }
            if (story != null && String.isNotBlank(story.PR_Url__c)) {
                prUrl = story.PR_Url__c;
                if (prNumber == null) {
                    prNumber = extractPullRequestNumber(prUrl);
                }
            }

            // Call GitHub API to check live PR details & mergeability if PR exists
            Map<String, Object> ghData = new Map<String, Object>();
            if (prNumber != null) {
                System.debug(LoggingLevel.INFO, '[DeploymentRequestActionController.getPRDetails] START - fetching GitHub PR details. prNumber: ' + prNumber);
                ghData = GitHubCommitProvider.getPullRequestDetails(repoOwner, repoName, prNumber);
                if (ghData.containsKey('htmlUrl') && String.isNotBlank((String) ghData.get('htmlUrl'))) {
                    prUrl = (String) ghData.get('htmlUrl');
                }
            } else {
                System.debug(LoggingLevel.WARN, '[DeploymentRequestActionController.getPRDetails] Warning: PR number not available. deploymentRequestId: ' + dreqId + ' | prUrl: ' + prUrl);
            }

            Boolean isMerged = (ghData.containsKey('merged') && (Boolean) ghData.get('merged'))
                            || (story != null && story.PR_Status__c == 'Merged');
            Boolean hasConflict = (ghData.containsKey('hasConflict') && ghData.get('hasConflict') == true)
                || (ghData.containsKey('mergeable') && ghData.get('mergeable') == false);
            Boolean isApproved = (story != null && (story.PR_Status__c == 'Approved' || story.PR_Status__c == 'Merged'))
                || (ghData.containsKey('isApproved') && (Boolean) ghData.get('isApproved'));
            String stateStr = ghData.containsKey('state') ? (String) ghData.get('state') : null;

            response.put('success', true);
            response.put('prNumber', prNumber);
            response.put('prUrl', prUrl);
            response.put('isApproved', isApproved);
            response.put('isMerged', isMerged);
            response.put('hasConflict', hasConflict);
            response.put('mergeableState', ghData.containsKey('mergeable_state') ? (String) ghData.get('mergeable_state') : null);
            response.put('state', stateStr);
            System.debug(LoggingLevel.INFO, '[DeploymentRequestActionController.getPRDetails] SUCCESS - deploymentRequestId: ' + dreqId + ' | prNumber: ' + prNumber + ' | state: ' + stateStr + ' | isMerged: ' + isMerged + ' | hasConflict: ' + hasConflict);
            return response;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DeploymentRequestActionController.getPRDetails] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            response.put('success', false);
            response.put('message', 'Error checking PR details: ' + ex.getMessage());
            return response;
        }
    }

    private static Integer extractPullRequestNumber(String prUrl) {
        if (String.isBlank(prUrl)) {
            return null;
        }

        Pattern pullPattern = Pattern.compile('/pull/(\\d+)(?:$|[/?#])');
        Matcher pullMatcher = pullPattern.matcher(prUrl);
        if (pullMatcher.find()) {
            return Integer.valueOf(pullMatcher.group(1));
        }
        return null;
    }

    /**
     * Aura-Enabled endpoint to approve PR in GitHub and update Salesforce state.
     */
    @AuraEnabled
    public static Map<String, Object> approvePullRequest(Id deploymentRequestId) {
        Map<String, Object> response = new Map<String, Object>();
        response.put('success', false);

        try {
            Id dreqId = deploymentRequestId;
            if (String.valueOf(deploymentRequestId).startsWith('a0a')) {
                List<Deployment_Request__c> dreqs = [
                    SELECT Id FROM Deployment_Request__c 
                    WHERE Promotion__c = :deploymentRequestId 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                ];
                if (!dreqs.isEmpty()) {
                    dreqId = dreqs[0].Id;
                }
            }

            List<Deployment_Request__c> dreqs = [
                SELECT Id, User_Story__c, User_Story__r.PR_Number__c
                FROM Deployment_Request__c
                WHERE Id = :dreqId
                LIMIT 1
            ];

            String repoOwner = 'Purpleskyinfotech';
            String repoName = 'Salesforce-DevOps-Pipeline';
            Integer prNumber = 12;

            List<Git_Repository__c> repos = [
                SELECT Repository_Owner__c, Repository_Name__c 
                FROM Git_Repository__c 
                WHERE Repository_Owner__c != null AND Repository_Name__c != null
                LIMIT 1
            ];
            if (!repos.isEmpty()) {
                if (String.isNotBlank(repos[0].Repository_Owner__c)) repoOwner = repos[0].Repository_Owner__c;
                if (String.isNotBlank(repos[0].Repository_Name__c)) repoName = repos[0].Repository_Name__c;
            }

            if (!dreqs.isEmpty()) {
                Deployment_Request__c req = dreqs[0];
                if (req.User_Story__c != null) {
                    User_Story__c story = [SELECT Id, PR_Number__c FROM User_Story__c WHERE Id = :req.User_Story__c LIMIT 1];
                    if (String.isNotBlank(story.PR_Number__c) && story.PR_Number__c.isNumeric()) {
                        prNumber = Integer.valueOf(story.PR_Number__c);
                    }
                }
            }

            // Call GitHub API to record PR approval review (Callout BEFORE DML!)
            GitHubCommitProvider.approvePullRequest(repoOwner, repoName, prNumber);

            // Update User Story status (DML AFTER Callout!)
            if (!dreqs.isEmpty() && dreqs[0].User_Story__c != null) {
                User_Story__c storyUpdate = new User_Story__c(Id = dreqs[0].User_Story__c);
                storyUpdate.PR_Status__c = 'Approved';
                update storyUpdate;
            }

            response.put('success', true);
            response.put('message', 'Pull Request # ' + prNumber + ' approved successfully.');
            return response;
        } catch (Exception ex) {
            response.put('success', false);
            response.put('message', 'Failed to approve PR: ' + ex.getMessage());
            return response;
        }
    }

    /**
     * Aura-Enabled endpoint to approve and merge PR, triggering the deployment engine.
     */
    @AuraEnabled
    public static Map<String, Object> confirmAndMergePullRequest(Id deploymentRequestId) {
        Map<String, Object> response = new Map<String, Object>();
        response.put('success', false);

        if (deploymentRequestId == null) {
            response.put('message', 'Deployment Request ID cannot be null.');
            return response;
        }

        Id dreqId = deploymentRequestId;
        if (String.valueOf(deploymentRequestId).startsWith('a0a')) {
            List<Deployment_Request__c> dreqs = [
                SELECT Id FROM Deployment_Request__c 
                WHERE Promotion__c = :deploymentRequestId 
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];
            if (!dreqs.isEmpty()) {
                dreqId = dreqs[0].Id;
            }
        }

        try {
            List<Deployment_Request__c> dreqs = [
                SELECT Id, User_Story__c, User_Story__r.PR_Number__c
                FROM Deployment_Request__c
                WHERE Id = :dreqId
                LIMIT 1
            ];

            String repoOwner = 'Purpleskyinfotech';
            String repoName = 'Salesforce-DevOps-Pipeline';
            Integer prNumber = 12;

            List<Git_Repository__c> repos = [
                SELECT Repository_Owner__c, Repository_Name__c 
                FROM Git_Repository__c 
                WHERE Repository_Owner__c != null AND Repository_Name__c != null
                LIMIT 1
            ];
            if (!repos.isEmpty()) {
                if (String.isNotBlank(repos[0].Repository_Owner__c)) repoOwner = repos[0].Repository_Owner__c;
                if (String.isNotBlank(repos[0].Repository_Name__c)) repoName = repos[0].Repository_Name__c;
            }

            if (!dreqs.isEmpty()) {
                Deployment_Request__c req = dreqs[0];
                if (req.User_Story__c != null) {
                    User_Story__c story = [SELECT Id, PR_Number__c FROM User_Story__c WHERE Id = :req.User_Story__c LIMIT 1];
                    if (String.isNotBlank(story.PR_Number__c) && story.PR_Number__c.isNumeric()) {
                        prNumber = Integer.valueOf(story.PR_Number__c);
                    }
                }
            }

            // Step 1: Merge PR in GitHub via REST API (Callout BEFORE DML!)
            Map<String, Object> mergeRes = GitHubCommitProvider.mergePullRequest(repoOwner, repoName, prNumber);
            System.debug(LoggingLevel.DEBUG, 'confirmAndMergePullRequest: GitHub merge result=' + mergeRes);

            // Step 2: Update User Story status (DML AFTER Callout!)
            if (!dreqs.isEmpty() && dreqs[0].User_Story__c != null) {
                User_Story__c storyUpdate = new User_Story__c(Id = dreqs[0].User_Story__c);
                storyUpdate.PR_Status__c = 'Merged';
                update storyUpdate;
            }

            // Decoupled: Update Deployment Request status to Merged so user can trigger action manually
            Deployment_Request__c dreqUpdate = new Deployment_Request__c(Id = dreqId);
            dreqUpdate.Status__c = 'Merged';
            update dreqUpdate;

            response.put('success', true);
            response.put('message', 'Pull Request #' + prNumber + ' merged in GitHub successfully. Ready for manual validation/deployment.');
            return response;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'confirmAndMergePullRequest: failed deploymentRequestId=' + dreqId + ', message=' + ex.getMessage());
            response.put('success', false);
            response.put('message', ex.getMessage());
            return response;
        }
    }

    /**
     * Aura-Enabled endpoint to run Dry-Run Check-Only Validation against target org.
     */
    @AuraEnabled
    public static Map<String, Object> validateDeploymentRequest(Id deploymentRequestId) {
        Map<String, Object> response = new Map<String, Object>();
        response.put('success', false);
        try {
            Id dreqId = deploymentRequestId;
            if (String.valueOf(deploymentRequestId).startsWith('a0a')) {
                List<Deployment_Request__c> dreqs = [
                    SELECT Id FROM Deployment_Request__c 
                    WHERE Promotion__c = :deploymentRequestId 
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                ];
                if (!dreqs.isEmpty()) {
                    dreqId = dreqs[0].Id;
                }
            }

            DeploymentRuntimeService.startDeployment(dreqId, 'Validate');
            response.put('success', true);
            response.put('message', 'Dry-Run Check-Only Validation initiated against target org.');
            return response;
        } catch (Exception ex) {
            response.put('success', false);
            response.put('message', 'Failed to start validation: ' + ex.getMessage());
            return response;
        }
    }

    /**
     * Backward-compatible alias method for approveAndMergePullRequest.
     */
    @AuraEnabled
    public static void approveAndMergePullRequest(Id deploymentRequestId) {
        confirmAndMergePullRequest(deploymentRequestId);
    }
}
