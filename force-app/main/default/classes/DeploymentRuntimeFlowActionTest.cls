@isTest
private class DeploymentRuntimeFlowActionTest {

    @isTest
    static void testExecuteValidateAction() {
        // Create environment
        Deployment_Environment__c env = new Deployment_Environment__c(Name = 'Target Env');
        insert env;

        // Create credential
        Credentials__c cred = new Credentials__c(
            Name = 'Target Cred',
            Deployment_Environment__c = env.Id,
            Instance_URL__c = 'https://login.salesforce.com',
            SFDX_Auth_URL__c = 'force://test-auth-url'
        );
        insert cred;

        // Create deployment request
        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Draft',
            Target_Environment__c = env.Id
        );
        insert req;

        DeploymentRuntimeFlowAction.ActionRequest actReq = new DeploymentRuntimeFlowAction.ActionRequest();
        actReq.recordId = req.Id;
        actReq.actionType = 'Validate';

        Test.startTest();
        List<DeploymentRuntimeFlowAction.ActionResult> results = DeploymentRuntimeFlowAction.execute(
            new List<DeploymentRuntimeFlowAction.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one response result');
        System.assert(results[0].success, 'Expected invocable validation action to return success');
        System.assertEquals('Validating', results[0].currentStatus);
        System.assertEquals(req.Id, results[0].requestId);
    }

    @isTest
    static void testExecuteCancelAction() {
        Deployment_Environment__c env = new Deployment_Environment__c(Name = 'Target Env');
        insert env;

        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Pending',
            Target_Environment__c = env.Id
        );
        insert req;

        DeploymentRuntimeFlowAction.ActionRequest actReq = new DeploymentRuntimeFlowAction.ActionRequest();
        actReq.recordId = req.Id;
        actReq.actionType = 'Cancel';

        Test.startTest();
        List<DeploymentRuntimeFlowAction.ActionResult> results = DeploymentRuntimeFlowAction.execute(
            new List<DeploymentRuntimeFlowAction.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one response result');
        System.assert(results[0].success, 'Expected invocable cancel action to return success');
        System.assertEquals('Cancelled', results[0].currentStatus);
    }

    @isTest
    static void testExecuteInvalidAction() {
        Deployment_Request__c req = new Deployment_Request__c(Status__c = 'Draft');
        insert req;

        DeploymentRuntimeFlowAction.ActionRequest actReq = new DeploymentRuntimeFlowAction.ActionRequest();
        actReq.recordId = req.Id;
        actReq.actionType = 'InvalidAction';

        Test.startTest();
        List<DeploymentRuntimeFlowAction.ActionResult> results = DeploymentRuntimeFlowAction.execute(
            new List<DeploymentRuntimeFlowAction.ActionRequest>{ actReq }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one response result');
        System.assert(!results[0].success, 'Expected invalid action to fail');
        System.assertEquals('Failed', results[0].currentStatus);
        System.assert(results[0].message.contains('Invalid action type'), 'Expected invalid type error message');
    }
}
