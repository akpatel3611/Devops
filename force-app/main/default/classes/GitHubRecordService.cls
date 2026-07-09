/**
 * Record service for GitHub webhook persistence.
 *
 * This class owns Salesforce database interaction. It uses dynamic schema
 * access so the package can compile before optional deployment-lifecycle
 * objects are added, while still using those objects when available.
 */
public with sharing class GitHubRecordService {
    private static final String STATUS_PROCESSED = 'processed';
    private static final String STATUS_SKIPPED = 'skipped';
    private static final String STATUS_ERROR = 'error';

    private static final String FIELD_ID = 'Id';
    private static final String FIELD_NAME = 'Name';

    private static final List<String> REPOSITORY_OBJECTS = new List<String>{
        'Git_Repository__c',
        'Repository__c'
    };
    private static final List<String> USER_STORY_OBJECTS = new List<String>{
        'User_Story__c'
    };
    private static final List<String> DEPLOYMENT_REQUEST_OBJECTS = new List<String>{
        'Deployment_Request__c'
    };
    private static final List<String> DEPLOYMENT_LOG_OBJECTS = new List<String>{
        'Deployment_Log__c'
    };
    private static final List<String> PIPELINE_OBJECTS = new List<String>{
        'Pipeline__c',
        'Deployment_Pipeline__c'
    };
    private static final List<String> ENVIRONMENT_OBJECTS = new List<String>{
        'Deployment_Environment__c'
    };
    private static final List<String> CREDENTIAL_OBJECTS = new List<String>{
        'Credentials__c'
    };

    private static final List<String> REPOSITORY_GITHUB_ID_FIELDS = new List<String>{
        'GitHub_Id__c',
        'Github_Id__c',
        'External_Id__c'
    };
    private static final List<String> REPOSITORY_FULL_NAME_FIELDS = new List<String>{
        'Full_Name__c',
        'Repository_Full_Name__c',
        'GitHub_Full_Name__c'
    };
    private static final List<String> REPOSITORY_URL_FIELDS = new List<String>{
        'Repository_URL__c',
        'GitHub_URL__c',
        'URL__c'
    };
    private static final List<String> USER_STORY_PR_URL_FIELDS = new List<String>{
        'Pull_Request_URL__c',
        'GitHub_PR_URL__c',
        'External_URL__c'
    };
    private static final List<String> LOOKUP_REPOSITORY_FIELDS = new List<String>{
        'Git_Repository__c',
        'Repository__c'
    };
    private static final List<String> LOOKUP_USER_STORY_FIELDS = new List<String>{
        'User_Story__c'
    };
    private static final List<String> LOOKUP_PIPELINE_FIELDS = new List<String>{
        'Pipeline__c',
        'Deployment_Pipeline__c'
    };
    private static final List<String> LOOKUP_ENVIRONMENT_FIELDS = new List<String>{
        'Deployment_Environment__c',
        'Environment__c'
    };
    private static final List<String> LOOKUP_CREDENTIAL_FIELDS = new List<String>{
        'Credentials__c',
        'Credential__c'
    };

    /**
     * Processes one pull request webhook.
     */
    public static RecordResult processPullRequest(GitHubRecordData requestData) {
        List<RecordResult> results =
            processPullRequests(new List<GitHubRecordData>{ requestData });
        return results.isEmpty() ? buildResult(STATUS_SKIPPED, 'No pull request data processed.') : results[0];
    }

    /**
     * Processes pull request webhook records in a bulk-safe flow.
     */
    public static List<RecordResult> processPullRequests(List<GitHubRecordData> requestList) {
        List<RecordResult> results = new List<RecordResult>();
        List<GitHubRecordData> validRequests = removeEmptyRequests(requestList);

        if (validRequests.isEmpty()) {
            results.add(buildResult(STATUS_SKIPPED, 'No valid GitHub pull request data received.'));
            return results;
        }

        try {
            Map<String, SObject> repositoriesByKey = upsertRepositories(validRequests);
            Map<String, SObject> userStoriesByKey = upsertUserStories(validRequests);
            Map<String, SObject> pipelinesByRepositoryKey = findPipelines(repositoriesByKey);
            SObject environmentRecord = findEnvironment();
            SObject credentialRecord = findCredential(environmentRecord);

            Map<String, SObject> deploymentRequestsByPullRequestKey =
                createDeploymentRequests(
                    validRequests,
                    repositoriesByKey,
                    userStoriesByKey,
                    pipelinesByRepositoryKey,
                    environmentRecord,
                    credentialRecord
                );

            for (GitHubRecordData requestData : validRequests) {
                String pullRequestKey = buildPullRequestKey(requestData);
                SObject depReq = deploymentRequestsByPullRequestKey.get(pullRequestKey);
                if (depReq != null && depReq.Id != null) {
                    PipelineRuntimeService.startPipeline(depReq.Id, requestData);
                }
            }

            createDeploymentLogs(validRequests, deploymentRequestsByPullRequestKey);

            for (GitHubRecordData requestData : validRequests) {
                results.add(buildResult(STATUS_PROCESSED, 'GitHub pull request processed.'));
            }
        } catch (Exception processingException) {
            throw processingException;
        }

        return results;
    }

    /**
     * Processes repository-only events such as ping and push.
     */
    public static RecordResult processRepositoryEvent(GitHubRecordData requestData) {
        if (requestData == null) {
            return buildResult(STATUS_SKIPPED, 'No GitHub repository data received.');
        }

        try {
            upsertRepositories(new List<GitHubRecordData>{ requestData });
            return buildResult(STATUS_PROCESSED, 'GitHub repository event processed.');
        } catch (Exception processingException) {
                System.debug('ERROR2 : ' + processingException.getMessage());
                System.debug(processingException.getStackTraceString());

                throw processingException;
            }
    }

    /**
     * Finds an existing Git repository record for one webhook.
     */
    public static SObject findRepository(GitHubRecordData requestData) {
        if (requestData == null) {
            return null;
        }
        Map<String, SObject> repositories =
            findRepositories(new List<GitHubRecordData>{ requestData });
        return repositories.get(buildRepositoryKey(requestData));
    }

    /**
     * Creates or updates one Git repository record.
     */
    public static SObject createRepository(GitHubRecordData requestData) {
        if (requestData == null) {
            return null;
        }
        Map<String, SObject> repositories =
            upsertRepositories(new List<GitHubRecordData>{ requestData });
        return repositories.get(buildRepositoryKey(requestData));
    }

    /**
     * Finds an existing pipeline for a repository.
     */
    public static SObject findPipeline(SObject repositoryRecord) {
        if (repositoryRecord == null) {
            return null;
        }
        Map<String, SObject> repositoriesByKey = new Map<String, SObject>{
            String.valueOf(repositoryRecord.get(FIELD_ID)) => repositoryRecord
        };
        return findPipelines(repositoriesByKey).get(String.valueOf(repositoryRecord.get(FIELD_ID)));
    }

    /**
     * Creates one deployment request.
     */
    public static SObject createDeploymentRequest(GitHubRecordData requestData) {
    SObject environmentRecord = findEnvironment();
    SObject credentialRecord = findCredential(environmentRecord);

    Map<String, SObject> createdRecords =
        createDeploymentRequests(
            new List<GitHubRecordData>{ requestData },
            new Map<String, SObject>(),
            new Map<String, SObject>(),
            new Map<String, SObject>(),
            environmentRecord,
            credentialRecord
        );

    return createdRecords.get(buildPullRequestKey(requestData));
}

    /**
     * Creates one deployment log.
     */
    public static SObject createDeploymentLog(GitHubRecordData requestData) {
        Map<String, SObject> deploymentRequestsByPullRequestKey =
            createDeploymentRequests(
                new List<GitHubRecordData>{ requestData },
                new Map<String, SObject>(),
                new Map<String, SObject>(),
                new Map<String, SObject>(),
                findEnvironment(),
                findCredential(findEnvironment())
            );

        SObject depReq = deploymentRequestsByPullRequestKey.get(buildPullRequestKey(requestData));
        if (depReq != null && depReq.Id != null) {
            PipelineRuntimeService.startPipeline(depReq.Id, requestData);
        }

        List<SObject> createdRecords =
            createDeploymentLogs(
                new List<GitHubRecordData>{ requestData },
                deploymentRequestsByPullRequestKey
            );

        return createdRecords.isEmpty() ? null : createdRecords[0];
    }

    /**
     * Updates or creates the User Story related to a GitHub PR.
     */
    public static SObject updateUserStory(GitHubRecordData requestData) {
        if (requestData == null) {
            return null;
        }
        Map<String, SObject> userStories =
            upsertUserStories(new List<GitHubRecordData>{ requestData });
        return userStories.get(buildPullRequestKey(requestData));
    }

    private static List<GitHubRecordData> removeEmptyRequests(List<GitHubRecordData> requestList) {
        List<GitHubRecordData> validRequests = new List<GitHubRecordData>();
        if (requestList == null) {
            return validRequests;
        }

        for (GitHubRecordData requestData : requestList) {
            if (requestData != null && String.isNotBlank(buildRepositoryKey(requestData))) {
                validRequests.add(requestData);
            }
        }

        return validRequests;
    }

    private static Map<String, SObject> upsertRepositories(List<GitHubRecordData> requestList) {
        String objectApi = firstExistingObject(REPOSITORY_OBJECTS);
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        if (String.isBlank(objectApi)) {
            return recordsByKey;
        }

        Map<String, SObject> existingRecords = findRepositories(requestList);
        List<SObject> recordsToUpsert = new List<SObject>();

        for (GitHubRecordData requestData : requestList) {
            String key = buildRepositoryKey(requestData);
            if (String.isBlank(key)) {
                continue;
            }

            SObject repositoryRecord = existingRecords.get(key);
            if (repositoryRecord == null) {
                repositoryRecord = newSObject(objectApi);
            }

            setIfFieldExists(repositoryRecord, FIELD_NAME, safeName(firstNonBlank(requestData.repositoryFullName, requestData.repositoryName)));
            setFirstExistingField(repositoryRecord, REPOSITORY_GITHUB_ID_FIELDS, requestData.repositoryGitHubId);
            setFirstExistingField(repositoryRecord, REPOSITORY_FULL_NAME_FIELDS, requestData.repositoryFullName);
            setFirstExistingField(repositoryRecord, REPOSITORY_URL_FIELDS, requestData.repositoryUrl);
            setFirstExistingField(repositoryRecord, new List<String>{ 'Default_Branch__c' }, requestData.repositoryDefaultBranch);
            setFirstExistingField(repositoryRecord, new List<String>{ 'Owner__c', 'Repository_Owner__c' }, requestData.repositoryOwner);

            recordsToUpsert.add(repositoryRecord);
            recordsByKey.put(key, repositoryRecord);
        }

        if (!recordsToUpsert.isEmpty()) {
            Database.upsert(recordsToUpsert, false);
        }

        return recordsByKey;
    }

    private static Map<String, SObject> findRepositories(List<GitHubRecordData> requestList) {
        String objectApi = firstExistingObject(REPOSITORY_OBJECTS);
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        if (String.isBlank(objectApi) || requestList == null || requestList.isEmpty()) {
            return recordsByKey;
        }

        Set<String> names = new Set<String>();
        Set<String> fullNames = new Set<String>();
        Set<String> urls = new Set<String>();
        for (GitHubRecordData requestData : requestList) {
            if (String.isNotBlank(requestData.repositoryName)) {
                names.add(requestData.repositoryName);
            }
            if (String.isNotBlank(requestData.repositoryFullName)) {
                names.add(requestData.repositoryFullName);
                fullNames.add(requestData.repositoryFullName);
            }
            if (String.isNotBlank(requestData.repositoryUrl)) {
                urls.add(requestData.repositoryUrl);
            }
        }

        List<String> whereParts = new List<String>();
        if (!names.isEmpty() && fieldExists(objectApi, FIELD_NAME)) {
            whereParts.add('Name IN :names');
        }
        String fullNameField = firstExistingField(objectApi, REPOSITORY_FULL_NAME_FIELDS);
        if (!fullNames.isEmpty() && String.isNotBlank(fullNameField)) {
            whereParts.add(fullNameField + ' IN :fullNames');
        }
        String urlField = firstExistingField(objectApi, REPOSITORY_URL_FIELDS);
        if (!urls.isEmpty() && String.isNotBlank(urlField)) {
            whereParts.add(urlField + ' IN :urls');
        }
        if (whereParts.isEmpty()) {
            return recordsByKey;
        }

        List<String> selectFields = existingFields(objectApi, new List<String>{
            FIELD_ID,
            FIELD_NAME,
            fullNameField,
            urlField
        });
        String soql = 'SELECT ' + String.join(selectFields, ',') +
            ' FROM ' + objectApi + ' WHERE ' + String.join(whereParts, ' OR ');

        for (SObject repositoryRecord : Database.query(soql)) {
            String key = buildRepositoryKey(repositoryRecord, fullNameField, urlField);
            if (String.isNotBlank(key)) {
                recordsByKey.put(key, repositoryRecord);
            }
        }

        return recordsByKey;
    }

    private static Map<String, SObject> upsertUserStories(List<GitHubRecordData> requestList) {
        String objectApi = firstExistingObject(USER_STORY_OBJECTS);
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        if (String.isBlank(objectApi)) {
            return recordsByKey;
        }

        Map<String, SObject> existingRecords = findUserStories(requestList);
        List<SObject> recordsToUpsert = new List<SObject>();

        for (GitHubRecordData requestData : requestList) {
            String key = buildPullRequestKey(requestData);
            if (String.isBlank(key)) {
                continue;
            }

            SObject userStoryRecord = existingRecords.get(key);
            if (userStoryRecord == null) {
                userStoryRecord = newSObject(objectApi);
            }

            setIfFieldExists(userStoryRecord, FIELD_NAME, safeName(requestData.pullRequestTitle));
            setFirstExistingField(userStoryRecord, USER_STORY_PR_URL_FIELDS, requestData.pullRequestUrl);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Pull_Request_Number__c', 'PR_Number__c' }, requestData.pullRequestNumber);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Description__c', 'Story_Description__c' }, requestData.pullRequestDescription);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Source_Branch__c' }, requestData.sourceBranch);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Target_Branch__c' }, requestData.targetBranch);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Author__c', 'GitHub_Author__c' }, requestData.pullRequestAuthor);
            setFirstExistingField(userStoryRecord, new List<String>{ 'Status__c', 'GitHub_State__c' }, requestData.pullRequestState);

            recordsToUpsert.add(userStoryRecord);
            recordsByKey.put(key, userStoryRecord);
        }

        if (!recordsToUpsert.isEmpty()) {
            Database.upsert(recordsToUpsert, false);
        }

        return recordsByKey;
    }

    private static Map<String, SObject> findUserStories(List<GitHubRecordData> requestList) {
        String objectApi = firstExistingObject(USER_STORY_OBJECTS);
        Map<String, SObject> recordsByKey = new Map<String, SObject>();
        if (String.isBlank(objectApi) || requestList == null || requestList.isEmpty()) {
            return recordsByKey;
        }

        String prUrlField = firstExistingField(objectApi, USER_STORY_PR_URL_FIELDS);
        if (String.isBlank(prUrlField)) {
            return recordsByKey;
        }

        Set<String> pullRequestUrls = new Set<String>();
        for (GitHubRecordData requestData : requestList) {
            if (String.isNotBlank(requestData.pullRequestUrl)) {
                pullRequestUrls.add(requestData.pullRequestUrl);
            }
        }
        if (pullRequestUrls.isEmpty()) {
            return recordsByKey;
        }

        List<String> selectFields = existingFields(objectApi, new List<String>{
            FIELD_ID,
            FIELD_NAME,
            prUrlField
        });
        String soql = 'SELECT ' + String.join(selectFields, ',') +
            ' FROM ' + objectApi + ' WHERE ' + prUrlField + ' IN :pullRequestUrls';

        for (SObject userStoryRecord : Database.query(soql)) {
            String key = String.valueOf(userStoryRecord.get(prUrlField));
            if (String.isNotBlank(key)) {
                recordsByKey.put(key, userStoryRecord);
            }
        }

        return recordsByKey;
    }

    private static Map<String, SObject> findPipelines(Map<String, SObject> repositoriesByKey) {
        String objectApi = firstExistingObject(PIPELINE_OBJECTS);
        Map<String, SObject> pipelinesByRepositoryKey = new Map<String, SObject>();
        if (String.isBlank(objectApi) || repositoriesByKey == null || repositoriesByKey.isEmpty()) {
            return pipelinesByRepositoryKey;
        }

        String repositoryLookupField = firstExistingField(objectApi, LOOKUP_REPOSITORY_FIELDS);
        if (String.isBlank(repositoryLookupField)) {
            return pipelinesByRepositoryKey;
        }

        Set<Id> repositoryIds = new Set<Id>();
        Map<String, String> keyByRepositoryId = new Map<String, String>();
        for (String key : repositoriesByKey.keySet()) {
            SObject repositoryRecord = repositoriesByKey.get(key);
            if (repositoryRecord != null && repositoryRecord.get(FIELD_ID) != null) {
                Id repositoryId = (Id) repositoryRecord.get(FIELD_ID);
                repositoryIds.add(repositoryId);
                keyByRepositoryId.put(String.valueOf(repositoryId), key);
            }
        }
        if (repositoryIds.isEmpty()) {
            return pipelinesByRepositoryKey;
        }

        String soql = 'SELECT Id,' + repositoryLookupField +
            ' FROM ' + objectApi +
            ' WHERE ' + repositoryLookupField + ' IN :repositoryIds';

        for (SObject pipelineRecord : Database.query(soql)) {
            String repositoryId = String.valueOf(pipelineRecord.get(repositoryLookupField));
            String key = keyByRepositoryId.get(repositoryId);
            if (String.isNotBlank(key)) {
                pipelinesByRepositoryKey.put(key, pipelineRecord);
            }
        }

        return pipelinesByRepositoryKey;
    }

    private static SObject findEnvironment() {
        String objectApi = firstExistingObject(ENVIRONMENT_OBJECTS);
        if (String.isBlank(objectApi)) {
            return null;
        }

        String whereClause = fieldExists(objectApi, 'Status__c') ? ' WHERE Status__c = \'Active\'' : '';
        List<SObject> environmentRecords =
            Database.query('SELECT Id FROM ' + objectApi + whereClause + ' LIMIT 1');
        return environmentRecords.isEmpty() ? null : environmentRecords[0];
    }

    private static SObject findCredential(SObject environmentRecord) {
        String objectApi = firstExistingObject(CREDENTIAL_OBJECTS);
        if (String.isBlank(objectApi)) {
            return null;
        }

        String environmentLookupField = firstExistingField(objectApi, LOOKUP_ENVIRONMENT_FIELDS);
        if (
            environmentRecord != null &&
            environmentRecord.get(FIELD_ID) != null &&
            String.isNotBlank(environmentLookupField)
        ) {
            Id environmentId = (Id) environmentRecord.get(FIELD_ID);
            List<SObject> credentialRecords =
                Database.query(
                    'SELECT Id FROM ' + objectApi +
                    ' WHERE ' + environmentLookupField + ' = :environmentId LIMIT 1'
                );
            if (!credentialRecords.isEmpty()) {
                return credentialRecords[0];
            }
        }

        List<SObject> fallbackCredentials = Database.query('SELECT Id FROM ' + objectApi + ' LIMIT 1');
        return fallbackCredentials.isEmpty() ? null : fallbackCredentials[0];
    }

    private static Map<String, SObject> createDeploymentRequests(
        List<GitHubRecordData> requestList,
        Map<String, SObject> repositoriesByKey,
        Map<String, SObject> userStoriesByKey,
        Map<String, SObject> pipelinesByRepositoryKey,
        SObject environmentRecord,
        SObject credentialRecord
    ) {
        String objectApi = firstExistingObject(DEPLOYMENT_REQUEST_OBJECTS);
        Map<String, SObject> recordsByPullRequestKey = new Map<String, SObject>();

        if (String.isBlank(objectApi) || requestList == null) {
            return recordsByPullRequestKey;
        }

        List<SObject> recordsToInsert = new List<SObject>();
        List<String> pullRequestKeys = new List<String>();

        for (GitHubRecordData requestData : requestList) {
            SObject deploymentRequest = newSObject(objectApi);
            String repositoryKey = buildRepositoryKey(requestData);
            String pullRequestKey = buildPullRequestKey(requestData);

            setIfFieldExists(
                deploymentRequest,
                FIELD_NAME,
                safeName('PR ' + String.valueOf(requestData.pullRequestNumber) + ' - ' + requestData.pullRequestTitle)
            );
            setFirstExistingField(deploymentRequest, new List<String>{ 'Branch_Name__c' }, requestData.sourceBranch);
            setFirstExistingField(deploymentRequest, new List<String>{ 'Status__c' }, 'Draft');
            setFirstExistingField(deploymentRequest, new List<String>{ 'Validation_Status__c' }, 'Pending');
            setFirstExistingField(
                deploymentRequest,
                new List<String>{ 'Deployment_Result__c' },
                'GitHub delivery ' + requestData.deliveryId + ' received for ' + requestData.eventName + ' / ' + requestData.action
            );

            setLookup(deploymentRequest, LOOKUP_PIPELINE_FIELDS, pipelinesByRepositoryKey.get(repositoryKey));
            setLookup(deploymentRequest, new List<String>{ 'Source_Environment__c' }, environmentRecord);
            setLookup(deploymentRequest, new List<String>{ 'Target_Environment__c' }, environmentRecord);
            setLookup(deploymentRequest, LOOKUP_USER_STORY_FIELDS, userStoriesByKey.get(pullRequestKey));

            recordsToInsert.add(deploymentRequest);
            pullRequestKeys.add(pullRequestKey);
        }

        if (!recordsToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(recordsToInsert, false);

            for (Integer index = 0; index < saveResults.size(); index++) {
                Database.SaveResult saveResult = saveResults[index];
                if (!saveResult.isSuccess()) {
                    String errorMessage = 'Deployment_Request__c insert failed: ';
                    for (Database.Error saveError : saveResult.getErrors()) {
                        errorMessage += saveError.getStatusCode() + ' ' + saveError.getMessage() + ' ';
                    }
                    throw new RecordServiceException(errorMessage.trim());
                }

                recordsToInsert[index].put(FIELD_ID, saveResult.getId());
                recordsByPullRequestKey.put(pullRequestKeys[index], recordsToInsert[index]);
            }
        }

        return recordsByPullRequestKey;
    }

    private static List<SObject> createDeploymentLogs(
        List<GitHubRecordData> requestList,
        Map<String, SObject> deploymentRequestsByPullRequestKey
    ) {
        String objectApi = firstExistingObject(DEPLOYMENT_LOG_OBJECTS);
        List<SObject> recordsToInsert = new List<SObject>();
    
        if (String.isBlank(objectApi) || requestList == null) {
            return recordsToInsert;
        }
    
        for (GitHubRecordData requestData : requestList) {
            SObject deploymentRequest =
                deploymentRequestsByPullRequestKey == null
                    ? null
                    : deploymentRequestsByPullRequestKey.get(buildPullRequestKey(requestData));
        
            SObject deploymentLog = newSObject(objectApi);
            String message = 'GitHub webhook ' + requestData.eventName + ' / ' + requestData.action;
        
            setIfFieldExists(deploymentLog, FIELD_NAME, safeName(message));
            setFirstExistingField(deploymentLog, new List<String>{ 'Message__c' }, message);
            setFirstExistingField(deploymentLog, new List<String>{ 'Log_Type__c' }, 'Info');
            setFirstExistingField(deploymentLog, new List<String>{ 'Timestamp__c' }, System.now());
            setLookup(deploymentLog, new List<String>{ 'Deployment_Request__c' }, deploymentRequest);
        
            recordsToInsert.add(deploymentLog);
        }
    
        if (!recordsToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(recordsToInsert, false);
        
            for (Database.SaveResult saveResult : saveResults) {
                if (!saveResult.isSuccess()) {
                    String errorMessage = 'Deployment_Log__c insert failed: ';
                    for (Database.Error saveError : saveResult.getErrors()) {
                        errorMessage += saveError.getStatusCode() + ' ' + saveError.getMessage() + ' ';
                    }
                    throw new RecordServiceException(errorMessage.trim());
                }
            }
        }
    
        return recordsToInsert;
    }

    private static void setLookup(SObject targetRecord, List<String> candidateFields, SObject sourceRecord) {
        if (sourceRecord == null || sourceRecord.get(FIELD_ID) == null) {
            return;
        }
        setFirstExistingField(targetRecord, candidateFields, sourceRecord.get(FIELD_ID));
    }

    private static SObject newSObject(String objectApi) {
        return Schema.getGlobalDescribe().get(objectApi).newSObject();
    }

    private static String firstExistingObject(List<String> candidateObjects) {
        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        for (String objectApi : candidateObjects) {
            if (describeMap.containsKey(objectApi)) {
                return objectApi;
            }
        }
        return null;
    }

    private static String firstExistingField(String objectApi, List<String> candidateFields) {
        if (String.isBlank(objectApi) || candidateFields == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApi).getDescribe().fields.getMap();
        for (String fieldApi : candidateFields) {
            if (String.isNotBlank(fieldApi) && fieldMap.containsKey(fieldApi)) {
                return fieldApi;
            }
        }
        return null;
    }

    private static Boolean fieldExists(String objectApi, String fieldApi) {
        return String.isNotBlank(firstExistingField(objectApi, new List<String>{ fieldApi }));
    }

    private static List<String> existingFields(String objectApi, List<String> candidateFields) {
        List<String> fields = new List<String>();
        Set<String> seenFields = new Set<String>();

        for (String fieldApi : candidateFields) {
            if (String.isBlank(fieldApi) || seenFields.contains(fieldApi)) {
                continue;
            }
            if (fieldExists(objectApi, fieldApi)) {
                fields.add(fieldApi);
                seenFields.add(fieldApi);
            }
        }

        if (fields.isEmpty()) {
            fields.add(FIELD_ID);
        }
        return fields;
    }

    private static void setFirstExistingField(SObject targetRecord, List<String> candidateFields, Object value) {
        if (targetRecord == null || value == null) {
            return;
        }
        String fieldApi = firstExistingField(targetRecord.getSObjectType().getDescribe().getName(), candidateFields);
        if (String.isNotBlank(fieldApi)) {
            targetRecord.put(fieldApi, value);
        }
    }

    private static void setIfFieldExists(SObject targetRecord, String fieldApi, Object value) {
        if (targetRecord == null || value == null) {
            return;
        }
        if (fieldExists(targetRecord.getSObjectType().getDescribe().getName(), fieldApi)) {
            targetRecord.put(fieldApi, value);
        }
    }

    private static String buildRepositoryKey(GitHubRecordData requestData) {
        if (requestData == null) {
            return null;
        }
        return firstNonBlank(
            requestData.repositoryFullName,
            firstNonBlank(requestData.repositoryUrl, requestData.repositoryName)
        );
    }

    private static String buildRepositoryKey(SObject repositoryRecord, String fullNameField, String urlField) {
        String fullName = getStringValue(repositoryRecord, fullNameField);
        String url = getStringValue(repositoryRecord, urlField);
        String name = getStringValue(repositoryRecord, FIELD_NAME);
        return firstNonBlank(fullName, firstNonBlank(url, name));
    }

    private static String buildPullRequestKey(GitHubRecordData requestData) {
        if (requestData == null) {
            return null;
        }
        String repositoryKey = buildRepositoryKey(requestData);
        if (String.isBlank(repositoryKey) || requestData.pullRequestNumber == null) {
            return requestData.pullRequestUrl;
        }
        return firstNonBlank(
            requestData.pullRequestUrl,
            repositoryKey + '#' + String.valueOf(requestData.pullRequestNumber)
        );
    }

    private static String getStringValue(SObject record, String fieldApi) {
        if (record == null || String.isBlank(fieldApi)) {
            return null;
        }
        Object value = record.get(fieldApi);
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : secondValue;
    }

    private static String safeName(String input) {
        String value = String.isBlank(input) ? 'GitHub Webhook' : input.trim();
        return value.length() > 80 ? value.substring(0, 80) : value;
    }

    private static RecordResult buildResult(String status, String message) {
        RecordResult result = new RecordResult();
        result.status = status;
        result.message = message;
        return result;
    }

    /**
     * GitHub webhook data transfer object.
     */
    public class GitHubRecordData {
        public String eventName;
        public String action;
        public String deliveryId;
        public String signature;
        public String userAgent;
        public String repositoryGitHubId;
        public String repositoryName;
        public String repositoryFullName;
        public String repositoryUrl;
        public String repositoryDefaultBranch;
        public String repositoryOwner;
        public Integer pullRequestNumber;
        public String pullRequestTitle;
        public String pullRequestDescription;
        public String pullRequestUrl;
        public String pullRequestState;
        public String pullRequestAuthor;
        public String sourceBranch;
        public String sourceSha;
        public String targetBranch;
        public String targetSha;
        public String createdAt;
        public String updatedAt;
        public String closedAt;
        public String mergedAt;
        public Boolean isMerged;
        
        // ===== NEW FIELD =====
        public List<GitHubIntegrationService.GitHubChangedFile> changedFiles =
            new List<GitHubIntegrationService.GitHubChangedFile>();
    }

    /**
     * Database processing result.
     */
    public class RecordResult {
        public String status;
        public String message;
    }

    /**
     * Custom record service exception for future callers that need typed errors.
     */
    public class RecordServiceException extends Exception {
    }
}