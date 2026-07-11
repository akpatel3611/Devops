public with sharing class PipelineRuntimeUpdaterService {
    
    /**
     * Updates metadata metrics dynamically across Pipeline, Deployment Request, and User Story.
     */
    public static void updateMetadataStats(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        Integer metadataCount, 
        Integer deployableCount, 
        Integer unsupportedCount, 
        String scanStatus
    ) {
        List<SObject> recordsToUpdate = new List<SObject>();

        // 1. Update Pipeline__c
        if (pipelineId != null) {
            Pipeline__c pipe = new Pipeline__c(Id = pipelineId);
            putLookupIfValid(pipe, 'Current_User_Story__c', userStoryId);
            putLookupIfValid(pipe, 'Current_Deployment_Request__c', deploymentRequestId);
            putIfFieldExists(pipe, 'Metadata_Count__c', metadataCount);
            putIfFieldExists(pipe, 'Deployable_Count__c', deployableCount);
            putIfFieldExists(pipe, 'Unsupported_Count__c', unsupportedCount);
            putIfFieldExists(pipe, 'Last_Scan_Time__c', System.now());
            putIfFieldExists(pipe, 'Deployment_Runtime_Status__c', scanStatus);
            recordsToUpdate.add(pipe);
        }

        // 2. Update Deployment_Request__c
        if (deploymentRequestId != null) {
            Deployment_Request__c req = new Deployment_Request__c(Id = deploymentRequestId);
            putIfFieldExists(req, 'Metadata_Count__c', metadataCount);
            putIfFieldExists(req, 'Deployable_Count__c', deployableCount);
            putIfFieldExists(req, 'Unsupported_Count__c', unsupportedCount);
            putIfFieldExists(req, 'Scan_Completed_Time__c', System.now());
            recordsToUpdate.add(req);
        }

        // 3. Update User_Story__c
        if (userStoryId != null) {
            User_Story__c story = new User_Story__c(Id = userStoryId);
            putIfFieldExists(story, 'Metadata_Count__c', metadataCount);
            putIfFieldExists(story, 'Metadata_Scan_Status__c', scanStatus);
            recordsToUpdate.add(story);
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
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
}