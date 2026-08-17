public with sharing class MetadataSaveController {

    public class SelectedComponentWrapper {
        @AuraEnabled public String label {get;set;}
        @AuraEnabled public String value {get;set;}
        @AuraEnabled public String type {get;set;}
        @AuraEnabled public String action {get;set;}
    }

    @AuraEnabled
    public static void saveSelectedComponents(
        Id userStoryId,
        List<SelectedComponentWrapper> components,
        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        Id releaseId
    ){
        System.debug(LoggingLevel.INFO, '[MetadataSaveController.saveSelectedComponents] START - userStoryId: ' + userStoryId + ' | componentsCount: ' + (components != null ? components.size() : 0));
        try {
            if(userStoryId == null){
                System.debug(LoggingLevel.ERROR, '[MetadataSaveController.saveSelectedComponents] Error: User Story ID is null.');
                throw new AuraHandledException('User Story is required');
            }

            if(components == null || components.isEmpty()){
                System.debug(LoggingLevel.ERROR, '[MetadataSaveController.saveSelectedComponents] Error: Components list is null or empty.');
                throw new AuraHandledException('No metadata selected');
            }

            // Fetch User Story to update Source Environment
            User_Story__c story = [
                SELECT Id, Pipeline__c, Source_Environment__c, Build_Status__c, PR_Status__c 
                FROM User_Story__c 
                WHERE Id = :userStoryId 
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, '[MetadataSaveController.saveSelectedComponents] Loaded User Story: ' + story.Id + ' | SourceEnv: ' + story.Source_Environment__c);
        
        Boolean needStoryUpdate = false;
        if (story.Source_Environment__c != sourceEnvironmentId) {
            story.Source_Environment__c = sourceEnvironmentId;
            needStoryUpdate = true;
        }
        if (story.Build_Status__c == 'In Progress' || story.Build_Status__c == 'Queued') {
            story.Build_Status__c = 'Not Started';
            story.PR_Status__c = null;
            needStoryUpdate = true;
        }
        if (needStoryUpdate) {
            update story;
        }

        // Cancel any active/stuck Deployment Requests
        List<Deployment_Request__c> activeRequests = [
            SELECT Id, Status__c 
            FROM Deployment_Request__c 
            WHERE User_Story__c = :userStoryId 
            AND Status__c != 'Completed' 
            AND Status__c != 'Failed' 
            AND Status__c != 'Cancelled'
        ];
        
        List<Deployment_Request__c> reqsToUpdate = new List<Deployment_Request__c>();
        List<Deployment_Request__c> draftRequests = new List<Deployment_Request__c>();
        for (Deployment_Request__c req : activeRequests) {
            if (req.Status__c != 'Draft') {
                req.Status__c = 'Cancelled';
                reqsToUpdate.add(req);
            } else {
                draftRequests.add(req);
            }
        }
        if (!reqsToUpdate.isEmpty()) {
            update reqsToUpdate;
        }

        if (draftRequests.isEmpty()) {
            Id resolvedTargetEnvId = targetEnvironmentId;
            if (resolvedTargetEnvId == null && story.Pipeline__c != null && sourceEnvironmentId != null) {
                List<Stage__c> stages = [
                    SELECT Id, Target_Environment__c, Stage_Order__c
                    FROM Stage__c
                    WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                    ORDER BY Stage_Order__c ASC
                ];
                Integer matchIdx = -1;
                for (Integer i = 0; i < stages.size(); i++) {
                    if (stages[i].Target_Environment__c == sourceEnvironmentId) {
                        matchIdx = i;
                        break;
                    }
                }
                if (matchIdx != -1 && matchIdx + 1 < stages.size()) {
                    resolvedTargetEnvId = stages[matchIdx + 1].Target_Environment__c;
                } else if (!stages.isEmpty()) {
                    resolvedTargetEnvId = stages[0].Target_Environment__c;
                }
            }

            Deployment_Request__c newReq = new Deployment_Request__c(
                User_Story__c = userStoryId,
                Source_Environment__c = sourceEnvironmentId,
                Target_Environment__c = resolvedTargetEnvId,
                Pipeline__c = story.Pipeline__c,
                Release__c = releaseId,
                Status__c = 'Draft'
            );
            insert newReq;
        }

        // Group selected components by type and build map of component name -> wrapper (using lower-case combined key to avoid case mismatch)
        Map<String, SelectedComponentWrapper> selectedCompToWrapperMap = new Map<String, SelectedComponentWrapper>();
        for (SelectedComponentWrapper comp : components) {
            if (comp.type != null && comp.value != null) {
                String key = (comp.type.trim() + ':' + comp.value.trim()).toLowerCase();
                selectedCompToWrapperMap.put(key, comp);
            }
        }

        // Query all existing metadata records for this User Story
        List<User_Story_Metadata__c> existingRecords = [
            SELECT Id, Metadata_API_Name__c, Metadata_Type__c, Selected__c, Action__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId
        ];

        List<User_Story_Metadata__c> recordsToUpdate = new List<User_Story_Metadata__c>();
        Set<String> existingKeys = new Set<String>();

        for (User_Story_Metadata__c rec : existingRecords) {
            String key = (rec.Metadata_Type__c != null ? rec.Metadata_Type__c.trim() : '') + ':' + (rec.Metadata_API_Name__c != null ? rec.Metadata_API_Name__c.trim() : '');
            String keyLower = key.toLowerCase();
            existingKeys.add(keyLower);

            // Check if this component is selected in the UI
            Boolean isSelectedInUI = selectedCompToWrapperMap.containsKey(keyLower);
            String newAction = '';
            if (isSelectedInUI) {
                newAction = selectedCompToWrapperMap.get(keyLower).action;
            }

            Boolean isChanged = false;
            if (isSelectedInUI && !rec.Selected__c) {
                rec.Selected__c = true;
                isChanged = true;
            } else if (!isSelectedInUI && rec.Selected__c) {
                rec.Selected__c = false;
                isChanged = true;
            }
            if (isSelectedInUI && String.isNotBlank(newAction) && rec.Action__c != newAction) {
                rec.Action__c = newAction;
                isChanged = true;
            }

            if (isChanged) {
                recordsToUpdate.add(rec);
            }
        }

        List<User_Story_Metadata__c> recordsToInsert = new List<User_Story_Metadata__c>();
        for (SelectedComponentWrapper comp : components) {
            String key = comp.type + ':' + comp.value;
            if (!existingKeys.contains(key.toLowerCase())) {
                User_Story_Metadata__c recordItem = new User_Story_Metadata__c();
                recordItem.User_Story__c = userStoryId;
                recordItem.Metadata_Type__c = comp.type;
                recordItem.Metadata_API_Name__c = comp.value;
                recordItem.Name = comp.value;
                recordItem.Selected__c = true;
                recordItem.Action__c = String.isNotBlank(comp.action) ? comp.action : 'Add';
                recordItem.File_Path__c = getFilePath(comp.type, comp.value);
                recordsToInsert.add(recordItem);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
        System.debug(LoggingLevel.INFO, '[MetadataSaveController.saveSelectedComponents] SUCCESS - Updated: ' + recordsToUpdate.size() + ' | Inserted: ' + recordsToInsert.size());
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataSaveController.saveSelectedComponents] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Error saving selected components: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void saveMetadataSelections(
        Id userStoryId,
        String metadataType,
        List<String> metadataNames,
        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        Id releaseId
    ){
        if(userStoryId == null){
            throw new AuraHandledException(
                'User Story is required'
            );
        }

        if(metadataNames == null || metadataNames.isEmpty()){
            throw new AuraHandledException(
                'No metadata selected'
            );
        }

        // Fetch User Story to update Source Environment
        User_Story__c story = [
            SELECT Id, Pipeline__c, Source_Environment__c, Build_Status__c, PR_Status__c 
            FROM User_Story__c 
            WHERE Id = :userStoryId 
            LIMIT 1
        ];
        
        Boolean needStoryUpdate = false;
        if (story.Source_Environment__c != sourceEnvironmentId) {
            story.Source_Environment__c = sourceEnvironmentId;
            needStoryUpdate = true;
        }
        if (story.Build_Status__c == 'In Progress' || story.Build_Status__c == 'Queued') {
            story.Build_Status__c = 'Not Started';
            story.PR_Status__c = null;
            needStoryUpdate = true;
        }
        if (needStoryUpdate) {
            update story;
        }

        // Cancel any active/stuck Deployment Requests
        List<Deployment_Request__c> activeRequests = [
            SELECT Id, Status__c 
            FROM Deployment_Request__c 
            WHERE User_Story__c = :userStoryId 
            AND Status__c != 'Completed' 
            AND Status__c != 'Failed' 
            AND Status__c != 'Cancelled'
        ];
        
        List<Deployment_Request__c> reqsToUpdate = new List<Deployment_Request__c>();
        List<Deployment_Request__c> draftRequests = new List<Deployment_Request__c>();
        for (Deployment_Request__c req : activeRequests) {
            if (req.Status__c != 'Draft') {
                req.Status__c = 'Cancelled';
                reqsToUpdate.add(req);
            } else {
                draftRequests.add(req);
            }
        }
        if (!reqsToUpdate.isEmpty()) {
            update reqsToUpdate;
        }

        if (draftRequests.isEmpty()) {
            Id resolvedTargetEnvId = targetEnvironmentId;
            if (resolvedTargetEnvId == null && story.Pipeline__c != null && sourceEnvironmentId != null) {
                List<Stage__c> stages = [
                    SELECT Id, Target_Environment__c, Stage_Order__c
                    FROM Stage__c
                    WHERE Pipeline__c = :story.Pipeline__c AND Status__c = 'Active'
                    ORDER BY Stage_Order__c ASC
                ];
                Integer matchIdx = -1;
                for (Integer i = 0; i < stages.size(); i++) {
                    if (stages[i].Target_Environment__c == sourceEnvironmentId) {
                        matchIdx = i;
                        break;
                    }
                }
                if (matchIdx != -1 && matchIdx + 1 < stages.size()) {
                    resolvedTargetEnvId = stages[matchIdx + 1].Target_Environment__c;
                } else if (!stages.isEmpty()) {
                    resolvedTargetEnvId = stages[0].Target_Environment__c;
                }
            }

            Deployment_Request__c newReq = new Deployment_Request__c(
                User_Story__c = userStoryId,
                Source_Environment__c = sourceEnvironmentId,
                Target_Environment__c = resolvedTargetEnvId,
                Pipeline__c = story.Pipeline__c,
                Release__c = releaseId,
                Status__c = 'Draft'
            );
            insert newReq;
        }

        List<User_Story_Metadata__c> existingRecords = [
            SELECT Id, Metadata_API_Name__c, Selected__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId
            AND Metadata_Type__c = :metadataType
        ];

        Set<String> selectedNamesSet = new Set<String>(metadataNames);
        Set<String> existingNamesSet = new Set<String>();
        
        List<User_Story_Metadata__c> recordsToUpdate = new List<User_Story_Metadata__c>();
        
        for (User_Story_Metadata__c rec : existingRecords) {
            existingNamesSet.add(rec.Metadata_API_Name__c);
            
            Boolean shouldBeSelected = selectedNamesSet.contains(rec.Metadata_API_Name__c);
            if (rec.Selected__c != shouldBeSelected) {
                rec.Selected__c = shouldBeSelected;
                recordsToUpdate.add(rec);
            }
        }
        
        List<User_Story_Metadata__c> recordsToInsert = new List<User_Story_Metadata__c>();
        for (String metadataName : metadataNames) {
            if (!existingNamesSet.contains(metadataName)) {
                User_Story_Metadata__c recordItem = new User_Story_Metadata__c();
                recordItem.User_Story__c = userStoryId;
                recordItem.Metadata_Type__c = metadataType;
                recordItem.Metadata_API_Name__c = metadataName;
                recordItem.Name = metadataName;
                recordItem.Selected__c = true;
                recordItem.Action__c = 'Add';
                recordItem.File_Path__c = getFilePath(metadataType, metadataName);
                recordsToInsert.add(recordItem);
            }
        }
        
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    }

    private static String getFilePath(String metadataType, String apiName) {
        String folder = '';
        String ext = '';
        
        if (metadataType == 'ApexClass') {
            folder = 'classes';
            ext = '.cls';
        } else if (metadataType == 'ApexTrigger') {
            folder = 'triggers';
            ext = '.trigger';
        } else if (metadataType == 'ApexPage') {
            folder = 'pages';
            ext = '.page';
        } else if (metadataType == 'ApexComponent') {
            folder = 'components';
            ext = '.component';
        } else if (metadataType == 'LightningComponentBundle') {
            return 'force-app/main/default/lwc/' + apiName + '/' + apiName + '.js';
        } else if (metadataType == 'AuraDefinitionBundle') {
            return 'force-app/main/default/aura/' + apiName + '/' + apiName + '.cmp';
        } else if (metadataType == 'CustomObject') {
            return 'force-app/main/default/objects/' + apiName + '/' + apiName + '.object-meta.xml';
        } else if (metadataType == 'CustomField') {
            if (apiName.contains('.')) {
                String[] parts = apiName.split('\\.');
                return 'force-app/main/default/objects/' + parts[0] + '/fields/' + parts[1] + '.field-meta.xml';
            }
        } else {
            folder = metadataType.toLowerCase() + 's';
            ext = '.' + metadataType.toLowerCase();
        }
        
        return 'force-app/main/default/' + folder + '/' + apiName + ext;
    }
}