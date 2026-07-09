/**
 * Service class responsible for managing database operations for User Story Metadata components inventory.
 * Decouples database persistence of scanner results from the runtime status updates.
 */
public with sharing class UserStoryMetadataService {

    public class UserStoryMetadataException extends Exception {}

    /**
     * Persists scanned metadata components for a given User Story.
     * Deletes any existing components for the User Story to prevent duplicates on re-scans.
     */
    public static void persistMetadata(Id userStoryId, List<MetadataScannerService.MetadataComponent> components) {
        if (userStoryId == null) {
            return;
        }

        try {
            // Step 1: Delete existing inventory records for this user story to prevent duplicates on re-scan
            deleteExistingMetadata(userStoryId);

            // Step 2: Convert and bulk-insert new records
            if (components != null && !components.isEmpty()) {
                List<User_Story_Metadata__c> recordsToInsert = createJunctionRecords(userStoryId, components);
                if (!recordsToInsert.isEmpty()) {
                    insert recordsToInsert;
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Failed to persist User Story Metadata: ' + ex.getMessage());
            throw new UserStoryMetadataException('Failed to persist metadata inventory: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Deletes existing metadata records for a user story.
     */
    private static void deleteExistingMetadata(Id userStoryId) {
        List<User_Story_Metadata__c> existing = [
            SELECT Id 
            FROM User_Story_Metadata__c 
            WHERE User_Story__c = :userStoryId
            LIMIT 10000
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }
    }

    /**
     * Maps scanner DTOs to User_Story_Metadata__c SObjects.
     */
    private static List<User_Story_Metadata__c> createJunctionRecords(
        Id userStoryId, 
        List<MetadataScannerService.MetadataComponent> components
    ) {
        List<User_Story_Metadata__c> records = new List<User_Story_Metadata__c>();
        for (MetadataScannerService.MetadataComponent comp : components) {
            if (comp == null) {
                continue;
            }
            User_Story_Metadata__c rec = new User_Story_Metadata__c();
            rec.User_Story__c = userStoryId;
            rec.Metadata_API_Name__c = comp.componentName;
            rec.Metadata_Type__c = comp.metadataType;
            rec.Action__c = comp.status;
            rec.File_Path__c = comp.filePath;
            records.add(rec);
        }
        return records;
    }
}