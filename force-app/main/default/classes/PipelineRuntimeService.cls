public with sharing class PipelineRuntimeService {

    // Instance fields stored as static variables for synchronous execution context
    private static Id currentDeploymentRequestId;
    private static Pipeline__c currentPipeline;
    private static Deployment_Request__c currentDeploymentRequest;
    private static User_Story__c currentUserStory;
    private static Deployment_Environment__c sourceEnvironment;
    private static Deployment_Environment__c targetEnvironment;
    private static Credentials__c currentCredential;

    // Webhook runtime context fields
    private static String currentBranch;
    private static Integer currentPrNumber;
    private static String currentPrUrl;
    private static String currentCommitId;

    // Fields to query dynamically to prevent compilation and execution errors
    private static final List<String> PIPELINE_FIELDS = new List<String>{
        'Current_Deployment_Request__c',
        'Current_User_Story__c',
        'Current_Repository__c',
        'Current_Branch__c',
        'Current_PR_Number__c',
        'Current_PR_URL__c',
        'Current_Commit_Id__c',
        'Current_Environment__c',
        'Current_Stage__c',
        'Pipeline_Runtime_Status__c',
        'Execution_Started_On__c',
        'Execution_Completed_On__c',
        'Execution_Duration__c',
        'QA_Approved__c',
        'QA_Approved_By__c',
        'QA_Approved_On__c',
        'UAT_Approved__c',
        'UAT_Approved_By__c',
        'UAT_Approved_On__c',
        'Validation_Runtime_Status__c',
        'Deployment_Runtime_Status__c',
        'Rollback_Status__c',
        'Last_Deployment_Result__c',
        'Last_Error_Message__c'
    };

    /**
     * Start the Pipeline Runtime Engine for a deployment request.
     */
    public static void startPipeline(Id deploymentRequestId) {
        startPipeline(deploymentRequestId, null);
    }

    /**
     * Start the Pipeline Runtime Engine for a deployment request with webhook data.
     */
    public static void startPipeline(Id deploymentRequestId, GitHubRecordService.GitHubRecordData requestData) {
        if (deploymentRequestId == null) {
            return;
        }

        // Reset runtime execution state (ensures bulk safety when invoked sequentially)
        currentDeploymentRequestId = deploymentRequestId;
        currentPipeline = null;
        currentDeploymentRequest = null;
        currentUserStory = null;
        sourceEnvironment = null;
        targetEnvironment = null;
        currentCredential = null;

        // Initialize runtime fields from request data
        if (requestData != null) {
            currentBranch = requestData.sourceBranch;
            currentPrNumber = requestData.pullRequestNumber;
            currentPrUrl = requestData.pullRequestUrl;
            currentCommitId = requestData.sourceSha;
        } else {
            currentBranch = null;
            currentPrNumber = null;
            currentPrUrl = null;
            currentCommitId = null;
        }

        // Load related records
        loadDeploymentRequest();
        loadPipeline();
        loadUserStory();
        loadSourceEnvironment();
        loadTargetEnvironment();
        loadCredential();

        // Fallback fields from database if requestData was not provided
        if (requestData == null) {
            if (currentDeploymentRequest != null) {
                currentBranch = currentDeploymentRequest.Branch_Name__c;
            }
            if (currentUserStory != null) {
                currentPrNumber = getIntegerPrNumber(currentUserStory);
                currentPrUrl = (String) getFirstExistingFieldValue(currentUserStory, new List<String>{ 'Pull_Request_URL__c', 'GitHub_PR_URL__c', 'External_URL__c' });
            }
        }

        // Run engine logic
        updateRuntimeFields();
        finishPipeline();

        // Enqueue asynchronous metadata scan job (Callout-DML boundary safe)
        if (requestData != null) {
            System.enqueueJob(
                new PipelineMetadataScanQueueable(
                    currentPipeline != null ? currentPipeline.Id : null,
                    deploymentRequestId,
                    currentUserStory != null ? currentUserStory.Id : null,
                    JSON.serialize(requestData)
                )
            );
        }
    }

    /**
     * Loads the target Pipeline record (Only one existing record).
     */
    private static Pipeline__c loadPipeline() {
        if (currentPipeline != null) {
            return currentPipeline;
        }

        List<String> fields = getExistingFields('Pipeline__c', PIPELINE_FIELDS);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Pipeline__c';
        
        if (currentDeploymentRequest != null && currentDeploymentRequest.Pipeline__c != null) {
            Id pipelineId = currentDeploymentRequest.Pipeline__c;
            query += ' WHERE Id = :pipelineId';
        }
        query += ' LIMIT 1';

        List<Pipeline__c> results = Database.query(query);
        if (results.isEmpty() && currentDeploymentRequest != null && currentDeploymentRequest.Pipeline__c != null) {
            // Fallback to query any available Pipeline if the lookup-referenced one is not found
            String fallbackQuery = 'SELECT ' + String.join(fields, ', ') + ' FROM Pipeline__c LIMIT 1';
            results = Database.query(fallbackQuery);
        }

        if (results.isEmpty()) {
            throw new PipelineException('No Pipeline__c records exist in the system.');
        }

        currentPipeline = results[0];
        return currentPipeline;
    }

    /**
     * Loads the current Deployment Request.
     */
    private static Deployment_Request__c loadDeploymentRequest() {
        if (currentDeploymentRequest != null) {
            return currentDeploymentRequest;
        }
        if (currentDeploymentRequestId == null) {
            return null;
        }

        List<String> fieldList = new List<String>{
            'Id', 'Name', 'Branch_Name__c', 'Status__c', 'Validation_Status__c',
            'Deployment_Result__c', 'Source_Environment__c', 'Target_Environment__c',
            'Credential__c', 'Pipeline__c', 'User_Story__c'
        };
        List<String> fields = getExistingFields('Deployment_Request__c', fieldList);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Deployment_Request__c WHERE Id = :currentDeploymentRequestId LIMIT 1';
        
        List<Deployment_Request__c> results = Database.query(query);
        if (!results.isEmpty()) {
            currentDeploymentRequest = results[0];
        }
        return currentDeploymentRequest;
    }

    /**
     * Loads the User Story linked to the deployment request.
     */
    private static User_Story__c loadUserStory() {
        if (currentUserStory != null) {
            return currentUserStory;
        }
        if (currentDeploymentRequest == null || currentDeploymentRequest.User_Story__c == null) {
            return null;
        }

        Id userStoryId = currentDeploymentRequest.User_Story__c;
        List<String> fieldList = new List<String>{
            'Id', 'Name', 'Pull_Request_Number__c', 'PR_Number__c', 'Pull_Request_URL__c',
            'GitHub_PR_URL__c', 'External_URL__c', 'Source_Branch__c', 'Target_Branch__c',
            'Title__c', 'Description__c', 'Story_Status__c', 'Test_Status__c', 'Build_Status__c'
        };
        List<String> fields = getExistingFields('User_Story__c', fieldList);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM User_Story__c WHERE Id = :userStoryId LIMIT 1';

        List<User_Story__c> results = Database.query(query);
        if (!results.isEmpty()) {
            currentUserStory = results[0];
        }
        return currentUserStory;
    }

    /**
     * Loads the Source Environment.
     */
    private static Deployment_Environment__c loadSourceEnvironment() {
        if (sourceEnvironment != null) {
            return sourceEnvironment;
        }
        if (currentDeploymentRequest == null || currentDeploymentRequest.Source_Environment__c == null) {
            return null;
        }

        Id envId = currentDeploymentRequest.Source_Environment__c;
        List<String> fieldList = new List<String>{ 'Id', 'Name', 'Environment_Type__c', 'Status__c' };
        List<String> fields = getExistingFields('Deployment_Environment__c', fieldList);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Deployment_Environment__c WHERE Id = :envId LIMIT 1';

        List<Deployment_Environment__c> results = Database.query(query);
        if (!results.isEmpty()) {
            sourceEnvironment = results[0];
        }
        return sourceEnvironment;
    }

    /**
     * Loads the Target Environment.
     */
    private static Deployment_Environment__c loadTargetEnvironment() {
        if (targetEnvironment != null) {
            return targetEnvironment;
        }
        if (currentDeploymentRequest == null || currentDeploymentRequest.Target_Environment__c == null) {
            return null;
        }

        Id envId = currentDeploymentRequest.Target_Environment__c;
        List<String> fieldList = new List<String>{ 'Id', 'Name', 'Environment_Type__c', 'Status__c' };
        List<String> fields = getExistingFields('Deployment_Environment__c', fieldList);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Deployment_Environment__c WHERE Id = :envId LIMIT 1';

        List<Deployment_Environment__c> results = Database.query(query);
        if (!results.isEmpty()) {
            targetEnvironment = results[0];
        }
        return targetEnvironment;
    }

    /**
     * Loads the Credential record.
     */
    private static Credentials__c loadCredential() {
        if (currentCredential != null) {
            return currentCredential;
        }
        if (currentDeploymentRequest == null || currentDeploymentRequest.Credential__c == null) {
            return null;
        }

        Id credId = currentDeploymentRequest.Credential__c;
        List<String> fieldList = new List<String>{ 'Id', 'Name' };
        List<String> fields = getExistingFields('Credentials__c', fieldList);
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Credentials__c WHERE Id = :credId LIMIT 1';

        List<Credentials__c> results = Database.query(query);
        if (!results.isEmpty()) {
            currentCredential = results[0];
        }
        return currentCredential;
    }

    /**
     * Updates the Pipeline's runtime execution fields.
     */
    private static void updateRuntimeFields() {
        if (currentPipeline == null) {
            return;
        }

        putLookupIfValid(currentPipeline, 'Current_Deployment_Request__c', currentDeploymentRequest != null ? currentDeploymentRequest.Id : null);
        putLookupIfValid(currentPipeline, 'Current_User_Story__c', currentUserStory != null ? currentUserStory.Id : null);

        // Find Repository Lookup Id dynamically from the Pipeline record fields if available
        Id repositoryId = (Id) getFirstExistingFieldValue(currentPipeline, new List<String>{ 'Git_Repository__c', 'Repository__c' });
        putLookupIfValid(currentPipeline, 'Current_Repository__c', repositoryId);

        putIfFieldExists(currentPipeline, 'Current_Branch__c', currentBranch);
        putIfFieldExists(currentPipeline, 'Current_PR_Number__c', currentPrNumber);
        putIfFieldExists(currentPipeline, 'Current_PR_URL__c', currentPrUrl);
        putIfFieldExists(currentPipeline, 'Current_Commit_Id__c', currentCommitId);
        putIfFieldExists(currentPipeline, 'Current_Environment__c', currentDeploymentRequest != null ? currentDeploymentRequest.Target_Environment__c : null);

        // Map Target Environment type to Stage
        String stageValue = 'DEV';
        if (targetEnvironment != null) {
            String envType = (String) getFieldValueSafe(targetEnvironment, 'Environment_Type__c');
            if (envType == 'DEV') {
                stageValue = 'DEV';
            } else if (envType == 'QA') {
                stageValue = 'QA';
            } else if (envType == 'SP' || envType == 'POD3') {
                stageValue = 'UAT';
            } else if (envType == 'PROD') {
                stageValue = 'PRODUCTION';
            }
        }
        putIfFieldExists(currentPipeline, 'Current_Stage__c', stageValue);

        // Set Pipeline Runtime Status and Execution Started On
        putIfFieldExists(currentPipeline, 'Pipeline_Runtime_Status__c', 'Running');
        putIfFieldExists(currentPipeline, 'Execution_Started_On__c', System.now());

        // Reset validation, deployment, and error states for a clean run
        putIfFieldExists(currentPipeline, 'Execution_Completed_On__c', null);
        putIfFieldExists(currentPipeline, 'Execution_Duration__c', null);
        putIfFieldExists(currentPipeline, 'Validation_Runtime_Status__c', 'Pending');
        putIfFieldExists(currentPipeline, 'Deployment_Runtime_Status__c', 'Pending');
        putIfFieldExists(currentPipeline, 'Rollback_Status__c', null);
        putIfFieldExists(currentPipeline, 'Last_Deployment_Result__c', null);
        putIfFieldExists(currentPipeline, 'Last_Error_Message__c', null);
    }

    /**
     * Saves the updated Pipeline record.
     */
    private static void finishPipeline() {
        if (currentPipeline != null) {
            update currentPipeline;
        }
    }

    // --- Dynamic Schema Helper Methods ---

    private static List<String> getExistingFields(String objectName, List<String> fieldNames) {
        Set<String> uniqueFields = new Set<String>{ 'Id' };
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectName);
        if (sobjType == null) {
            return new List<String>(uniqueFields);
        }
        Map<String, Schema.SObjectField> fieldsMap = sobjType.getDescribe().fields.getMap();
        for (String fieldName : fieldNames) {
            if (fieldsMap.containsKey(fieldName.toLowerCase()) || fieldsMap.containsKey(fieldName)) {
                String correctName = fieldName;
                if (fieldsMap.containsKey(fieldName.toLowerCase())) {
                    correctName = fieldsMap.get(fieldName.toLowerCase()).getDescribe().getName();
                }
                uniqueFields.add(correctName);
            }
        }
        return new List<String>(uniqueFields);
    }

    private static void putIfFieldExists(SObject record, String fieldName, Object value) {
        if (record == null) {
            return;
        }
        Map<String, Schema.SObjectField> fieldsMap = record.getSObjectType().getDescribe().fields.getMap();
        if (fieldsMap.containsKey(fieldName.toLowerCase()) || fieldsMap.containsKey(fieldName)) {
            record.put(fieldName, value);
        }
    }

    private static void putLookupIfValid(SObject record, String fieldName, Id targetId) {
        if (record == null) {
            return;
        }
        if (targetId == null) {
            putIfFieldExists(record, fieldName, null);
            return;
        }
        Map<String, Schema.SObjectField> fieldsMap = record.getSObjectType().getDescribe().fields.getMap();
        Schema.SObjectField fld = fieldsMap.containsKey(fieldName.toLowerCase()) ? fieldsMap.get(fieldName.toLowerCase()) : fieldsMap.get(fieldName);
        if (fld != null) {
            Schema.DescribeFieldResult fldDesc = fld.getDescribe();
            if (fldDesc.getType() == Schema.DisplayType.Reference && !fldDesc.getReferenceTo().isEmpty()) {
                Schema.SObjectType refType = fldDesc.getReferenceTo()[0];
                if (refType == targetId.getSObjectType()) {
                    record.put(fieldName, targetId);
                } else {
                    System.debug(LoggingLevel.WARN, 'Skipped lookup ' + fieldName + ' due to target type mismatch.');
                }
            } else {
                putIfFieldExists(record, fieldName, targetId);
            }
        }
    }

    private static Object getFieldValueSafe(SObject record, String fieldName) {
        if (record == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldsMap = record.getSObjectType().getDescribe().fields.getMap();
        if (fieldsMap.containsKey(fieldName.toLowerCase()) || fieldsMap.containsKey(fieldName)) {
            return record.get(fieldName);
        }
        return null;
    }

    private static Object getFirstExistingFieldValue(SObject record, List<String> candidateFields) {
        if (record == null || candidateFields == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldsMap = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : candidateFields) {
            if (fieldsMap.containsKey(fieldName.toLowerCase()) || fieldsMap.containsKey(fieldName)) {
                return record.get(fieldName);
            }
        }
        return null;
    }

    private static Integer getIntegerPrNumber(SObject record) {
        Object val = getFirstExistingFieldValue(record, new List<String>{ 'Pull_Request_Number__c', 'PR_Number__c' });
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return ((Decimal) val).intValue();
        }
        if (val instanceof Integer) {
            return (Integer) val;
        }
        try {
            return Integer.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Custom Pipeline Runtime Exception.
     */
    public class PipelineException extends Exception {}
}