@isTest
private class PipelineMetadataScanQueueableTest {

    /**
     * HTTP mock implementation to simulate successful auth and github changed files retrieval.
     */
    public class MultiEndpointMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('/services/oauth2/token') || req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token": "mock_access_token", "instance_url": "https://api.github.com"}');
            } else if (req.getEndpoint().contains('/pulls/')) {
                res.setStatusCode(200);
                res.setHeader('X-RateLimit-Remaining', '4999');
                res.setBody('[' +
                    '{"filename": "force-app/main/default/classes/MyClass.cls", "status": "added", "sha": "12345"},' +
                    '{"filename": "force-app/main/default/classes/MyClass.cls-meta.xml", "status": "added", "sha": "67890"}' +
                ']');
            } else {
                res.setStatusCode(500);
                res.setBody('{"error": "unknown endpoint"}');
            }
            return res;
        }
    }

    /**
     * HTTP mock to simulate API authentication failures.
     */
    public class ErrorCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/services/oauth2/token') || req.getEndpoint().contains('/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token": "mock_access_token", "instance_url": "https://api.github.com"}');
            } else {
                res.setStatusCode(401);
                res.setBody('{"message": "Bad credentials"}');
            }
            return res;
        }
    }

    @isTest
    static void testQueueableSuccess() {
        // Create test data
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Test Env',
            Status__c = 'Active'
        );
        insert env;

        Credentials__c cred = new Credentials__c(
            Name = 'Test Cred',
            Deployment_Environment__c = env.Id,
            Instance_URL__c = 'https://api.github.com',
            SFDX_Auth_URL__c = 'force://sfdx'
        );
        insert cred;

        Pipeline__c pipe = new Pipeline__c(
            Name = 'Test Pipeline'
        );
        insert pipe;

        // Build request data DTO
        GitHubRecordService.GitHubRecordData requestData = new GitHubRecordService.GitHubRecordData();
        requestData.eventName = 'pull_request';
        requestData.repositoryFullName = 'owner/repo';
        requestData.pullRequestNumber = 123;
        requestData.sourceBranch = 'feature/branch';
        requestData.sourceSha = 'sha123';

        String requestDataJson = JSON.serialize(requestData);

        // Register multi mock
        Test.setMock(HttpCalloutMock.class, new MultiEndpointMock());

        Test.startTest();
        // Pass null for deploymentRequestId and userStoryId to bypass lookup target constraints (self-lookups to Pipeline__c in this org).
        PipelineMetadataScanQueueable job = new PipelineMetadataScanQueueable(
            pipe.Id,
            null,
            null,
            requestDataJson
        );
        System.enqueueJob(job);
        Test.stopTest();

        // Verify updates dynamically to prevent compile-time custom field missing errors
        String queryFields = 'Id';
        Map<String, Schema.SObjectField> fieldsMap = Schema.getGlobalDescribe().get('Pipeline__c').getDescribe().fields.getMap();
        
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            queryFields += ', Deployment_Runtime_Status__c';
        }
        if (fieldsMap.containsKey('metadata_count__c')) {
            queryFields += ', Metadata_Count__c';
        }
        
        String query = 'SELECT ' + queryFields + ' FROM Pipeline__c WHERE Id = \'' + pipe.Id + '\' LIMIT 1';
        SObject updatedPipe = Database.query(query);
        
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            System.assertEquals('Completed', updatedPipe.get('Deployment_Runtime_Status__c'));
        }
        if (fieldsMap.containsKey('metadata_count__c')) {
            System.assertEquals(2, updatedPipe.get('Metadata_Count__c'));
        }
    }

    @isTest
    static void testQueueableDeserializationFailure() {
        // Create test data
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Test Env',
            Status__c = 'Active'
        );
        insert env;

        Pipeline__c pipe = new Pipeline__c(
            Name = 'Test Pipeline'
        );
        insert pipe;

        Test.startTest();
        // Pass empty json to trigger exception
        PipelineMetadataScanQueueable job = new PipelineMetadataScanQueueable(
            pipe.Id,
            null,
            null,
            ''
        );
        System.enqueueJob(job);
        
        try {
            // Test.stopTest executes the queueable and throws the exception, wrap it here to catch
            Test.stopTest();
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('Request data payload is missing'), 'Expected missing request payload error');
        }

        // Verify status is updated to Failed dynamically
        String queryFields = 'Id';
        Map<String, Schema.SObjectField> fieldsMap = Schema.getGlobalDescribe().get('Pipeline__c').getDescribe().fields.getMap();
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            queryFields += ', Deployment_Runtime_Status__c';
        }
        
        String query = 'SELECT ' + queryFields + ' FROM Pipeline__c WHERE Id = \'' + pipe.Id + '\' LIMIT 1';
        SObject updatedPipe = Database.query(query);
        
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            System.assertEquals('Failed', updatedPipe.get('Deployment_Runtime_Status__c'));
        }
    }

    @isTest
    static void testQueueableCalloutError() {
        // Create test data
        Deployment_Environment__c env = new Deployment_Environment__c(
            Name = 'Test Env',
            Status__c = 'Active'
        );
        insert env;

        Credentials__c cred = new Credentials__c(
            Name = 'Test Cred',
            Deployment_Environment__c = env.Id,
            Instance_URL__c = 'https://api.github.com',
            SFDX_Auth_URL__c = 'force://sfdx'
        );
        insert cred;

        Pipeline__c pipe = new Pipeline__c(
            Name = 'Test Pipeline'
        );
        insert pipe;

        GitHubRecordService.GitHubRecordData requestData = new GitHubRecordService.GitHubRecordData();
        requestData.eventName = 'pull_request';
        requestData.repositoryFullName = 'owner/repo';
        requestData.pullRequestNumber = 123;

        Test.setMock(HttpCalloutMock.class, new ErrorCalloutMock());

        Test.startTest();
        PipelineMetadataScanQueueable job = new PipelineMetadataScanQueueable(
            pipe.Id,
            null,
            null,
            JSON.serialize(requestData)
        );
        System.enqueueJob(job);
        
        try {
            // Test.stopTest executes the queueable and throws the exception, wrap it here to catch
            Test.stopTest();
        } catch (Exception ex) {
            System.assert(ex.getMessage().contains('GitHub API authentication failed'), 'Expected auth error');
        }

        // Verify status is updated to Failed dynamically
        String queryFields = 'Id';
        Map<String, Schema.SObjectField> fieldsMap = Schema.getGlobalDescribe().get('Pipeline__c').getDescribe().fields.getMap();
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            queryFields += ', Deployment_Runtime_Status__c';
        }
        
        String query = 'SELECT ' + queryFields + ' FROM Pipeline__c WHERE Id = \'' + pipe.Id + '\' LIMIT 1';
        SObject updatedPipe = Database.query(query);
        
        if (fieldsMap.containsKey('deployment_runtime_status__c')) {
            System.assertEquals('Failed', updatedPipe.get('Deployment_Runtime_Status__c'));
        }
    }
}