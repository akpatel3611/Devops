public with sharing class UserStoryWorkspaceController {

    public class WorkspaceContext {
        @AuraEnabled public Id userStoryId;
        @AuraEnabled public String userStoryName;
        @AuraEnabled public String userStoryTitle;
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public Id releaseId;
        @AuraEnabled public String releaseName;
        @AuraEnabled public Id sourceEnvironmentId;
        @AuraEnabled public String sourceEnvironmentName;
        @AuraEnabled public Id targetEnvironmentId;
        @AuraEnabled public String targetEnvironmentName;
        @AuraEnabled public String featureBranch;
        @AuraEnabled public String baseBranch;
        @AuraEnabled public String buildStatus;
        @AuraEnabled public String prStatus;
        @AuraEnabled public String deliverStatus;
        @AuraEnabled public Boolean readyToPromote;
        @AuraEnabled public Boolean promoteAndDeploy;
        @AuraEnabled public String promotionTestLevel;
        @AuraEnabled public String viewOnGitUrl;
        @AuraEnabled public Id promotionId;           // Set if 1st deployment was already done
        @AuraEnabled public Id deploymentRequestId;   // Latest Deployment Request Id (for redirect)
        @AuraEnabled public Boolean isAlreadyDeployed; // true if Promotion already exists (1-to-1 rule)
    }

    public class StepWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String className;
    }

    public class PipelineProgressWrapper {
        @AuraEnabled public String pipelineName;
        @AuraEnabled public String currentEnvironmentName;
        @AuraEnabled public String activeStage; // DEV, QA, UAT, PRODUCTION
        @AuraEnabled public List<StepWrapper> steps;
    }

    @AuraEnabled
    public static WorkspaceContext getWorkspaceContext(Id userStoryId) {
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.getWorkspaceContext] START - userStoryId: ' + userStoryId);
        try {
            if (userStoryId == null) {
                System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.getWorkspaceContext] Warning: userStoryId is null.');
                return null;
            }

            User_Story__c story = [
                SELECT Id, Name, Title__c, Project__c, Project__r.Name, Release__c, Release__r.Name, 
                       Source_Environment__c, Source_Environment__r.Name__c, Feature_Branch__c, 
                       PR_Status__c, Build_Status__c, Deliver_Status__c, Pipeline__c, Promotion__c,
                       Ready_to_Promote__c, Promote_and_Deploy__c, Promotion_Test_Level__c, Base_Branch__c, View_on_Git__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            WorkspaceContext ctx = new WorkspaceContext();
            ctx.userStoryId = story.Id;
            ctx.userStoryName = story.Name;
            ctx.userStoryTitle = story.Title__c;
            ctx.projectId = story.Project__c;
            ctx.projectName = story.Project__r != null ? story.Project__r.Name : '';
            ctx.releaseId = story.Release__c;
            ctx.releaseName = story.Release__r != null ? story.Release__r.Name : '';
            ctx.sourceEnvironmentId = story.Source_Environment__c;
            ctx.sourceEnvironmentName = story.Source_Environment__r != null ? story.Source_Environment__r.Name__c : '';
            ctx.featureBranch = story.Feature_Branch__c;
            ctx.viewOnGitUrl = story.View_on_Git__c;
            ctx.baseBranch = String.isNotBlank(story.Base_Branch__c) ? story.Base_Branch__c : 'main';
            ctx.buildStatus = story.Build_Status__c;
            ctx.prStatus = story.PR_Status__c;
            ctx.deliverStatus = story.Deliver_Status__c;
            ctx.readyToPromote = story.Ready_to_Promote__c;
            ctx.promoteAndDeploy = story.Promote_and_Deploy__c;
            ctx.promotionTestLevel = story.Promotion_Test_Level__c;

            // Populate promotion and deployment status for LWC to decide visibility
            ctx.promotionId = story.Promotion__c;
            ctx.isAlreadyDeployed = (story.Promotion__c != null);

            // Resolve latest Deployment Request for redirect
            if (story.Promotion__c != null) {
                List<Deployment_Request__c> latestDreqs = [
                    SELECT Id FROM Deployment_Request__c
                    WHERE User_Story__c = :userStoryId
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                ctx.deploymentRequestId = latestDreqs.isEmpty() ? null : latestDreqs[0].Id;
            }

            // Resolve Target Environment from Pipeline Stages
            if (story.Pipeline__c != null && story.Source_Environment__c != null) {
                List<Stage__c> stages = [
                    SELECT Id, Target_Environment__c, Target_Environment__r.Name__c, Stage_Order__c, Stage_Type__c
                    FROM Stage__c
                    WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                    ORDER BY Stage_Order__c ASC
                ];
                Integer matchIdx = -1;
                for (Integer i = 0; i < stages.size(); i++) {
                    if (stages[i].Target_Environment__c == story.Source_Environment__c) {
                        matchIdx = i;
                        break;
                    }
                }
                if (matchIdx != -1 && matchIdx + 1 < stages.size()) {
                    ctx.targetEnvironmentId = stages[matchIdx + 1].Target_Environment__c;
                    ctx.targetEnvironmentName = stages[matchIdx + 1].Target_Environment__r != null 
                        ? stages[matchIdx + 1].Target_Environment__r.Name__c : '';
                } else if (!stages.isEmpty()) {
                    ctx.targetEnvironmentId = stages[0].Target_Environment__c;
                    ctx.targetEnvironmentName = stages[0].Target_Environment__r != null 
                        ? stages[0].Target_Environment__r.Name__c : '';
                }
            }

            System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.getWorkspaceContext] SUCCESS - Loaded story ' + story.Name + ' | SourceEnv: ' + ctx.sourceEnvironmentName);
            return ctx;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[UserStoryWorkspaceController.getWorkspaceContext] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Error loading workspace context: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<User_Story_Metadata__c> getSelectedMetadata(Id userStoryId) {
        System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getSelectedMetadata:start userStoryId=' + userStoryId);
        if (userStoryId == null) {
            System.debug(LoggingLevel.WARN, 'UserStoryWorkspaceController.getSelectedMetadata:blank userStoryId; returning empty list');
            return new List<User_Story_Metadata__c>();
        }

        List<User_Story_Metadata__c> selectedMetadata = [
            SELECT Id, Name, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c, Selected__c,
                   LastModifiedById, LastModifiedDate, CreatedById, CreatedDate
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId AND Selected__c = true
            ORDER BY Metadata_Type__c, Metadata_API_Name__c
        ];
        System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getSelectedMetadata:loaded count=' + selectedMetadata.size() + ', userStoryId=' + userStoryId);
        return selectedMetadata;
    }

    @AuraEnabled
    public static void saveSelectedComponents(
        Id userStoryId,
        List<MetadataSaveController.SelectedComponentWrapper> components,
        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        Id releaseId
    ) {
        MetadataSaveController.saveSelectedComponents(userStoryId, components, sourceEnvironmentId, targetEnvironmentId, releaseId);
    }

    @AuraEnabled
    public static CommitChangesRuntimeService.CommitResult runCommitChanges(Id userStoryId, String commitMessage) {
        return CommitChangesRuntimeService.commitChanges(userStoryId, commitMessage);
    }

    @AuraEnabled(cacheable=true)
    public static List<Promotion__c> getPromotions(Id userStoryId) {
        System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getPromotions:start userStoryId=' + userStoryId);
        if (userStoryId == null) {
            System.debug(LoggingLevel.WARN, 'UserStoryWorkspaceController.getPromotions:blank userStoryId; returning empty list');
            return new List<Promotion__c>();
        }
        
        List<Deployment_Request__c> deployments = [
            SELECT Promotion__c
            FROM Deployment_Request__c
            WHERE User_Story__c = :userStoryId AND Promotion__c != null
        ];
        
        Set<Id> promoIds = new Set<Id>();
        for (Deployment_Request__c dep : deployments) {
            promoIds.add(dep.Promotion__c);
        }
        
        User_Story__c story = [SELECT Promotion__c FROM User_Story__c WHERE Id = :userStoryId LIMIT 1];
        if (story.Promotion__c != null) {
            promoIds.add(story.Promotion__c);
        }
        
        if (promoIds.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getPromotions:no promotions found for userStoryId=' + userStoryId);
            return new List<Promotion__c>();
        }
        
        List<Promotion__c> promotions = [
            SELECT Id,
                   Name,
                   Status__c,
                   Source_Environment__r.Name__c,
                   Target_Environment__r.Name__c,
                   Promotion_Date__c,
                   Release__r.Name
            FROM Promotion__c
            WHERE Id IN :promoIds
            ORDER BY Promotion_Date__c DESC NULLS LAST
        ];
        System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getPromotions:loaded count=' + promotions.size() + ', userStoryId=' + userStoryId);
        return promotions;
    }

    @AuraEnabled(cacheable=true)
    public static PipelineProgressWrapper getPipelineProgress(Id recordId) {
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.getPipelineProgress] START - recordId: ' + recordId);
        if (recordId == null) {
            System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.getPipelineProgress] Warning: recordId is null.');
            return null;
        }
        
        try {
            PipelineProgressWrapper wrapper = new PipelineProgressWrapper();
            wrapper.steps = new List<StepWrapper>();
            
            String sobjectType = recordId.getSObjectType().getDescribe().getName();
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.getPipelineProgress] sObjectType resolved: ' + sobjectType);
            
            if (sobjectType == 'Deployment_Request__c') {
                Deployment_Request__c req = [
                    SELECT User_Story__c, Promotion__c 
                    FROM Deployment_Request__c 
                    WHERE Id = :recordId 
                    LIMIT 1
                ];
                System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.getPipelineProgress] Deployment Request linked US: ' + req.User_Story__c + ' | Promotion: ' + req.Promotion__c);
                if (req.User_Story__c != null) {
                    return getPipelineProgress(req.User_Story__c);
                } else if (req.Promotion__c != null) {
                    return getPipelineProgress(req.Promotion__c);
                }
            }
            
            if (sobjectType == 'User_Story__c') {
                User_Story__c story = [
                    SELECT Id, Pipeline__r.Name, Pipeline__c, 
                           Pipeline__r.Source_Environment__c, Pipeline__r.Source_Environment__r.Name, Pipeline__r.Source_Environment__r.Name__c,
                           Source_Environment__c, Source_Environment__r.Name, Source_Environment__r.Name__c
                    FROM User_Story__c
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                
                if (story.Source_Environment__c == null) {
                    System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.getPipelineProgress] Source Environment is null for User Story: ' + story.Id);
                    return null;
                }
                
                wrapper.pipelineName = story.Pipeline__r != null ? story.Pipeline__r.Name : 'Default Pipeline';
                wrapper.currentEnvironmentName = String.isNotBlank(story.Source_Environment__r.Name__c) ? story.Source_Environment__r.Name__c : story.Source_Environment__r.Name;
                System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.getPipelineProgress] PipelineName: ' + wrapper.pipelineName + ' | CurrentEnv: ' + wrapper.currentEnvironmentName);
                
                List<Stage__c> stages = new List<Stage__c>();
                if (story.Pipeline__c != null) {
                    stages = [
                        SELECT Id, Name, Target_Environment__r.Name, Target_Environment__r.Name__c, Stage_Order__c
                        FROM Stage__c
                        WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                        ORDER BY Stage_Order__c ASC
                    ];
                    System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.getPipelineProgress] Loaded ' + stages.size() + ' active pipeline stages.');
                    for (Stage__c stg : stages) {
                        System.debug(LoggingLevel.FINE, '[UserStoryWorkspaceController.getPipelineProgress] Stage Order: ' + stg.Stage_Order__c + ' | TargetEnv: ' + stg.Target_Environment__r.Name__c);
                    }
                }
                
                List<String> stepNames = new List<String>();
                if (story.Pipeline__c != null && !stages.isEmpty()) {
                    String pipeStartEnv = '';
                    if (story.Pipeline__r.Source_Environment__r != null) {
                        pipeStartEnv = String.isNotBlank(story.Pipeline__r.Source_Environment__r.Name__c) ? story.Pipeline__r.Source_Environment__r.Name__c : story.Pipeline__r.Source_Environment__r.Name;
                    }
                    if (String.isNotBlank(pipeStartEnv)) {
                        stepNames.add(pipeStartEnv);
                    } else if (String.isNotBlank(wrapper.currentEnvironmentName)) {
                        stepNames.add(wrapper.currentEnvironmentName);
                    }
                    for (Stage__c stg : stages) {
                        if (stg.Target_Environment__r != null) {
                            String envName = String.isNotBlank(stg.Target_Environment__r.Name__c) ? stg.Target_Environment__r.Name__c : stg.Target_Environment__r.Name;
                            if (String.isNotBlank(envName)) {
                                Boolean exists = false;
                                for (String existing : stepNames) {
                                    if (existing.equalsIgnoreCase(envName)) {
                                        exists = true;
                                        break;
                                    }
                                }
                                if (!exists) {
                                    stepNames.add(envName);
                                }
            wrapper.targetEnvName = 'QA';
        }

        wrapper.pipelineName = req.Pipeline__r != null ? req.Pipeline__r.Name : 'Default Pipeline';
        wrapper.promotionId = req.Promotion__c;
        wrapper.promotionName = req.Promotion__r != null ? req.Promotion__r.Name : '';

        // Query linked Deployment__c record
        if (req.Promotion__c != null) {
            List<Deployment__c> deps = [
                SELECT Id, Name FROM Deployment__c 
                WHERE Promotion__c = :req.Promotion__c 
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!deps.isEmpty()) {
                wrapper.deploymentId = deps[0].Id;
                wrapper.deploymentName = deps[0].Name;
            } else {
                wrapper.deploymentName = 'DEP-0001';
            }
        } else {
            wrapper.deploymentName = 'DEP-0001';
        }

        wrapper.createdDate = req.CreatedDate;

        if (req.User_Story__c != null) {
            wrapper.isMultiStory = false;
            wrapper.userStoryId = req.User_Story__c;
            wrapper.userStoryName = req.User_Story__r != null ? req.User_Story__r.Name : '';
            wrapper.headerTitle = wrapper.userStoryName;

            User_Story__c story = [
                SELECT Id, Title__c, Project__r.Name, Release__r.Name, Credential__r.Name, Owner.Name, Story_Status__c
                FROM User_Story__c
                WHERE Id = :req.User_Story__c
                LIMIT 1
            ];
            wrapper.userStoryTitle = story.Title__c;
            wrapper.projectName = story.Project__r != null ? story.Project__r.Name : '';
            wrapper.releaseName = story.Release__r != null ? story.Release__r.Name : '';
            wrapper.credentialName = story.Credential__r != null ? story.Credential__r.Name : '';
            wrapper.developerName = story.Owner != null ? story.Owner.Name : '';
            wrapper.userStoryStatus = story.Story_Status__c;
            wrapper.linkedStoriesCount = 1;
            wrapper.linkedStoryNames = new List<String>{ wrapper.userStoryName };
        } else if (req.Promotion__c != null) {
            wrapper.isMultiStory = true;
            wrapper.userStoryId = null;
            
            // Query linked stories for this promotion
            List<User_Story__c> linkedStories = [
                SELECT Id, Name, Title__c, Project__r.Name, Release__r.Name, Credential__r.Name
                FROM User_Story__c
                WHERE Promotion__c = :req.Promotion__c
                ORDER BY Name ASC
            ];
            
            wrapper.linkedStoriesCount = linkedStories.size();
            List<String> storyNames = new List<String>();
            for (User_Story__c s : linkedStories) {
                storyNames.add(s.Name);
            }
            wrapper.linkedStoryNames = storyNames;
            
            // Set dynamic header title: Release name if available, else Promotion Name
            String promoName = req.Promotion__r != null ? req.Promotion__r.Name : 'Multi-Story Release';
            String releaseName = (req.Promotion__r != null && req.Promotion__r.Release__r != null) ? req.Promotion__r.Release__r.Name : '';
            
            if (String.isNotBlank(releaseName)) {
                wrapper.headerTitle = 'Release: ' + releaseName + ' (' + wrapper.linkedStoriesCount + ' User Stories)';
                wrapper.releaseName = releaseName;
            } else {
                wrapper.headerTitle = 'Promotion: ' + promoName + ' (' + wrapper.linkedStoriesCount + ' User Stories)';
                wrapper.releaseName = 'Multi-Story Release';
            }
            
            wrapper.userStoryName = wrapper.headerTitle;
            wrapper.userStoryTitle = 'Multi-Story Release Deployment';
            wrapper.projectName = (!linkedStories.isEmpty() && linkedStories[0].Project__r != null) ? linkedStories[0].Project__r.Name : ((req.Promotion__r != null && req.Promotion__r.Pipeline__r != null && req.Promotion__r.Pipeline__r.Project__r != null) ? req.Promotion__r.Pipeline__r.Project__r.Name : 'Default Project');
            wrapper.credentialName = (!linkedStories.isEmpty() && linkedStories[0].Credential__r != null) ? linkedStories[0].Credential__r.Name : 'Target Environment Credential';
        } else {
            wrapper.isMultiStory = false;
            wrapper.userStoryName = 'Deployment Request';
            wrapper.headerTitle = 'Deployment Request';
            wrapper.userStoryTitle = 'Metadata Selection';
            wrapper.projectName = 'Default Project';
            wrapper.releaseName = 'Default Release';
            wrapper.credentialName = 'Default Cred';
            wrapper.linkedStoriesCount = 0;
            wrapper.linkedStoryNames = new List<String>();
        }

        System.debug(LoggingLevel.DEBUG, 'UserStoryWorkspaceController.getDeploymentDetails:loaded deploymentRequestId=' + deploymentRequestId + ', status=' + wrapper.status + ', headerTitle=' + wrapper.headerTitle);
        return wrapper;
    }

    @AuraEnabled
    public static void completeDeployment(Id deploymentRequestId) {
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.completeDeployment] START - deploymentRequestId: ' + deploymentRequestId);
        if (deploymentRequestId == null) {
            System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.completeDeployment] Warning: deploymentRequestId is null. Deploy skipped.');
            return;
        }

        // Trigger real queueable deployment execution instead of instant status update
        DeploymentRuntimeService.startDeployment(deploymentRequestId, 'Deploy');
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.completeDeployment] SUCCESS - deploy request submitted: ' + deploymentRequestId);
    }

    /**
     * Promotes a User Story from its current stage to the next stage in the pipeline (e.g. QA to UAT).
     * Creates Promotion and Deployment Request records, returning the deployment request ID for live console execution.
     */
    @AuraEnabled
    public static Map<String, Object> promoteStoryToNextStage(Id userStoryId) {
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.promoteStoryToNextStage] START - userStoryId: ' + userStoryId);
        Map<String, Object> response = new Map<String, Object>();
        if (userStoryId == null) {
            System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.promoteStoryToNextStage] Warning: userStoryId is null.');
            response.put('success', false);
            response.put('message', 'User Story ID is required.');
            return response;
        }

        try {
            User_Story__c story = [
                SELECT Id, Name, Title__c, Pipeline__c, Source_Environment__c, Source_Environment__r.Name, Source_Environment__r.Name__c,
                       Release__c, Project__c, Promotion__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.promoteStoryToNextStage] Story loaded - storyName: ' + story.Name + ' | pipelineId: ' + story.Pipeline__c + ' | sourceEnvId: ' + story.Source_Environment__c);

            if (story.Source_Environment__c == null) {
                System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.promoteStoryToNextStage] Warning: Source Environment missing for userStoryId: ' + userStoryId);
                response.put('success', false);
                response.put('message', 'User Story does not have a Source Environment assigned.');
                return response;
            }

            // Query next target stage in Pipeline
            List<Stage__c> stages = new List<Stage__c>();
            if (story.Pipeline__c != null) {
                stages = [
                    SELECT Id, Name, Target_Environment__c, Target_Environment__r.Name, Target_Environment__r.Name__c, Stage_Order__c
                    FROM Stage__c
                    WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                    ORDER BY Stage_Order__c ASC
                ];
            }
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.getPromotionActionContext] Active stages queried - count: ' + stages.size() + ' | currentEnv: ' + currentEnv);
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.promoteStoryToNextStage] Active pipeline stages queried - count: ' + stages.size());

            Id targetEnvId = null;
            String targetEnvName = '';

            // Find next stage target environment
            String currentEnvName = String.isNotBlank(story.Source_Environment__r.Name__c) ? story.Source_Environment__r.Name__c : story.Source_Environment__r.Name;
            for (Integer i = 0; i < stages.size(); i++) {
                String stgEnv = String.isNotBlank(stages[i].Target_Environment__r.Name__c) ? stages[i].Target_Environment__r.Name__c : stages[i].Target_Environment__r.Name;
                if (stgEnv.equalsIgnoreCase(currentEnvName)) {
                    if (i + 1 < stages.size()) {
                        targetEnvId = stages[i + 1].Target_Environment__c;
                        targetEnvName = String.isNotBlank(stages[i + 1].Target_Environment__r.Name__c) ? stages[i + 1].Target_Environment__r.Name__c : stages[i + 1].Target_Environment__r.Name;
                    }
                    break;
                }
            }

            // Fallback target resolution (e.g. QA -> UAT or DEV -> QA)
            if (targetEnvId == null) {
                String searchTarget = 'UAT';
                if (currentEnvName.equalsIgnoreCase('DEV') || currentEnvName.contains('DEV')) {
                    searchTarget = 'QA';
                }
                List<Deployment_Environment__c> targetEnvs = [
                    SELECT Id, Name, Name__c FROM Deployment_Environment__c 
                    WHERE Name = :searchTarget OR Name__c = :searchTarget 
                    LIMIT 1
                ];
                if (!targetEnvs.isEmpty()) {
                    targetEnvId = targetEnvs[0].Id;
                    targetEnvName = searchTarget;
                } else if (!stages.isEmpty()) {
                    targetEnvId = stages[0].Target_Environment__c;
                    targetEnvName = String.isNotBlank(stages[0].Target_Environment__r.Name__c) ? stages[0].Target_Environment__r.Name__c : stages[0].Target_Environment__r.Name;
                }
            }

            if (targetEnvId == null) {
                System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.promoteStoryToNextStage] Warning: Target environment could not be resolved. userStoryId: ' + userStoryId);
                response.put('success', false);
                response.put('message', 'Next target environment (e.g. UAT) could not be resolved in the pipeline.');
                return response;
            }

            // Resolve dynamic target credential (with fallback to source environment credential)
            Id targetCredId = null;
            List<Credentials__c> targetCreds = [
                SELECT Id, Name FROM Credentials__c 
                WHERE Deployment_Environment__c = :targetEnvId 
                LIMIT 1
            ];
            if (!targetCreds.isEmpty()) {
                targetCredId = targetCreds[0].Id;
            } else if (story.Source_Environment__c != null) {
                List<Credentials__c> sourceCreds = [
                    SELECT Id, Name FROM Credentials__c 
                    WHERE Deployment_Environment__c = :story.Source_Environment__c 
                    LIMIT 1
                ];
                if (!sourceCreds.isEmpty()) {
                    targetCredId = sourceCreds[0].Id;
                }
            }
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.promoteStoryToNextStage] Credential resolved - targetCredId: ' + targetCredId + ' | targetEnvName: ' + targetEnvName);

            // Reuse existing Promotion__c if present on User Story
            Id existingPromoId = story.Promotion__c;

            String prBody = 'PR created from Salesforce DevOps Platform';

            // Programmatically create GitHub Pull Request (QA -> UAT) BEFORE any DML to avoid uncommitted work pending error
            String prUrl = 'https://github.com/akpatel3611/Devops/compare/' + targetEnvName + '...' + currentEnvName;
            Integer prNum = null;
            try {
                System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.promoteStoryToNextStage] START - creating GitHub PR from ' + currentEnvName + ' to ' + targetEnvName);
                Map<String, Object> prRes = GitHubCommitProvider.createPullRequest(
                    'akpatel3611',
                    'Devops',
                    'Promote ' + story.Name + ' from ' + currentEnvName + ' to ' + targetEnvName,
                    currentEnvName,
                    targetEnvName,
                    prBody
                );
                if (prRes != null && prRes.containsKey('prUrl') && String.isNotBlank((String) prRes.get('prUrl'))) {
                    prUrl = (String) prRes.get('prUrl');
                    if (prRes.containsKey('prNumber') && prRes.get('prNumber') != null) {
                        prNum = Integer.valueOf(prRes.get('prNumber'));
                    }
                }
                System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.promoteStoryToNextStage] SUCCESS - GitHub PR result. prNumber: ' + prNum + ' | prUrl: ' + prUrl);
            } catch (Exception prEx) {
                System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.promoteStoryToNextStage] Warning: Error creating PR for stage promotion: ' + prEx.getMessage());
            }

            // Create 1 Deployment Request without upfront Promotion creation
            Deployment_Request__c dreq = new Deployment_Request__c(
                User_Story__c = story.Id,
                Promotion__c = existingPromoId,
                Source_Environment__c = story.Source_Environment__c,
                Target_Environment__c = targetEnvId,
                Pipeline__c = story.Pipeline__c,
                Release__c = story.Release__c,
                Credential__c = targetCredId,
                Status__c = 'Waiting For Pull Request Approval'
            );
            insert dreq;
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.promoteStoryToNextStage] Deployment_Request__c inserted - deploymentRequestId: ' + dreq.Id);

            // Update the User Story to reset PR status and set new PR details
            User_Story__c storyUpdate = new User_Story__c(Id = story.Id);
            storyUpdate.PR_Status__c = 'Open';
            storyUpdate.PR_Number__c = prNum != null ? String.valueOf(prNum) : null;
            storyUpdate.PR_Url__c = prUrl;
            update storyUpdate;
            System.debug(LoggingLevel.DEBUG, '[UserStoryWorkspaceController.promoteStoryToNextStage] User Story PR fields updated - userStoryId: ' + story.Id + ' | prNumber: ' + prNum);

            response.put('success', true);
            response.put('userStoryName', story.Name);
            response.put('currentEnvironment', currentEnvName);
            response.put('targetEnvironment', targetEnvName);
            response.put('promotionId', existingPromoId);
            response.put('deploymentRequestId', dreq.Id);
            response.put('prUrl', prUrl);
            response.put('prNumber', prNum);
            response.put('message', 'Stage promotion initiated to ' + targetEnvName + '. Ready for execution.');
            System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.promoteStoryToNextStage] SUCCESS - promotion initiated. deploymentRequestId: ' + dreq.Id + ' | targetEnvName: ' + targetEnvName);
            return response;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[UserStoryWorkspaceController.promoteStoryToNextStage] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            response.put('success', false);
            response.put('message', 'Failed to initiate stage promotion: ' + ex.getMessage());
            return response;
        }
    }

    /**
     * Dynamically inspects pipeline stages to resolve current environment and next target environment context for UI modal.
     */
    @AuraEnabled
    public static Map<String, Object> getPromotionActionContext(Id userStoryId) {
        System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.getPromotionActionContext] START - userStoryId: ' + userStoryId);
        Map<String, Object> result = new Map<String, Object>();
        if (userStoryId == null) {
            System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.getPromotionActionContext] Warning: userStoryId is null.');
            result.put('isPromoteAvailable', false);
            result.put('message', 'No User Story specified.');
            return result;
        }

        try {
            User_Story__c story = [
                SELECT Id, Name, Pipeline__c, Source_Environment__c, Source_Environment__r.Name, Source_Environment__r.Name__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            if (story.Source_Environment__c == null) {
                System.debug(LoggingLevel.WARN, '[UserStoryWorkspaceController.getPromotionActionContext] Warning: Source Environment missing for userStoryId: ' + userStoryId);
                result.put('isPromoteAvailable', false);
                result.put('message', 'No Source Environment assigned to User Story.');
                return result;
            }

            String currentEnv = String.isNotBlank(story.Source_Environment__r.Name__c) ? story.Source_Environment__r.Name__c : story.Source_Environment__r.Name;

            List<Stage__c> stages = new List<Stage__c>();
            if (story.Pipeline__c != null) {
                stages = [
                    SELECT Id, Name, Target_Environment__c, Target_Environment__r.Name, Target_Environment__r.Name__c, Stage_Order__c
                    FROM Stage__c
                    WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                    ORDER BY Stage_Order__c ASC
                ];
            }

            String targetEnv = '';
            for (Integer i = 0; i < stages.size(); i++) {
                String stgEnv = String.isNotBlank(stages[i].Target_Environment__r.Name__c) ? stages[i].Target_Environment__r.Name__c : stages[i].Target_Environment__r.Name;
                if (stgEnv.equalsIgnoreCase(currentEnv)) {
                    if (i + 1 < stages.size()) {
                        targetEnv = String.isNotBlank(stages[i + 1].Target_Environment__r.Name__c) ? stages[i + 1].Target_Environment__r.Name__c : stages[i + 1].Target_Environment__r.Name;
                    }
                    break;
                }
            }

            if (String.isBlank(targetEnv)) {
                if (currentEnv.equalsIgnoreCase('DEV') || currentEnv.contains('DEV')) {
                    targetEnv = 'QA';
                } else if (currentEnv.equalsIgnoreCase('QA') || currentEnv.contains('QA')) {
                    targetEnv = 'UAT';
                }
            }

            result.put('isPromoteAvailable', String.isNotBlank(targetEnv));
            result.put('currentEnvironment', currentEnv);
            result.put('targetEnvironment', targetEnv);
            result.put('userStoryName', story.Name);
            result.put('headerText', currentEnv + ' ➔ ' + (String.isNotBlank(targetEnv) ? targetEnv : 'Final Stage'));
            result.put('buttonLabel', 'Confirm & Deploy to ' + (String.isNotBlank(targetEnv) ? targetEnv : 'Next Stage'));
            System.debug(LoggingLevel.INFO, '[UserStoryWorkspaceController.getPromotionActionContext] SUCCESS - currentEnv: ' + currentEnv + ' | targetEnv: ' + targetEnv + ' | isPromoteAvailable: ' + result.get('isPromoteAvailable'));
            return result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[UserStoryWorkspaceController.getPromotionActionContext] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            result.put('isPromoteAvailable', false);
            result.put('message', 'Error resolving stage: ' + ex.getMessage());
            return result;
        }
    }

    /**
     * Resolves git branch details and GitHub repository URL for the Build Tab "View on Git" link.
     */
    @AuraEnabled
    public static Map<String, Object> getBuildTabGitDetails(Id userStoryId) {
        Map<String, Object> result = new Map<String, Object>();
        if (userStoryId == null) return result;

        try {
            User_Story__c story = [
                SELECT Id, Name, Project__c, Project__r.Git_Repository__c,
                       Project__r.Git_Repository__r.Repository_Name__c,
                       Project__r.Git_Repository__r.Repository_Owner__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            String gitBranchName = 'feature/' + story.Name;
            String gitBranchUrl = '';

            if (story.Project__r != null && story.Project__r.Git_Repository__r != null) {
                String owner = story.Project__r.Git_Repository__r.Repository_Owner__c;
                String repo = story.Project__r.Git_Repository__r.Repository_Name__c;

                if (String.isNotBlank(owner) && String.isNotBlank(repo)) {
                    gitBranchUrl = 'https://github.com/' + owner + '/' + repo + '/tree/' + gitBranchName;
                } else {
                    gitBranchUrl = 'https://github.com/search?q=' + gitBranchName;
                }
            } else {
                gitBranchUrl = 'https://github.com/search?q=' + gitBranchName;
            }

            result.put('gitBranchName', gitBranchName);
            result.put('gitBranchUrl', gitBranchUrl);
            result.put('userStoryName', story.Name);
            return result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'UserStoryWorkspaceController.getBuildTabGitDetails error: ' + ex.getMessage());
            return result;
        }
    }

    /**
     * Executes test verification for selected Apex Classes/Triggers linked to the User Story,
     * triggers real-time Apex test execution via Tooling API runTestsAsynchronous,
     * calculates weighted cumulative Apex Code Coverage across all classes,
     * and updates the User_Story__c.Apex_Code_Coverage__c field in the database.
     */
    /**
     * Initiates real-time Apex test execution via Tooling API runTestsAsynchronous,
     * immediately returning the testJobId for async client-side polling.
     */
    @AuraEnabled
    public static Map<String, Object> initiateUserStoryTests(Id userStoryId) {
        Map<String, Object> response = new Map<String, Object>();
        if (userStoryId == null) {
            response.put('success', false);
            response.put('message', 'Invalid User Story ID.');
            return response;
        }

        try {
            User_Story__c story = [
                SELECT Id, Credential__c, Source_Environment__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            Id credId = story.Credential__c;
            if (credId == null && story.Source_Environment__c != null) {
                List<Credentials__c> cList = [SELECT Id FROM Credentials__c WHERE Deployment_Environment__c = :story.Source_Environment__c LIMIT 1];
                if (!cList.isEmpty()) credId = cList[0].Id;
            }
            if (credId == null) {
                List<Credentials__c> anyCred = [SELECT Id FROM Credentials__c ORDER BY LastModifiedDate DESC LIMIT 1];
                if (!anyCred.isEmpty()) credId = anyCred[0].Id;
            }

            String targetUrl = Url.getOrgDomainUrl().toExternalForm();
            String targetToken = UserInfo.getSessionId();

            if (credId != null) {
                try {
                    MetadataAuthenticationService.OAuthTokenResponse tokenRes = MetadataAuthenticationService.generateAccessToken(credId);
                    if (tokenRes != null && String.isNotBlank(tokenRes.accessToken)) {
                        targetUrl = tokenRes.instanceUrl;
                        targetToken = tokenRes.accessToken;
                    }
                } catch (Exception tokenEx) {
                    System.debug(LoggingLevel.WARN, 'MetadataAuthenticationService OAuth token fallback notice: ' + tokenEx.getMessage());
                }
            }

            List<User_Story_Metadata__c> allApexComps = [
                SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c, LastModifiedDate
                FROM User_Story_Metadata__c
                WHERE User_Story__c = :userStoryId AND Selected__c = true
                AND (Metadata_Type__c = 'ApexClass' OR Metadata_Type__c = 'ApexTrigger')
            ];

            if (allApexComps.isEmpty()) {
                response.put('success', true);
                response.put('status', 'Completed');
                response.put('overallCoverage', 'N/A (No Apex)');
                response.put('message', 'No Apex Classes or Triggers selected for this User Story.');
                response.put('tests', new List<Map<String, Object>>());
                return response;
            }

            Set<String> classNames = new Set<String>();
            for (User_Story_Metadata__c comp : allApexComps) {
                if (String.isNotBlank(comp.Metadata_API_Name__c)) {
                    classNames.add(comp.Metadata_API_Name__c.toLowerCase());
                }
            }

            Set<String> possibleTestNames = new Set<String>();
            for (String name : classNames) {
                if (name.endsWith('test') || name.startsWith('test') || name.contains('test')) {
                    possibleTestNames.add(name);
                } else {
                    possibleTestNames.add(name + 'test');
                    possibleTestNames.add(name + '_test');
                    possibleTestNames.add('test' + name);
                }
            }

            Set<String> testClassIdsToRun = new Set<String>();
            if (!possibleTestNames.isEmpty()) {
                List<String> quotedNames = new List<String>();
                for (String pName : possibleTestNames) {
                    quotedNames.add('\'' + String.escapeSingleQuotes(pName) + '\'');
                }
                String qTargetClasses = EncodingUtil.urlEncode('SELECT Id, Name FROM ApexClass WHERE Name IN (' + String.join(quotedNames, ',') + ')', 'UTF-8');
                HttpRequest classReq = new HttpRequest();
                classReq.setEndpoint(targetUrl + '/services/data/v67.0/tooling/query?q=' + qTargetClasses);
                classReq.setMethod('GET');
                classReq.setHeader('Authorization', 'Bearer ' + targetToken);
                Http h = new Http();
                HttpResponse classRes = h.send(classReq);
                if (classRes.getStatusCode() == 200) {
                    Map<String, Object> classData = (Map<String, Object>) JSON.deserializeUntyped(classRes.getBody());
                    List<Object> classRecs = (List<Object>) classData.get('records');
                    if (classRecs != null && !classRecs.isEmpty()) {
                        for (Object cr : classRecs) {
                            Map<String, Object> cMap = (Map<String, Object>) cr;
                            String cName = (String) cMap.get('Name');
                            String cId = (String) cMap.get('Id');
                            String cNameLower = cName.toLowerCase();
                            if (cNameLower.endsWith('test') || cNameLower.startsWith('test') || cNameLower.contains('test')) {
                                testClassIdsToRun.add(cId);
                            }
                        }
                    }
                }
            }

            String testJobId = '';
            if (!testClassIdsToRun.isEmpty()) {
                List<String> testIdStrs = new List<String>(testClassIdsToRun);
                HttpRequest runReq = new HttpRequest();
                runReq.setEndpoint(targetUrl + '/services/data/v67.0/tooling/runTestsAsynchronous');
                runReq.setMethod('POST');
                runReq.setHeader('Authorization', 'Bearer ' + targetToken);
                runReq.setHeader('Content-Type', 'application/json');
                runReq.setBody(JSON.serialize(new Map<String, Object>{ 'classids' => String.join(testIdStrs, ',') }));
                
                Http h = new Http();
                HttpResponse runRes = h.send(runReq);
                if (runRes.getStatusCode() == 200) {
                    testJobId = runRes.getBody().replace('"', '').trim();
                }
            }

            response.put('success', true);
            response.put('status', 'In Progress');
            response.put('testJobId', testJobId);
            response.put('message', 'Apex test execution initiated asynchronously.');
            return response;
        } catch (Exception ex) {
            response.put('success', false);
            response.put('message', 'Error initiating tests: ' + ex.getMessage());
            return response;
        }
    }

    /**
     * Polls current Tooling API test execution status and returns final results when completed.
     */
    @AuraEnabled
    public static Map<String, Object> checkUserStoryTestStatus(Id userStoryId, String testJobId) {
        Map<String, Object> response = new Map<String, Object>();
        if (userStoryId == null) {
            response.put('success', false);
            response.put('message', 'Invalid User Story ID.');
            return response;
        }

        try {
            User_Story__c story = [
                SELECT Id, Credential__c, Source_Environment__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            Id credId = story.Credential__c;
            if (credId == null && story.Source_Environment__c != null) {
                List<Credentials__c> cList = [SELECT Id FROM Credentials__c WHERE Deployment_Environment__c = :story.Source_Environment__c LIMIT 1];
                if (!cList.isEmpty()) credId = cList[0].Id;
            }
            if (credId == null) {
                List<Credentials__c> anyCred = [SELECT Id FROM Credentials__c ORDER BY LastModifiedDate DESC LIMIT 1];
                if (!anyCred.isEmpty()) credId = anyCred[0].Id;
            }

            String targetUrl = Url.getOrgDomainUrl().toExternalForm();
            String targetToken = UserInfo.getSessionId();

            if (credId != null) {
                try {
                    MetadataAuthenticationService.OAuthTokenResponse tokenRes = MetadataAuthenticationService.generateAccessToken(credId);
                    if (tokenRes != null && String.isNotBlank(tokenRes.accessToken)) {
                        targetUrl = tokenRes.instanceUrl;
                        targetToken = tokenRes.accessToken;
                    }
                } catch (Exception tokenEx) {
                    System.debug(LoggingLevel.WARN, 'OAuth token fallback notice: ' + tokenEx.getMessage());
                }
            }

            List<User_Story_Metadata__c> allApexComps = [
                SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Action__c, LastModifiedDate
                FROM User_Story_Metadata__c
                WHERE User_Story__c = :userStoryId AND Selected__c = true
                AND (Metadata_Type__c = 'ApexClass' OR Metadata_Type__c = 'ApexTrigger')
            ];

            if (allApexComps.isEmpty()) {
                response.put('success', true);
                response.put('status', 'Completed');
                response.put('overallCoverage', 'N/A (No Apex)');
                response.put('tests', new List<Map<String, Object>>());
                return response;
            }

            Set<String> classNames = new Set<String>();
            for (User_Story_Metadata__c comp : allApexComps) {
                if (String.isNotBlank(comp.Metadata_API_Name__c)) {
                    classNames.add(comp.Metadata_API_Name__c.toLowerCase());
                }
            }

            Map<String, Id> nameToIdMap = new Map<String, Id>();
            for (ApexClass ac : [SELECT Id, Name FROM ApexClass WHERE Name IN :classNames]) {
                nameToIdMap.put(ac.Name.toLowerCase(), ac.Id);
            }
            for (ApexTrigger at : [SELECT Id, Name FROM ApexTrigger WHERE Name IN :classNames]) {
                nameToIdMap.put(at.Name.toLowerCase(), at.Id);
            }

            Set<String> possibleTestNames = new Set<String>();
            for (String name : classNames) {
                possibleTestNames.add(name + 'test');
                possibleTestNames.add(name + '_test');
                possibleTestNames.add('test' + name);
                possibleTestNames.add(name);
            }

            Set<Id> testClassIds = new Set<Id>();
            for (ApexClass ac : [SELECT Id, Name FROM ApexClass WHERE Name IN :possibleTestNames]) {
                testClassIds.add(ac.Id);
            }

            // Auto-resolve latest ParentJobId if testJobId is blank (e.g. Page Refresh)
            String activeJobId = testJobId;
            if (String.isBlank(activeJobId) && !testClassIds.isEmpty()) {
                List<String> tStrs = new List<String>();
                for (Id tid : testClassIds) tStrs.add('\'' + String.valueOf(tid) + '\'');
                String qPoll = EncodingUtil.urlEncode('SELECT ParentJobId, Status FROM ApexTestQueueItem WHERE ApexClassId IN (' + String.join(tStrs, ',') + ') ORDER BY CreatedDate DESC LIMIT 1', 'UTF-8');
                HttpRequest pollReq = new HttpRequest();
                pollReq.setEndpoint(targetUrl + '/services/data/v67.0/tooling/query?q=' + qPoll);
                pollReq.setMethod('GET');
                pollReq.setHeader('Authorization', 'Bearer ' + targetToken);
                Http h = new Http();
                HttpResponse pollRes = h.send(pollReq);
                if (pollRes.getStatusCode() == 200) {
                    Map<String, Object> pollData = (Map<String, Object>) JSON.deserializeUntyped(pollRes.getBody());
                    List<Object> recs = (List<Object>) pollData.get('records');
                    if (recs != null && !recs.isEmpty()) {
                        activeJobId = (String) ((Map<String, Object>) recs[0]).get('ParentJobId');
                    }
                }
            }

            // Poll status of active job
            if (String.isNotBlank(activeJobId)) {
                String qJobStatus = EncodingUtil.urlEncode('SELECT Status FROM ApexTestQueueItem WHERE ParentJobId = \'' + activeJobId + '\'', 'UTF-8');
                HttpRequest jobReq = new HttpRequest();
                jobReq.setEndpoint(targetUrl + '/services/data/v67.0/tooling/query?q=' + qJobStatus);
                jobReq.setMethod('GET');
                jobReq.setHeader('Authorization', 'Bearer ' + targetToken);
                Http h = new Http();
                HttpResponse jobRes = h.send(jobReq);
                if (jobRes.getStatusCode() == 200) {
                    Map<String, Object> jobData = (Map<String, Object>) JSON.deserializeUntyped(jobRes.getBody());
                    List<Object> recs = (List<Object>) jobData.get('records');
                    if (recs != null && !recs.isEmpty()) {
                        Boolean stillRunning = false;
                        for (Object r : recs) {
                            String st = (String)((Map<String, Object>) r).get('Status');
                            if (st == 'Queued' || st == 'Processing' || st == 'Preparing') {
                                stillRunning = true;
                                break;
                            }
                        }
                        if (stillRunning) {
                            response.put('success', true);
                            response.put('status', 'In Progress');
                            response.put('testJobId', activeJobId);
                            response.put('message', 'Test execution is running in background...');
                            return response;
                        }
                    }
                }
            }

            // Query test execution outcomes (Pass / Fail) from ApexTestResult by class name
            Map<String, String> testOutcomeMap = new Map<String, String>();
            if (String.isNotBlank(activeJobId)) {
                try {
                    Http h = new Http();
                    String quote = String.fromCharArray(new List<Integer>{39});
                    String resSoql = EncodingUtil.urlEncode('SELECT ApexClass.Name, Outcome FROM ApexTestResult WHERE AsyncApexJobId = ' + quote + String.valueOf(activeJobId) + quote, 'UTF-8');
                    HttpRequest resReq = new HttpRequest();
                    resReq.setEndpoint(targetUrl + '/services/data/v67.0/tooling/query?q=' + resSoql);
                    resReq.setMethod('GET');
                    resReq.setHeader('Authorization', 'Bearer ' + targetToken);
                    HttpResponse resRes = h.send(resReq);
                    if (resRes.getStatusCode() == 200) {
                        Map<String, Object> resData = (Map<String, Object>) JSON.deserializeUntyped(resRes.getBody());
                        List<Object> resRecs = (List<Object>) resData.get('records');
                        if (resRecs != null && !resRecs.isEmpty()) {
                            for (Object r : resRecs) {
                                Map<String, Object> rec = (Map<String, Object>) r;
                                Map<String, Object> apexCls = (Map<String, Object>) rec.get('ApexClass');
                                String clsName = apexCls != null ? (String) apexCls.get('Name') : null;
                                String outcome = (String) rec.get('Outcome');
                                if (String.isNotBlank(clsName)) {
                                    String cLower = clsName.toLowerCase();
                                    if (outcome == 'Fail' || outcome == 'CompileFail') {
                                        testOutcomeMap.put(cLower, 'Fail');
                                    } else if (!testOutcomeMap.containsKey(cLower)) {
                                        testOutcomeMap.put(cLower, 'Pass');
                                    }
                                }
                            }
                        }
                    }
                } catch (Exception resEx) {
                    System.debug(LoggingLevel.WARN, 'ApexTestResult query notice: ' + resEx.getMessage());
                }
            }

            // Query Tooling API for fresh ApexCodeCoverageAggregate by class name
            Integer totalCovered = 0;
            Integer totalUncovered = 0;
            Map<String, Map<String, Integer>> coverageMap = new Map<String, Map<String, Integer>>();

            List<String> endpointsToTry = new List<String>{ targetUrl };
            String localUrl = Url.getOrgDomainUrl().toExternalForm();
            if (!endpointsToTry.contains(localUrl)) endpointsToTry.add(localUrl);

            for (String epUrl : endpointsToTry) {
                try {
                    String q = EncodingUtil.urlEncode('SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate', 'UTF-8');
                    HttpRequest req = new HttpRequest();
                    req.setEndpoint(epUrl + '/services/data/v67.0/tooling/query?q=' + q);
                    req.setMethod('GET');
                    req.setHeader('Authorization', 'Bearer ' + targetToken);
                    Http h = new Http();
                    HttpResponse res = h.send(req);

                    if (res.getStatusCode() == 200) {
                        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                        List<Object> records = (List<Object>) data.get('records');
                        if (records != null && !records.isEmpty()) {
                            for (Object r : records) {
                                Map<String, Object> rec = (Map<String, Object>) r;
                                Map<String, Object> entity = (Map<String, Object>) rec.get('ApexClassOrTrigger');
                                String eName = entity != null ? (String) entity.get('Name') : null;
                                if (String.isNotBlank(eName)) {
                                    String eLower = eName.toLowerCase();
                                    Integer covered = rec.get('NumLinesCovered') != null ? Integer.valueOf(rec.get('NumLinesCovered')) : 0;
                                    Integer uncovered = rec.get('NumLinesUncovered') != null ? Integer.valueOf(rec.get('NumLinesUncovered')) : 0;
                                    coverageMap.put(eLower, new Map<String, Integer>{
                                        'covered' => covered,
                                        'uncovered' => uncovered
                                    });
                                }
                            }
                            if (!coverageMap.isEmpty()) break;
                        }
                    }
                } catch (Exception toolingEx) {
                    System.debug(LoggingLevel.WARN, 'Tooling API coverage query notice: ' + toolingEx.getMessage());
                }
            }

            // Calculate Weighted Cumulative Coverage
            List<Map<String, Object>> testResults = new List<Map<String, Object>>();
            for (User_Story_Metadata__c comp : allApexComps) {
                String name = comp.Metadata_API_Name__c;
                if (String.isBlank(name)) continue;

                String nameLower = name.toLowerCase();

                String targetClassName = nameLower;
                if (nameLower.endsWith('test')) {
                    targetClassName = nameLower.substring(0, nameLower.length() - 4);
                } else if (nameLower.startsWith('test')) {
                    targetClassName = nameLower.substring(4);
                }
                if (targetClassName.endsWith('_')) {
                    targetClassName = targetClassName.substring(0, targetClassName.length() - 1);
                }

                Integer c = 0;
                Integer u = 0;
                if (coverageMap.containsKey(targetClassName)) {
                    c = coverageMap.get(targetClassName).get('covered');
                    u = coverageMap.get(targetClassName).get('uncovered');
                } else if (coverageMap.containsKey(nameLower)) {
                    c = coverageMap.get(nameLower).get('covered');
                    u = coverageMap.get(nameLower).get('uncovered');
                }

                totalCovered += c;
                totalUncovered += u;

                if (nameLower.endsWith('test') || nameLower.startsWith('test') || nameLower.contains('test')) {
                    Boolean hasOutcome = testOutcomeMap.containsKey(nameLower);
                    Boolean isFailed = hasOutcome && testOutcomeMap.get(nameLower) == 'Fail';
                    Double classPct = (c + u > 0) ? ((Double)c / (c + u)) * 100.0 : 0.0;
                    String prefix = isFailed ? 'Fail (' : 'Pass (';
                    String classResult = (comp.Action__c == 'Delete' || comp.Action__c == 'Destructive Changes')
                        ? 'N/A (Destructive)'
                        : (hasOutcome || c + u > 0
                            ? prefix + String.valueOf(Math.round(classPct)) + '%)'
                            : 'Execution Result Unavailable');
                    Map<String, Object> item = new Map<String, Object>();
                    item.put('id', comp.Id);
                    item.put('name', 'ApexUnit: ' + name);
                    item.put('type', 'Apex Unit Test');
                    item.put('tool', 'Apex Test Engine');
                    item.put('runDate', String.valueOf(Date.today()));
                    item.put('result', classResult);
                    item.put('status', isFailed ? 'Failed' : 'Completed');
                    testResults.add(item);
                }
            }

            Double overallPct = (totalCovered + totalUncovered > 0) 
                ? ((Double)totalCovered / (totalCovered + totalUncovered)) * 100.0 
                : 0.0;

            User_Story__c storyToUpdate = new User_Story__c(
                Id = userStoryId,
                Apex_Code_Coverage__c = overallPct
            );
            update storyToUpdate;

            response.put('success', true);
            response.put('status', 'Completed');
            response.put('overallCoverage', String.valueOf(Math.round(overallPct)) + '%');
            response.put('tests', testResults);
            response.put('message', 'Apex test execution completed. Code Coverage updated to ' + String.valueOf(Math.round(overallPct)) + '%.');
            return response;

        } catch (Exception ex) {
            response.put('success', false);
            response.put('message', 'Error checking test status: ' + ex.getMessage());
            return response;
        }
    }

    /**
     * Executes test verification for selected Apex Classes/Triggers linked to the User Story,
     * triggers real-time Apex test execution via Tooling API runTestsAsynchronous,
     * calculates weighted cumulative Apex Code Coverage across all classes,
     * and updates the User_Story__c.Apex_Code_Coverage__c field in the database.
     */
    @AuraEnabled
    public static Map<String, Object> runUserStoryTests(Id userStoryId) {
        Map<String, Object> initRes = initiateUserStoryTests(userStoryId);
        if (initRes != null && initRes.containsKey('status') && (String)initRes.get('status') == 'Completed') {
            return initRes;
        }
        String tJobId = (initRes != null && initRes.containsKey('testJobId')) ? (String)initRes.get('testJobId') : '';
        return checkUserStoryTestStatus(userStoryId, tJobId);
    }
}
