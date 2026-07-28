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
    }

    public class PipelineProgressWrapper {
        @AuraEnabled public String pipelineName;
        @AuraEnabled public String currentEnvironmentName;
        @AuraEnabled public String activeStage; // DEV, QA, UAT, PRODUCTION
    }

    @AuraEnabled(cacheable=true)
    public static WorkspaceContext getWorkspaceContext(Id userStoryId) {
        if (userStoryId == null) {
            return null;
        }

        User_Story__c story = [
            SELECT Id, Name, Title__c, Project__c, Project__r.Name, Release__c, Release__r.Name, 
                   Source_Environment__c, Source_Environment__r.Name__c, Feature_Branch__c, 
                   PR_Status__c, Build_Status__c, Deliver_Status__c, Pipeline__c,
                   Ready_to_Promote__c, Promote_and_Deploy__c, Promotion_Test_Level__c, Base_Branch__c
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
        ctx.baseBranch = String.isNotBlank(story.Base_Branch__c) ? story.Base_Branch__c : 'main';
        ctx.buildStatus = story.Build_Status__c;
        ctx.prStatus = story.PR_Status__c;
        ctx.deliverStatus = story.Deliver_Status__c;
        ctx.readyToPromote = story.Ready_to_Promote__c;
        ctx.promoteAndDeploy = story.Promote_and_Deploy__c;
        ctx.promotionTestLevel = story.Promotion_Test_Level__c;

        // Resolve Target Environment from Pipeline Stages
        if (story.Pipeline__c != null && story.Source_Environment__c != null) {
            List<Stage__c> stages = [
                SELECT Id, Target_Environment__c, Target_Environment__r.Name__c, Stage_Order__c, Stage_Type__c
                FROM Stage__c
                WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                ORDER BY Stage_Order__c ASC
            ];
            
            if (!stages.isEmpty()) {
                Id targetId = null;
                String targetName = '';
                Integer matchingIndex = -1;
                
                for (Integer i = 0; i < stages.size(); i++) {
                    if (stages[i].Target_Environment__c == story.Source_Environment__c) {
                        matchingIndex = i;
                        break;
                    }
                }
                
                if (matchingIndex != -1 && matchingIndex + 1 < stages.size()) {
                    targetId = stages[matchingIndex + 1].Target_Environment__c;
                    targetName = stages[matchingIndex + 1].Target_Environment__r.Name__c;
                } else if (matchingIndex == -1) {
                    targetId = stages[0].Target_Environment__c;
                    targetName = stages[0].Target_Environment__r.Name__c;
                }
                
                ctx.targetEnvironmentId = targetId;
                ctx.targetEnvironmentName = targetName;
            }
        }

        return ctx;
    }

    @AuraEnabled
    public static List<User_Story_Metadata__c> getSelectedMetadata(Id userStoryId) {
        if (userStoryId == null) {
            return new List<User_Story_Metadata__c>();
        }
        return [
            SELECT Id, Name, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c, Selected__c, LastModifiedDate
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId AND Selected__c = true
            ORDER BY Metadata_Type__c, Metadata_API_Name__c
        ];
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

    @AuraEnabled
    public static List<Promotion__c> getPromotions(Id userStoryId) {
        if (userStoryId == null) {
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
            return new List<Promotion__c>();
        }
        
        return [
            SELECT Id, Name, Status__c, Source_Environment__r.Name__c, Target_Environment__r.Name__c, Promotion_Date__c
            FROM Promotion__c
            WHERE Id IN :promoIds
            ORDER BY Promotion_Date__c DESC NULLS LAST
        ];
    }

    @AuraEnabled(cacheable=true)
    public static PipelineProgressWrapper getPipelineProgress(Id recordId) {
        if (recordId == null) {
            return null;
        }
        
        PipelineProgressWrapper wrapper = new PipelineProgressWrapper();
        String sobjectType = recordId.getSObjectType().getDescribe().getName();
        
        if (sobjectType == 'User_Story__c') {
            User_Story__c story = [
                SELECT Id, Pipeline__r.Name, Source_Environment__r.Name__c
                FROM User_Story__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            wrapper.pipelineName = story.Pipeline__r != null ? story.Pipeline__r.Name : 'Default Pipeline';
            wrapper.currentEnvironmentName = story.Source_Environment__r != null ? story.Source_Environment__r.Name__c : 'DEV';
        } else if (sobjectType == 'Promotion__c') {
            Promotion__c promo = [
                SELECT Id, Pipeline__r.Name, Source_Environment__r.Name__c, Target_Environment__r.Name__c
                FROM Promotion__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            wrapper.pipelineName = promo.Pipeline__r != null ? promo.Pipeline__r.Name : 'Default Pipeline';
            wrapper.currentEnvironmentName = promo.Target_Environment__r != null ? promo.Target_Environment__r.Name__c : (promo.Source_Environment__r != null ? promo.Source_Environment__r.Name__c : 'INT');
        }
        
        String envName = wrapper.currentEnvironmentName != null ? wrapper.currentEnvironmentName.toUpperCase() : 'DEV';
        if (envName.contains('QA') || envName.contains('INT')) {
            wrapper.activeStage = 'QA';
        } else if (envName.contains('UAT')) {
            wrapper.activeStage = 'UAT';
        } else if (envName.contains('PROD') || envName.contains('MAIN') || envName.contains('PRODUCTION')) {
            wrapper.activeStage = 'PRODUCTION';
        } else {
            wrapper.activeStage = 'DEV';
        }
        
        return wrapper;
    }

    public class DeploymentDetailsWrapper {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String sourceEnvName;
        @AuraEnabled public String targetEnvName;
        @AuraEnabled public String pipelineName;
        @AuraEnabled public Id promotionId;
        @AuraEnabled public String promotionName;
        @AuraEnabled public Id userStoryId;
        @AuraEnabled public String userStoryName;
        @AuraEnabled public String userStoryTitle;
        @AuraEnabled public String projectName;
        @AuraEnabled public String releaseName;
        @AuraEnabled public String credentialName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String userStoryStatus;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static DeploymentDetailsWrapper getDeploymentDetails(Id deploymentRequestId) {
        if (deploymentRequestId == null) {
            return null;
        }

        Deployment_Request__c req = [
            SELECT Id, Name, Status__c, Source_Environment__r.Name__c, Target_Environment__r.Name__c, 
                   Pipeline__r.Name, Promotion__r.Name, Promotion__c, User_Story__c, User_Story__r.Name, CreatedDate
            FROM Deployment_Request__c
            WHERE Id = :deploymentRequestId
            LIMIT 1
        ];

        DeploymentDetailsWrapper wrapper = new DeploymentDetailsWrapper();
        wrapper.recordId = req.Id;
        wrapper.name = req.Name;
        wrapper.status = req.Status__c;
        wrapper.sourceEnvName = req.Source_Environment__r != null ? req.Source_Environment__r.Name__c : 'DEV';
        wrapper.targetEnvName = req.Target_Environment__r != null ? req.Target_Environment__r.Name__c : 'QA';
        wrapper.pipelineName = req.Pipeline__r != null ? req.Pipeline__r.Name : 'Default Pipeline';
        wrapper.promotionId = req.Promotion__c;
        wrapper.promotionName = req.Promotion__r != null ? req.Promotion__r.Name : '';
        wrapper.userStoryId = req.User_Story__c;
        wrapper.userStoryName = req.User_Story__r != null ? req.User_Story__r.Name : '';
        wrapper.createdDate = req.CreatedDate;

        if (req.User_Story__c != null) {
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
        }

        return wrapper;
    }

    @AuraEnabled
    public static void completeDeployment(Id deploymentRequestId) {
        if (deploymentRequestId == null) return;

        Deployment_Request__c req = [
            SELECT Id, User_Story__c, Source_Environment__c, Target_Environment__c 
            FROM Deployment_Request__c 
            WHERE Id = :deploymentRequestId 
            LIMIT 1
        ];

        req.Status__c = 'Completed';
        update req;

        if (req.User_Story__c != null) {
            User_Story__c story = new User_Story__c(
                Id = req.User_Story__c,
                Source_Environment__c = req.Target_Environment__c,
                Build_Status__c = 'Completed',
                PR_Status__c = 'Merged',
                Deliver_Status__c = 'Promoted'
            );
            update story;
        }
    }
}