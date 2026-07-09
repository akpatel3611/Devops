/**
 * Service class responsible for managing the Metadata Inventory attached to a User Story.
 * Implements inventory creation, loading, refresh, selection, validation, and summary statistics.
 * Delegates DML and SOQL query operations safely, keeping the existing pipeline architectures stable.
 */
public with sharing class MetadataInventoryService {

    public class MetadataInventoryException extends Exception {}

    // DTO for inventory operations results
    public class InventoryResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO for inventory validation results
    public class ValidationResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO for inventory summary statistics
    public class InventorySummary {
        @AuraEnabled public Integer totalCount {get;set;}
        @AuraEnabled public Integer selectedCount {get;set;}
        @AuraEnabled public Map<String, Integer> typeGroups {get;set;}
        @AuraEnabled public Map<String, Integer> actionGroups {get;set;}
    }

    private static InventoryResult createFailedResult(String errorMsg) {
        InventoryResult res = new InventoryResult();
        res.success = false;
        res.message = errorMsg;
        res.errors = new List<String>{ errorMsg };
        return res;
    }

    /**
     * Checks if inventory records already exist for the User Story.
     * If they do, retrieves and returns them.
     * If not, generates a default mock inventory, persists it, and returns the records.
     */
    public static List<User_Story_Metadata__c> buildOrLoadInventory(Id userStoryId) {
        if (userStoryId == null) {
            throw new MetadataInventoryException('User Story ID cannot be null.');
        }

        try {
            List<User_Story_Metadata__c> existing = loadInventory(userStoryId);
            if (!existing.isEmpty()) {
                return existing;
            }

            // Generate, persist, and return new inventory if none exists
            List<User_Story_Metadata__c> generated = generateDefaultInventory(userStoryId);
            if (!generated.isEmpty()) {
                insert generated;
            }
            return generated;
        } catch (Exception ex) {
            throw new MetadataInventoryException('Failed to build or load metadata inventory: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Loads existing metadata inventory records for the given User Story.
     */
    public static List<User_Story_Metadata__c> loadInventory(Id userStoryId) {
        if (userStoryId == null) {
            throw new MetadataInventoryException('User Story ID cannot be null.');
        }

        return [
            SELECT Id, Name, User_Story__c, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c, Selected__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId
            ORDER BY Metadata_Type__c ASC, Metadata_API_Name__c ASC
        ];
    }

    /**
     * Rebuilds the metadata inventory by generating a new set of records,
     * while preserving developer selection status ('Selected__c') for matching components.
     */
    public static List<User_Story_Metadata__c> refreshInventory(Id userStoryId) {
        if (userStoryId == null) {
            throw new MetadataInventoryException('User Story ID cannot be null.');
        }

        try {
            // Step 1: Query existing inventory and map their unique keys to their selection state
            List<User_Story_Metadata__c> existingRecords = loadInventory(userStoryId);
            Map<String, Boolean> selectionMap = new Map<String, Boolean>();
            for (User_Story_Metadata__c rec : existingRecords) {
                String key = (rec.Metadata_Type__c + ':' + rec.Metadata_API_Name__c).toLowerCase();
                selectionMap.put(key, rec.Selected__c);
            }

            // Step 2: Delete the old inventory records
            if (!existingRecords.isEmpty()) {
                delete existingRecords;
            }

            // Step 3: Generate the new inventory components
            List<User_Story_Metadata__c> newInventory = generateDefaultInventory(userStoryId);

            // Step 4: Preserve selections for matching components
            for (User_Story_Metadata__c rec : newInventory) {
                String key = (rec.Metadata_Type__c + ':' + rec.Metadata_API_Name__c).toLowerCase();
                if (selectionMap.containsKey(key)) {
                    rec.Selected__c = selectionMap.get(key);
                }
            }

            // Step 5: Persist new inventory and return
            if (!newInventory.isEmpty()) {
                insert newInventory;
            }
            return newInventory;
        } catch (Exception ex) {
            throw new MetadataInventoryException('Failed to refresh metadata inventory: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Selects specified user story metadata records in bulk.
     */
    public static InventoryResult selectMetadata(List<Id> metadataIds) {
        if (metadataIds == null || metadataIds.isEmpty()) {
            return createFailedResult('Metadata IDs list cannot be null or empty.');
        }

        try {
            List<User_Story_Metadata__c> records = [
                SELECT Id, Selected__c 
                FROM User_Story_Metadata__c 
                WHERE Id IN :metadataIds
            ];

            for (User_Story_Metadata__c rec : records) {
                rec.Selected__c = true;
            }

            update records;

            InventoryResult res = new InventoryResult();
            res.success = true;
            res.message = 'Metadata selected successfully.';
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedResult('Failed to select metadata: ' + ex.getMessage());
        }
    }

    /**
     * Unselects specified user story metadata records in bulk.
     */
    public static InventoryResult unselectMetadata(List<Id> metadataIds) {
        if (metadataIds == null || metadataIds.isEmpty()) {
            return createFailedResult('Metadata IDs list cannot be null or empty.');
        }

        try {
            List<User_Story_Metadata__c> records = [
                SELECT Id, Selected__c 
                FROM User_Story_Metadata__c 
                WHERE Id IN :metadataIds
            ];

            for (User_Story_Metadata__c rec : records) {
                rec.Selected__c = false;
            }

            update records;

            InventoryResult res = new InventoryResult();
            res.success = true;
            res.message = 'Metadata unselected successfully.';
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedResult('Failed to unselect metadata: ' + ex.getMessage());
        }
    }

    /**
     * Returns only the user story metadata records that are currently selected.
     */
    public static List<User_Story_Metadata__c> returnSelectedMetadata(Id userStoryId) {
        if (userStoryId == null) {
            throw new MetadataInventoryException('User Story ID cannot be null.');
        }

        return [
            SELECT Id, Name, User_Story__c, Metadata_API_Name__c, Metadata_Type__c, Action__c, File_Path__c, Selected__c
            FROM User_Story_Metadata__c
            WHERE User_Story__c = :userStoryId AND Selected__c = true
            ORDER BY Metadata_Type__c ASC, Metadata_API_Name__c ASC
        ];
    }

    /**
     * Returns summary statistics for the inventory (total count, selected count, and grouping summaries).
     */
    public static InventorySummary returnInventorySummary(Id userStoryId) {
        if (userStoryId == null) {
            throw new MetadataInventoryException('User Story ID cannot be null.');
        }

        List<User_Story_Metadata__c> allRecords = loadInventory(userStoryId);

        InventorySummary summary = new InventorySummary();
        summary.totalCount = allRecords.size();
        summary.selectedCount = 0;
        summary.typeGroups = new Map<String, Integer>();
        summary.actionGroups = new Map<String, Integer>();

        for (User_Story_Metadata__c rec : allRecords) {
            if (rec.Selected__c == true) {
                summary.selectedCount++;
            }

            // Group by Metadata Type
            String typeKey = String.isNotBlank(rec.Metadata_Type__c) ? rec.Metadata_Type__c : 'UnknownType';
            Integer typeCount = summary.typeGroups.containsKey(typeKey) ? summary.typeGroups.get(typeKey) : 0;
            summary.typeGroups.put(typeKey, typeCount + 1);

            // Group by Action (Deployment Action)
            String actionKey = String.isNotBlank(rec.Action__c) ? rec.Action__c : 'UnknownAction';
            Integer actionCount = summary.actionGroups.containsKey(actionKey) ? summary.actionGroups.get(actionKey) : 0;
            summary.actionGroups.put(actionKey, actionCount + 1);
        }

        return summary;
    }

    /**
     * Performs validations verifying that:
     * - User Story exists in the database.
     * - Metadata API Name is present.
     * - Metadata Type is present.
     * - Deployment Action is present.
     * - Selected flag is configured.
     * - User Story relationship links back to the correct User Story.
     */
    public static ValidationResult validateInventory(Id userStoryId) {
        ValidationResult result = new ValidationResult();
        result.success = true;
        result.errors = new List<String>();

        if (userStoryId == null) {
            result.success = false;
            result.errors.add('User Story ID cannot be null.');
            return result;
        }

        try {
            // Verify User Story exists
            List<User_Story__c> stories = [
                SELECT Id 
                FROM User_Story__c 
                WHERE Id = :userStoryId
                LIMIT 1
            ];
            if (stories.isEmpty()) {
                result.success = false;
                result.errors.add('User Story record not found.');
                return result;
            }

            List<User_Story_Metadata__c> records = loadInventory(userStoryId);
            for (User_Story_Metadata__c rec : records) {
                if (String.isBlank(rec.Metadata_API_Name__c)) {
                    result.success = false;
                    result.errors.add('Metadata API Name is missing on record ID: ' + rec.Id);
                }
                if (String.isBlank(rec.Metadata_Type__c)) {
                    result.success = false;
                    result.errors.add('Metadata Type is missing on record ID: ' + rec.Id);
                }
                if (String.isBlank(rec.Action__c)) {
                    result.success = false;
                    result.errors.add('Deployment Action (Action__c) is missing on record ID: ' + rec.Id);
                }
                if (rec.Selected__c == null) {
                    result.success = false;
                    result.errors.add('Selected flag (Selected__c) is null on record ID: ' + rec.Id);
                }
                if (rec.User_Story__c != userStoryId) {
                    result.success = false;
                    result.errors.add('Invalid User Story relationship on record ID: ' + rec.Id);
                }
            }
        } catch (Exception ex) {
            result.success = false;
            result.errors.add('Validation failure: ' + ex.getMessage());
        }

        return result;
    }

    /**
     * Generates a default list of mock metadata components for inventory building and refreshing.
     */
    private static List<User_Story_Metadata__c> generateDefaultInventory(Id userStoryId) {
        List<User_Story_Metadata__c> mockList = new List<User_Story_Metadata__c>();

        User_Story_Metadata__c comp1 = new User_Story_Metadata__c();
        comp1.User_Story__c = userStoryId;
        comp1.Metadata_API_Name__c = 'AccountService';
        comp1.Metadata_Type__c = 'ApexClass';
        comp1.Action__c = 'Modify';
        comp1.File_Path__c = 'force-app/main/default/classes/AccountService.cls';
        comp1.Selected__c = true;
        mockList.add(comp1);

        User_Story_Metadata__c comp2 = new User_Story_Metadata__c();
        comp2.User_Story__c = userStoryId;
        comp2.Metadata_API_Name__c = 'AccountTrigger';
        comp2.Metadata_Type__c = 'ApexTrigger';
        comp2.Action__c = 'Add';
        comp2.File_Path__c = 'force-app/main/default/triggers/AccountTrigger.trigger';
        comp2.Selected__c = true;
        mockList.add(comp2);

        User_Story_Metadata__c comp3 = new User_Story_Metadata__c();
        comp3.User_Story__c = userStoryId;
        comp3.Metadata_API_Name__c = 'Account';
        comp3.Metadata_Type__c = 'CustomObject';
        comp3.Action__c = 'Modify';
        comp3.File_Path__c = 'force-app/main/default/objects/Account/Account.object-meta.xml';
        comp3.Selected__c = true;
        mockList.add(comp3);

        return mockList;
    }
}