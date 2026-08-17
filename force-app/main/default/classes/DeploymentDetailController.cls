public with sharing class DeploymentDetailController {

    public class MetadataWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String metadataType { get; set; }
        @AuraEnabled public String metadataName { get; set; }
        @AuraEnabled public String action { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    public class UserStoryWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String developer { get; set; }
        @AuraEnabled public String branchName { get; set; }
        @AuraEnabled public String gitUrl { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<MetadataWrapper> metadataList { get; set; }
        public UserStoryWrapper() {
            this.metadataList = new List<MetadataWrapper>();
        }
    }

    public class DeploymentHierarchyWrapper {
        @AuraEnabled public String deploymentId { get; set; }
        @AuraEnabled public String deploymentNumber { get; set; }
        @AuraEnabled public String deploymentName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String sourceEnvironment { get; set; }
        @AuraEnabled public String targetEnvironment { get; set; }
        @AuraEnabled public String asyncJobId { get; set; }
        @AuraEnabled public Integer totalComponents { get; set; }
        @AuraEnabled public Integer totalUserStories { get; set; }
        @AuraEnabled public List<UserStoryWrapper> userStories { get; set; }
        public DeploymentHierarchyWrapper() {
            this.userStories = new List<UserStoryWrapper>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static DeploymentHierarchyWrapper getDeploymentHierarchy(Id deploymentId) {
        System.debug(LoggingLevel.INFO, '[DeploymentDetailController.getDeploymentHierarchy] START - deploymentId: ' + deploymentId);
        if (deploymentId == null) {
            System.debug(LoggingLevel.WARN, '[DeploymentDetailController.getDeploymentHierarchy] Warning: deploymentId is null.');
            return null;
        }

        try {
            Deployment__c dep = [
                SELECT Id, Name, Deployment_Name__c, Status__c, Async_Job_Id__c,
                       Total_Components_Deployed__c, Total_User_Stories__c,
                       Source_Environment__r.Name, Source_Environment__r.Name__c,
                       Target_Environment__r.Name, Target_Environment__r.Name__c,
                       Promotion__c, User_Story__c
                FROM Deployment__c
                WHERE Id = :deploymentId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, '[DeploymentDetailController.getDeploymentHierarchy] Loaded Deployment - Number: ' + dep.Name + ' | Status: ' + dep.Status__c + ' | PromotionId: ' + dep.Promotion__c);

            DeploymentHierarchyWrapper result = new DeploymentHierarchyWrapper();
            result.deploymentId = dep.Id;
            result.deploymentNumber = dep.Name;
            result.deploymentName = dep.Deployment_Name__c;
            result.status = dep.Status__c;
        result.asyncJobId = dep.Async_Job_Id__c;
        result.sourceEnvironment = dep.Source_Environment__r != null ? (String.isNotBlank(dep.Source_Environment__r.Name__c) ? dep.Source_Environment__r.Name__c : dep.Source_Environment__r.Name) : '';
        result.targetEnvironment = dep.Target_Environment__r != null ? (String.isNotBlank(dep.Target_Environment__r.Name__c) ? dep.Target_Environment__r.Name__c : dep.Target_Environment__r.Name) : '';
        result.totalComponents = dep.Total_Components_Deployed__c != null ? Integer.valueOf(dep.Total_Components_Deployed__c) : 0;

        // Collect all related User Story IDs (via Deployment__c, Promotion__c, or direct User_Story__c lookup)
        Set<Id> storyIdsToQuery = new Set<Id>();
        if (dep.User_Story__c != null) {
            storyIdsToQuery.add(dep.User_Story__c);
        }
        if (dep.Promotion__c != null) {
            for (User_Story__c s : [SELECT Id FROM User_Story__c WHERE Promotion__c = :dep.Promotion__c]) {
                storyIdsToQuery.add(s.Id);
            }
            for (Deployment_Request__c dr : [SELECT User_Story__c FROM Deployment_Request__c WHERE Promotion__c = :dep.Promotion__c AND User_Story__c != null]) {
                storyIdsToQuery.add(dr.User_Story__c);
            }
        }
        List<User_Story__c> stories = new List<User_Story__c>();
        if (!storyIdsToQuery.isEmpty()) {
            stories = [
                SELECT Id, Name, Title__c, Owner.Name, Feature_Branch__c, View_on_Git__c, Story_Status__c,
                       Project__r.Name
                FROM User_Story__c
                WHERE Id IN :storyIdsToQuery
                ORDER BY Name ASC
            ];
        }
        result.totalUserStories = stories.size();

        Set<Id> storyIds = new Set<Id>();
        for (User_Story__c s : stories) {
            storyIds.add(s.Id);
        }

        // Query metadata items for all linked stories
        Map<Id, List<MetadataWrapper>> storyMetadataMap = new Map<Id, List<MetadataWrapper>>();
        if (!storyIds.isEmpty()) {
            List<User_Story_Metadata__c> metaList = [
                SELECT Id, User_Story__c, Metadata_API_Name__c, Metadata_Type__c, Action__c, Selected__c
                FROM User_Story_Metadata__c
                WHERE User_Story__c IN :storyIds
                ORDER BY Metadata_API_Name__c ASC
            ];
            for (User_Story_Metadata__c m : metaList) {
                if (!storyMetadataMap.containsKey(m.User_Story__c)) {
                    storyMetadataMap.put(m.User_Story__c, new List<MetadataWrapper>());
                }
                MetadataWrapper mw = new MetadataWrapper();
                mw.id = m.Id;
                mw.metadataName = m.Metadata_API_Name__c;
                mw.metadataType = m.Metadata_Type__c;
                mw.action = m.Action__c;
                mw.status = m.Selected__c == true ? 'Selected' : 'Included';
                storyMetadataMap.get(m.User_Story__c).add(mw);
            }
        }

        for (User_Story__c s : stories) {
            UserStoryWrapper sw = new UserStoryWrapper();
            sw.id = s.Id;
            sw.name = s.Name;
            sw.title = s.Title__c;
            sw.developer = s.Owner != null ? s.Owner.Name : '';
            sw.branchName = s.Feature_Branch__c;
            sw.gitUrl = s.View_on_Git__c;
            sw.status = s.Story_Status__c;
            if (storyMetadataMap.containsKey(s.Id)) {
                sw.metadataList = storyMetadataMap.get(s.Id);
            }
            result.userStories.add(sw);
        }

            System.debug(LoggingLevel.INFO, '[DeploymentDetailController.getDeploymentHierarchy] SUCCESS - Loaded ' + result.userStories.size() + ' user stories for deployment ID: ' + deploymentId);
            return result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DeploymentDetailController.getDeploymentHierarchy] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to load deployment hierarchy: ' + ex.getMessage());
        }
    }
}