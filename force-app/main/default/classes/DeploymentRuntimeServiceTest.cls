@isTest
private class DeploymentRuntimeServiceTest {

    @isTest
    static void testStartDeploymentSuccess() {
        // Create target environment
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Target Env'
        );
        insert env;

        // Create credentials linked to environment
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

        Test.startTest();
        DeploymentRuntimeService.DeploymentResult res = DeploymentRuntimeService.startDeployment(req.Id, 'Validate');
        Test.stopTest();

        // Verify status transitioned to the active validation state.
        System.assert(res.success, 'Expected start to return success');
        System.assertEquals('Validating', res.currentStatus);

        Deployment_Request__c updatedReq = [
            SELECT Id, Status__c, Credential__c, Started_On__c 
            FROM Deployment_Request__c 
            WHERE Id = :req.Id
        ];
        System.assertEquals('Validated', updatedReq.Status__c);
        System.assertEquals(cred.Id, updatedReq.Credential__c);
        System.assertNotEquals(null, updatedReq.Started_On__c);

        List<Deployment_Log__c> logs = [
            SELECT Id, Message__c 
            FROM Deployment_Log__c 
            WHERE Deployment_Request__c = :req.Id
        ];
        System.assert(logs.size() > 0, 'Expected at least 1 log entry created');
    }

    @isTest
    static void testCancelDeploymentSuccess() {
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Target Env'
        );
        insert env;

        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Pending',
            Target_Environment__c = env.Id
        );
        insert req;

        Test.startTest();
        Boolean cancelResult = DeploymentRuntimeService.cancelDeployment(req.Id);
        Test.stopTest();

        System.assert(cancelResult, 'Expected cancel to return true');

        Deployment_Request__c updatedReq = [
            SELECT Id, Status__c, Completed_On__c 
            FROM Deployment_Request__c 
            WHERE Id = :req.Id
        ];
        System.assertEquals('Cancelled', updatedReq.Status__c);
        System.assertNotEquals(null, updatedReq.Completed_On__c);
    }

    @isTest
    static void testGetDeploymentStatus() {
        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Draft'
        );
        insert req;

        Deployment_Log__c log = new Deployment_Log__c(
            Deployment_Request__c = req.Id,
            Log_Type__c = 'Info',
            Message__c = 'Test Log',
            Timestamp__c = System.now()
        );
        insert log;

        Test.startTest();
        DeploymentRuntimeService.DeploymentStatusResult statusRes = DeploymentRuntimeService.getDeploymentStatus(req.Id);
        Test.stopTest();

        System.assertEquals('Draft', statusRes.status);
        System.assertEquals(1, statusRes.logs.size());
        System.assertEquals('Test Log', statusRes.logs[0].Message__c);
    }

    @isTest
    static void testStartDeploymentPreconditionsFailure() {
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Target Env'
        );
        insert env;

        // Test that running requests throw validation error
        Deployment_Request__c req = new Deployment_Request__c(
            Status__c = 'Deploying',
            Target_Environment__c = env.Id
        );
        insert req;

        try {
            Test.startTest();
            DeploymentRuntimeService.startDeployment(req.Id, 'Validate');
            Test.stopTest();
            System.assert(false, 'Expected validation exception');
        } catch (DeploymentRuntimeService.DeploymentRuntimeServiceException ex) {
            System.assert(ex.getMessage().contains('Another execution is already in progress'));
        }
    }
}
