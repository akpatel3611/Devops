public with sharing class MetadataSaveController {

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
            Deployment_Request__c newReq = new Deployment_Request__c(
                User_Story__c = userStoryId,
                Source_Environment__c = sourceEnvironmentId,
                Target_Environment__c = targetEnvironmentId,
                Pipeline__c = story.Pipeline__c,
                Release__c = releaseId,
                Status__c = 'Draft'
            );
            insert newReq;
        }

        Set<String> existingMetadata = new Set<String>();
        for(User_Story_Metadata__c existingRecord : [
            SELECT Metadata_API_Name__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId
            AND Metadata_Type__c = :metadataType
        ]){
            existingMetadata.add(existingRecord.Metadata_API_Name__c);
        }

        List<User_Story_Metadata__c> recordsToInsert = new List<User_Story_Metadata__c>();
        for(String metadataName : metadataNames){
            if(existingMetadata.contains(metadataName)){
                continue;
            }

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

        if(!recordsToInsert.isEmpty()){
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