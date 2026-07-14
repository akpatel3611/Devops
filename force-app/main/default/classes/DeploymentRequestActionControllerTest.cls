@isTest
private class DeploymentRequestActionControllerTest {

    @isTest
    static void testAuraEnabledActions() {
        Deployment_Environment__c env = new Deployment_Environment__c(Name = 'Target Env');
        insert env;

        Credentials__c cred = new Credentials__c(
            Name = 'Target Cred',
            Deployment_Environment__c = env.Id,
            Instance_URL__c = 'https://login.salesforce.com',
            SFDX_Auth_URL__c = 'force://test-auth-url'
        );
        insert cred;

        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Draft',
            Target_Environment__c = env.Id
        );
        insert req;

        // 1. Test validate request
        Test.startTest();
        DeploymentRuntimeService.DeploymentResult valRes = DeploymentRequestActionController.validateRequest(req.Id);
        System.assert(valRes.success, 'Expected validation trigger to succeed');
        
        // 2. Test cancel request
        Boolean cancelRes = DeploymentRequestActionController.cancelRequest(req.Id);
        System.assert(cancelRes, 'Expected cancellation to succeed');
        Test.stopTest();
    }

    @isTest
    static void testInvocableValidateAction() {
        Deployment_Environment__c env = new Deployment_Environment__c(Name = 'Target Env');
        insert env;

        Credentials__c cred = new Credentials__c(
            Name = 'Target Cred',
            Deployment_Environment__c = env.Id,
            Instance_URL__c = 'https://login.salesforce.com',
            SFDX_Auth_URL__c = 'force://test-auth-url'
        );
        insert cred;

        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Draft',
            Target_Environment__c = env.Id
        );
        insert req;

        DeploymentRequestActionController.ActionRequest actReq = new DeploymentRequestActionController.ActionRequest();
        actReq.requestId = req.Id;
        actReq.actionType = 'Validate';

        Test.startTest();
        List<DeploymentRequestActionController.ActionResult> results = DeploymentRequestActionController.executeAction(
            new List<DeploymentRequestActionController.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one action response');
        System.assert(results[0].success, 'Expected invocable validation to succeed');
    }

    @isTest
    static void testInvocableCancelAction() {
        Deployment_Environment__c env = new Deployment_Environment__c(Name = 'Target Env');
        insert env;

        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Pending',
            Target_Environment__c = env.Id
        );
        insert req;

        DeploymentRequestActionController.ActionRequest actReq = new DeploymentRequestActionController.ActionRequest();
        actReq.requestId = req.Id;
        actReq.actionType = 'Cancel';

        Test.startTest();
        List<DeploymentRequestActionController.ActionResult> results = DeploymentRequestActionController.executeAction(
            new List<DeploymentRequestActionController.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one action response');
        System.assert(results[0].success, 'Expected invocable cancellation to succeed');
    }

    @isTest
    static void testInvocableInvalidActionType() {
        Deployment_Request__c req = new Deployment_Request__c(Status__c = 'Draft');
        insert req;

        DeploymentRequestActionController.ActionRequest actReq = new DeploymentRequestActionController.ActionRequest();
        actReq.requestId = req.Id;
        actReq.actionType = 'InvalidAction';

        Test.startTest();
        List<DeploymentRequestActionController.ActionResult> results = DeploymentRequestActionController.executeAction(
            new List<DeploymentRequestActionController.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one action response');
        System.assert(!results[0].success, 'Expected validation to fail for invalid action type');
        System.assert(results[0].message.contains('Invalid action type'), 'Expected invalid type error message');
    }
}