/**
 * Coordinator service for handling the Commit Changes lifecycle actions on User Stories.
 * Operates strictly as a runtime state machine and boundary wrapper.
 */
public with sharing class CommitChangesRuntimeService {

    public class CommitException extends Exception {}

    // Centralized private static final constants for runtime status values
    private static final String BUILD_STATUS_IN_PROGRESS = 'In Progress';
    private static final String BUILD_STATUS_COMPLETED = 'Completed';
    private static final String BUILD_STATUS_NOT_STARTED = 'Not Started';

    private static final String PR_STATUS_PENDING_REVIEW = 'Pending Review';
    private static final String PR_STATUS_OPEN = 'Open';
    private static final String PR_STATUS_FAILED = 'Failed';

    private static final String STORY_STATUS_READY_FOR_REVIEW = 'Ready For Review';

    private static final String DEPLOYMENT_STATUS_WAITING_PR_APPROVAL = 'Waiting For Pull Request Approval';

    // DTO for returning commit operation results to clients/LWC
    public class CommitResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id userStoryId {get;set;}
        @AuraEnabled public Id deploymentRequestId {get;set;}
        @AuraEnabled public String featureBranch {get;set;}
        @AuraEnabled public String commitId {get;set;}
        @AuraEnabled public String pullRequestNumber {get;set;}
        @AuraEnabled public String pullRequestUrl {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // In-memory Runtime Context representation
    public class RuntimeContext {
        public User_Story__c userStory {get;set;}
        public Project__c project {get;set;}
        public Pipeline__c pipeline {get;set;}
        public Git_Repository__c repository {get;set;}
        public String developer {get;set;}
        public String repositoryOwner {get;set;}
        public String repositoryProvider {get;set;}
        public String defaultBranch {get;set;}
        public List<User_Story_Metadata__c> selectedMetadata {get;set;}
        public Deployment_Request__c deploymentRequest {get;set;}
        public String featureBranch {get;set;}
        public Datetime executionTimestamp {get;set;}
    }

    private static IGitCommitProvider providerInstance = null;

    @TestVisible
    public static void setProvider(IGitCommitProvider provider) {
        providerInstance = provider;
    }

    // ----------------------------------------------------
    // Public API Methods
    // ----------------------------------------------------

    /**
     * Entry point to execute the commit changes flow.
     */
    @AuraEnabled
    public static CommitResult commitChanges(Id userStoryId, String commitMessage) {
        System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.commitChanges] START - userStoryId: ' + userStoryId + ' | hasCommitMessage: ' + String.isNotBlank(commitMessage));
        if (String.isBlank(commitMessage) || String.isBlank(commitMessage.trim())) {
            System.debug(LoggingLevel.WARN, '[CommitChangesRuntimeService.commitChanges] Warning: commitMessage is blank for userStoryId: ' + userStoryId);
            return createResult(
                false,
                'Commit message cannot be null or empty.',
                userStoryId,
                null,
                null,
                null,
                null,
                null,
                null,
                new List<String>{ 'Commit message cannot be null or empty.' }
            );
        }

        try {
            // Step 1: Build Runtime Context (Loads all data via single SOQL step to avoid duplicates)
            RuntimeContext context = buildRuntimeContext(userStoryId);
            System.debug(LoggingLevel.DEBUG, '[CommitChangesRuntimeService.commitChanges] Runtime context built - deploymentRequestId: ' + (context.deploymentRequest == null ? null : context.deploymentRequest.Id) + ' | selectedMetadataCount: ' + (context.selectedMetadata == null ? 0 : context.selectedMetadata.size()));

            // Step 2: Perform validations on pre-built context
            CommitResult valResult = validateCommitRequest(context);
            if (!valResult.success) {
                System.debug(LoggingLevel.WARN, '[CommitChangesRuntimeService.commitChanges] Warning: validation failed for userStoryId: ' + userStoryId + ' | errors: ' + valResult.errors);
                return valResult;
            }

            // Step 3: Generate Feature Branch Name using stable immutable identifier
            String identifier = String.isNotBlank(context.userStory.Story_Number__c) 
                ? context.userStory.Story_Number__c 
                : context.userStory.Id;
            String branchName = 'feature/' + identifier;
            context.featureBranch = branchName;

            // Step 4: Invoke Provider implementation to execute real Git branch creation & Pull Request opening!
            GitCommitResult provRes = invokeCommitProvider(context, commitMessage);
            if (!provRes.success) {
                String errMsg = (provRes.errors != null && !provRes.errors.isEmpty()) ? provRes.errors[0] : 'Git Commit provider execution failed.';
                System.debug(LoggingLevel.ERROR, '[CommitChangesRuntimeService.commitChanges] Git provider failed - userStoryId: ' + userStoryId + ' | error: ' + errMsg);
                updateRuntimeStatus(userStoryId, BUILD_STATUS_NOT_STARTED, PR_STATUS_FAILED, null, null);
                return createResult(false, errMsg, userStoryId, null, null, null, null, null, PR_STATUS_FAILED, provRes.errors);
            }
            System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.commitChanges] Git provider success - branchName: ' + branchName + ' | prNumber: ' + provRes.pullRequestNumber + ' | prUrl: ' + provRes.pullRequestUrl);

            // Save PR Number and PR URL onto User Story
            User_Story__c storyUpdate = new User_Story__c(Id = userStoryId);
            storyUpdate.Build_Status__c = BUILD_STATUS_COMPLETED;
            storyUpdate.PR_Status__c = PR_STATUS_OPEN;
            storyUpdate.Feature_Branch__c = branchName;
            storyUpdate.PR_Number__c = provRes.pullRequestNumber;
            storyUpdate.PR_Url__c = provRes.pullRequestUrl;
            storyUpdate.Commit_Time__c = System.now();
            update storyUpdate;

            Deployment_Request__c dreq = context.deploymentRequest;
            dreq.Status__c = DEPLOYMENT_STATUS_WAITING_PR_APPROVAL;
            dreq.Remarks__c = commitMessage; 
            update dreq;
            System.debug(LoggingLevel.DEBUG, '[CommitChangesRuntimeService.commitChanges] DML updates completed - userStoryId: ' + userStoryId + ' | deploymentRequestId: ' + dreq.Id);

            System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.commitChanges] SUCCESS - userStoryId: ' + userStoryId + ' | deploymentRequestId: ' + dreq.Id);
            return createResult(
                true,
                'Commit changes process completed successfully. Branch & Pull Request created!',
                userStoryId,
                dreq.Id,
                branchName,
                provRes.commitId,
                provRes.pullRequestNumber,
                provRes.pullRequestUrl,
                PR_STATUS_OPEN,
                new List<String>()
            );

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[CommitChangesRuntimeService.commitChanges] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            List<String> errs = new List<String>{ ex.getMessage() };
            return createResult(false, 'Exception occurred during commit: ' + ex.getMessage(), userStoryId, null, null, null, null, null, null, errs);
        }
    }

    /**
     * Preview the expanded Git payload and file tree for a User Story before committing.
     */
    @AuraEnabled
    public static List<GitMetadataItem> getPayloadPreview(Id userStoryId) {
        System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.getPayloadPreview] START - userStoryId: ' + userStoryId);
        try {
            RuntimeContext context = buildRuntimeContext(userStoryId);
            List<User_Story_Metadata__c> metaList = context.selectedMetadata;
            System.debug(LoggingLevel.DEBUG, '[CommitChangesRuntimeService.getPayloadPreview] Runtime metadata loaded - count: ' + (metaList == null ? 0 : metaList.size()));
            if (metaList == null || metaList.isEmpty()) {
                metaList = [
                    SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c
                    FROM User_Story_Metadata__c
                    WHERE User_Story__c = :userStoryId
                    ORDER BY Metadata_Type__c ASC, Metadata_API_Name__c ASC
                ];
                System.debug(LoggingLevel.DEBUG, '[CommitChangesRuntimeService.getPayloadPreview] Fallback metadata query completed - count: ' + metaList.size());
            }

            if (metaList.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[CommitChangesRuntimeService.getPayloadPreview] Warning: no metadata selected for userStoryId: ' + userStoryId);
                return new List<GitMetadataItem>();
            }

            List<GitMetadataItem> items = new List<GitMetadataItem>();
            for (User_Story_Metadata__c m : metaList) {
                GitMetadataItem item = new GitMetadataItem();
                item.metadataType = m.Metadata_Type__c;
                item.apiName = m.Metadata_API_Name__c;
                item.filePath = m.File_Path__c;
                item.deploymentAction = String.isNotBlank(m.Action__c) ? m.Action__c : 'Add';
                items.add(item);
            }

            Id sourceCredId = (context.deploymentRequest != null && context.deploymentRequest.Credential__c != null)
                ? context.deploymentRequest.Credential__c
                : (context.userStory != null ? context.userStory.Credential__c : null);

            String sourceUrl = null;
            String sourceToken = null;
            if (sourceCredId != null) {
                try {
                    MetadataAuthenticationService.OAuthTokenResponse srcTok =
                        MetadataAuthenticationService.generateAccessToken(sourceCredId);
                    if (srcTok != null && String.isNotBlank(srcTok.accessToken) && String.isNotBlank(srcTok.instanceUrl)) {
                        sourceToken = srcTok.accessToken;
                        sourceUrl = srcTok.instanceUrl;
                    }
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'getPayloadPreview auth error: ' + ex.getMessage());
                }
            }

            List<GitMetadataItem> previewItems = GitHubCommitProvider.previewPayload(items, sourceUrl, sourceToken);
            System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.getPayloadPreview] SUCCESS - userStoryId: ' + userStoryId + ' | previewItemCount: ' + previewItems.size());
            return previewItems;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[CommitChangesRuntimeService.getPayloadPreview] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            return new List<GitMetadataItem>();
        }
    }

    /**
     * Executes check-only validation against target org prior to Git commit.
     */
    @AuraEnabled
    public static Map<String, Object> validatePreCommit(Id userStoryId) {
        System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.validatePreCommit] START - userStoryId: ' + userStoryId);
        Map<String, Object> res = new Map<String, Object>();
        try {
            List<Deployment_Request__c> reqs = [
                SELECT Id, Status__c, Target_Environment__c, Source_Environment__c
                FROM Deployment_Request__c
                WHERE User_Story__c = :userStoryId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, '[CommitChangesRuntimeService.validatePreCommit] Deployment request query completed - count: ' + reqs.size());

            if (reqs.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[CommitChangesRuntimeService.validatePreCommit] Warning: no deployment request found for userStoryId: ' + userStoryId);
                res.put('success', false);
                res.put('message', 'No draft deployment request record found for this User Story. Please select metadata components first.');
                return res;
            }

            Id reqId = reqs[0].Id;
            DeploymentRuntimeService.startDeployment(reqId, 'Validate');

            res.put('success', true);
            res.put('requestId', reqId);
            res.put('message', 'Validation started successfully.');
            System.debug(LoggingLevel.INFO, '[CommitChangesRuntimeService.validatePreCommit] SUCCESS - validation started. userStoryId: ' + userStoryId + ' | requestId: ' + reqId);
            return res;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[CommitChangesRuntimeService.validatePreCommit] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            res.put('success', false);
            res.put('message', ex.getMessage());
            return res;
        }
    }

    /**
     * Executes the actual GitHub branch creation, file commit, and Pull Request creation post successful deployment.
     */
    public static void executePostDeploymentGitCommit(Id userStoryId, Id requestId, String commitMessage) {
        try {
            RuntimeContext context = buildRuntimeContext(userStoryId);
            String identifier = String.isNotBlank(context.userStory.Story_Number__c) 
                ? context.userStory.Story_Number__c 
                : context.userStory.Id;
            String branchName = 'feature/' + identifier;
            context.featureBranch = branchName;

            GitCommitResult provRes = invokeCommitProvider(context, commitMessage);
            if (provRes.success) {
                // Update User Story with final Git information
                updateRuntimeStatus(userStoryId, BUILD_STATUS_COMPLETED, PR_STATUS_OPEN, branchName, STORY_STATUS_READY_FOR_REVIEW);

                Deployment_Request__c dreq = new Deployment_Request__c(
                    Id = requestId,
                    Remarks__c = 'Git sync completed successfully. PR: ' + provRes.pullRequestUrl
                );
                update dreq;
            } else {
                String errMsg = provRes.errors != null && !provRes.errors.isEmpty() ? provRes.errors[0] : 'Git provider failed.';
                Deployment_Request__c dreq = new Deployment_Request__c(
                    Id = requestId,
                    Remarks__c = 'Git post-deployment sync failed: ' + errMsg
                );
                update dreq;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'executePostDeploymentGitCommit exception: ' + ex.getMessage());
        }
    }

    /**
     * Executes business and schema preconditions check with outer userStoryId.
     */
    public static CommitResult validateCommitRequest(Id userStoryId) {
        try {
            RuntimeContext context = buildRuntimeContext(userStoryId);
            return validateCommitRequest(context);
        } catch (Exception ex) {
            List<String> errs = new List<String>{ ex.getMessage() };
            return createResult(false, 'Validation failed: ' + ex.getMessage(), userStoryId, null, null, null, null, null, null, errs);
        }
    }

    /**
     * Callback method to mark commit changes transaction as completed.
     */
    public static CommitResult markCommitCompleted(Id userStoryId, String pullRequestNumber, String pullRequestUrl) {
        try {
            updateRuntimeStatus(userStoryId, BUILD_STATUS_COMPLETED, PR_STATUS_OPEN, null, STORY_STATUS_READY_FOR_REVIEW);
            return createResult(true, 'Commit marked as completed.', userStoryId, null, null, null, pullRequestNumber, pullRequestUrl, BUILD_STATUS_COMPLETED, new List<String>());
        } catch (Exception ex) {
            return createResult(false, 'Failed to complete commit: ' + ex.getMessage(), userStoryId, null, null, null, null, null, null, new List<String>{ ex.getMessage() });
        }
    }

    /**
     * Callback method to mark commit changes transaction as failed.
     */
    public static CommitResult markCommitFailed(Id userStoryId, String errorMessage) {
        try {
            updateRuntimeStatus(userStoryId, BUILD_STATUS_NOT_STARTED, PR_STATUS_FAILED, null, null);
            return createResult(true, 'Commit marked as failed.', userStoryId, null, null, null, null, null, BUILD_STATUS_NOT_STARTED, new List<String>{ errorMessage });
        } catch (Exception ex) {
            return createResult(false, 'Failed to mark commit as failed: ' + ex.getMessage(), userStoryId, null, null, null, null, null, null, new List<String>{ ex.getMessage() });
        }
    }

    /**
     * Reverts the commit status of the user story back to default.
     */
    public static CommitResult cancelCommit(Id userStoryId) {
        try {
            updateRuntimeStatus(userStoryId, BUILD_STATUS_NOT_STARTED, null, null, null);
            return createResult(true, 'Commit status cancelled successfully.', userStoryId, null, null, null, null, null, BUILD_STATUS_NOT_STARTED, new List<String>());
        } catch (Exception ex) {
            return createResult(false, 'Failed to cancel commit: ' + ex.getMessage(), userStoryId, null, null, null, null, null, null, new List<String>{ ex.getMessage() });
        }
    }

    // ----------------------------------------------------
    // Private Validation & Helper Methods (SOQL Free)
    // ----------------------------------------------------

    /**
     * Validates context properties in memory.
     */
    private static CommitResult validateCommitRequest(RuntimeContext context) {
        List<String> errors = new List<String>();
        Id dreqId = context.deploymentRequest != null ? context.deploymentRequest.Id : null;
        Id userStoryId = context.userStory != null ? context.userStory.Id : null;

        validateUserStory(context.userStory, errors);
        
        if (context.userStory != null) {
            validateProject(context.userStory.Project__c, errors);
            validatePipeline(context.userStory.Pipeline__c, errors);
            validateRepository(context.repository, context.defaultBranch, context.repositoryOwner, context.repositoryProvider, errors);
            validateSourceEnvironment(context.userStory.Source_Environment__r, errors);
            validateMetadataSelection(context.selectedMetadata, errors);
            validateDeploymentRequest(context.deploymentRequest, userStoryId, errors);
            
            if (context.userStory.Story_Status__c != 'New' && context.userStory.Story_Status__c != 'In Progress') {
                errors.add('Invalid User Story status for commit. Current Status: ' + context.userStory.Story_Status__c);
            }
            if (context.userStory.Build_Status__c == BUILD_STATUS_IN_PROGRESS) {
                errors.add('A commit process is already in progress for this User Story.');
            }
        }

        if (String.isBlank(context.developer)) {
            errors.add('Developer context is not available.');
        }

        if (!errors.isEmpty()) {
            return createResult(false, 'Validation failed.', userStoryId, dreqId, null, null, null, null, null, errors);
        }

        return createResult(true, 'Validation passed.', userStoryId, dreqId, null, null, null, null, null, new List<String>());
    }

    private static void validateUserStory(User_Story__c story, List<String> errors) {
        if (story == null) {
            errors.add('User Story record is missing.');
        }
    }

    private static void validateProject(Id projectId, List<String> errors) {
        if (projectId == null) {
            errors.add('Project is not configured on the User Story.');
        }
    }

    private static void validatePipeline(Id pipelineId, List<String> errors) {
        if (pipelineId == null) {
            errors.add('Pipeline is not configured on the User Story.');
        }
    }

    private static void validateRepository(Git_Repository__c repo, String defaultBranch, String repositoryOwner, String repositoryProvider, List<String> errors) {
        if (repo == null) {
            errors.add('Git Repository is not configured on the Project.');
        } else {
            if (repo.Status__c != 'Active') {
                errors.add('Repository is not active.');
            }
            if (String.isBlank(defaultBranch)) {
                errors.add('Default Branch configuration is missing on the Repository.');
            }
            if (String.isBlank(repositoryOwner)) {
                errors.add('Repository Owner configuration is missing on the Repository.');
            }
            if (String.isBlank(repositoryProvider)) {
                errors.add('Git Provider type configuration is missing on the Repository.');
            }
            if (String.isBlank(repo.GitHub_URL__c)) {
                errors.add('Repository URL (GitHub_URL__c) configuration is missing on the Repository.');
            }
        }
    }

    private static void validateSourceEnvironment(Deployment_Environment__c env, List<String> errors) {
        if (env == null) {
            errors.add('Source Environment is not configured on the User Story.');
        } else {
            if (env.Status__c != 'Active') {
                errors.add('Source Environment is not active.');
            }
            if (env.Is_Source_Enabled__c != true) {
                errors.add('Source Environment is not enabled as a metadata source.');
            }
        }
    }

    private static void validateDeploymentRequest(Deployment_Request__c dreq, Id userStoryId, List<String> errors) {
        if (dreq == null) {
            errors.add('Deployment Request missing on the User Story.');
        } else {
            if (dreq.User_Story__c != userStoryId) {
                errors.add('Deployment Request does not belong to the current User Story.');
            }
            if (dreq.Status__c != 'Draft' && dreq.Status__c != 'Pending' && dreq.Status__c != 'Validated') {
                errors.add('Deployment Request is in an invalid state for commit. Current Status: ' + dreq.Status__c);
            }
        }
    }

    private static void validateMetadataSelection(List<User_Story_Metadata__c> selectedMeta, List<String> errors) {
        if (selectedMeta == null || selectedMeta.isEmpty()) {
            errors.add('No metadata components selected for commit.');
        }
    }

    private static RuntimeContext buildRuntimeContext(Id userStoryId) {
        if (userStoryId == null) {
            throw new CommitException('User Story ID cannot be null.');
        }

        List<User_Story__c> stories = [
            SELECT Id, Name, Title__c, Story_Status__c, Project__c, Pipeline__c, Source_Environment__c, Build_Status__c, Story_Number__c,
                   Release__c, Promotion__c, Credential__c,
                   Source_Environment__r.Name, Source_Environment__r.Status__c, Source_Environment__r.Is_Source_Enabled__c,
                   Project__r.Git_Repository__c, Project__r.Git_Repository__r.Status__c,
                   Project__r.Git_Repository__r.Repository_Name__c, Project__r.Git_Repository__r.GitHub_URL__c,
                   Project__r.Git_Repository__r.Default_Branch__c, Project__r.Git_Repository__r.Repository_Owner__c,
                   Project__r.Git_Repository__r.Git_Provider__c,
                   Pipeline__r.Pipeline_Status__c
            FROM User_Story__c
            WHERE Id = :userStoryId
            LIMIT 1
        ];

        if (stories.isEmpty()) {
            throw new CommitException('User Story record not found.');
        }

        User_Story__c story = stories[0];
        Project__c proj = story.Project__r;
        Pipeline__c pipe = story.Pipeline__r;
        Git_Repository__c repo = (proj != null) ? proj.Git_Repository__r : null;

        List<Deployment_Request__c> requests = [
            SELECT Id, Status__c, User_Story__c, Target_Environment__c, Source_Environment__c, Pipeline__c, Release__c, Credential__c
            FROM Deployment_Request__c
            WHERE User_Story__c = :userStoryId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        List<User_Story_Metadata__c> selectedMeta = MetadataInventoryService.returnSelectedMetadata(userStoryId);

        RuntimeContext context = new RuntimeContext();
        context.userStory = story;
        context.project = proj;
        context.pipeline = pipe;
        context.repository = repo;
        context.developer = UserInfo.getUserName();
        context.repositoryOwner = repo != null ? repo.Repository_Owner__c : null;
        context.repositoryProvider = repo != null ? repo.Git_Provider__c : null;
        context.defaultBranch = repo != null ? repo.Default_Branch__c : null;
        context.selectedMetadata = selectedMeta;
        context.deploymentRequest = requests.isEmpty() ? null : requests[0];
        context.executionTimestamp = System.now();
        return context;
    }

    private static GitCommitResult invokeCommitProvider(RuntimeContext context, String commitMessage) {
        if (providerInstance == null && context.repositoryProvider == 'GitHub') {
            providerInstance = new GitHubCommitProvider();
        }
        if (providerInstance != null) {
            GitCommitContext providerContext = new GitCommitContext();
            providerContext.repositoryName = context.repository != null ? context.repository.Repository_Name__c : null;
            providerContext.repositoryOwner = context.repositoryOwner;
            providerContext.repositoryUrl = context.repository != null ? context.repository.GitHub_URL__c : null;
            providerContext.defaultBranch = context.defaultBranch;
            providerContext.providerType = context.repositoryProvider;
            providerContext.developerUsername = context.developer;
            providerContext.featureBranchName = context.featureBranch;
            providerContext.executionTimestamp = context.executionTimestamp;
            providerContext.sourceCredentialId = (context.deploymentRequest != null && context.deploymentRequest.Credential__c != null)
                ? context.deploymentRequest.Credential__c
                : (context.userStory != null ? context.userStory.Credential__c : null);

            List<GitMetadataItem> items = new List<GitMetadataItem>();
            if (context.selectedMetadata != null) {
                for (User_Story_Metadata__c m : context.selectedMetadata) {
                    GitMetadataItem item = new GitMetadataItem();
                    item.metadataType = m.Metadata_Type__c;
                    item.apiName = m.Metadata_API_Name__c;
                    item.filePath = m.File_Path__c;
                    item.deploymentAction = m.Action__c;
                    items.add(item);
                }
            }
            providerContext.selectedMetadata = items;

            return providerInstance.executeCommit(providerContext, commitMessage);
        }

        // Proper configuration error if no provider implementation is configured
        GitCommitResult failedRes = new GitCommitResult();
        failedRes.success = false;
        failedRes.errors = new List<String>{ 'Git Provider not configured.' };
        return failedRes;
    }

    private static void updateRuntimeStatus(Id userStoryId, String buildStatus, String prStatus, String featureBranchName, String storyStatus) {
        User_Story__c story = new User_Story__c(Id = userStoryId);
        story.Build_Status__c = buildStatus;
        story.PR_Status__c = prStatus;
        if (storyStatus != null) {
            story.Story_Status__c = storyStatus;
        }
        // Clear branch on default/revert, keep branch on success/completed
        if (featureBranchName != null || buildStatus == BUILD_STATUS_NOT_STARTED) {
            story.Feature_Branch__c = featureBranchName;
        }
        if (buildStatus == BUILD_STATUS_IN_PROGRESS) {
            story.Commit_Time__c = System.now();
        }
        update story;
    }

    private static CommitResult createResult(
        Boolean success,
        String message,
        Id userStoryId,
        Id deploymentRequestId,
        String featureBranch,
        String commitId,
        String pullRequestNumber,
        String pullRequestUrl,
        String status,
        List<String> errors
    ) {
        CommitResult res = new CommitResult();
        res.success = success;
        res.message = message;
        res.userStoryId = userStoryId;
        res.deploymentRequestId = deploymentRequestId;
        res.featureBranch = featureBranch;
        res.commitId = commitId;
        res.pullRequestNumber = pullRequestNumber;
        res.pullRequestUrl = pullRequestUrl;
        res.status = status;
        res.errors = errors != null ? errors : new List<String>();
        return res;
    }
}
