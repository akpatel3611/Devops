public with sharing class DynamicRecordService {

    // ================= DTOs =================
    public class RecordWrapper {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String objectApiName;
    }

    public class ObjectCountWrapper {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Id parentRecordId;
    }

    public class RecordHierarchyNode {
        @AuraEnabled public String nodeId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public Integer level;
        @AuraEnabled public String parentNodeId;
    }

    // ✅ DYNAMIC SEARCH METHOD
    @AuraEnabled
    public static List<RecordWrapper> searchRecords(String objectApiName, String searchKey) {
        List<RecordWrapper> response = new List<RecordWrapper>();
        if (String.isBlank(objectApiName) || String.isBlank(searchKey)) return response;

        // Proof: Handle special fields for Case, Task, and Event
        String fieldName = 'Name';
        if (objectApiName == 'Task' || objectApiName == 'Event') {
            fieldName = 'Subject';
        } else if (objectApiName == 'Case') {
            fieldName = 'CaseNumber';
        }

        String soql = 'SELECT Id, ' + fieldName + ' FROM ' + objectApiName +
                     ' WHERE ' + fieldName + ' LIKE \'%' + String.escapeSingleQuotes(searchKey) + '%\' ' +
                     ' LIMIT 20';

        for (SObject sob : Database.query(soql)) {
            RecordWrapper rw = new RecordWrapper();
            rw.recordId = (Id)sob.get('Id');
            rw.recordName = String.valueOf(sob.get(fieldName));
            rw.objectApiName = objectApiName;
            response.add(rw);
        }
        return response;
    }

    @AuraEnabled
    public static List<ObjectCountWrapper> getRelatedRecordCounts(
        String parentObject,
        Id parentRecordId,
        List<String> relatedObjects
    ) {
        List<ObjectCountWrapper> result = new List<ObjectCountWrapper>();
        
        if (String.isBlank(parentObject) || parentRecordId == null || relatedObjects == null) {
            return result;
        }
    
        // ✅ DYNAMIC FIX: Salesforce restricted objects that cannot be queried directly
        Set<String> restrictedObjects = new Set<String>{
            'ActivityHistory', 'OpenActivity', 'CombinedAttachment', 
            'CollaborationGroupRecord', 'ActivityMetric', 'EmailMessage'
        };
    
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        if (!globalMap.containsKey(parentObject)) return result;
    
        Schema.DescribeSObjectResult parentDesc = globalMap.get(parentObject).getDescribe();
    
        for (String objApi : relatedObjects) {
            // Skip restricted system objects to prevent Server Error 500
            if (restrictedObjects.contains(objApi)) {
                continue;
            }
        
            // Handle TASK (WhoId vs WhatId proof)
            if (objApi == 'Task') {
                Integer tCount = 0;
                try {
                    if (parentObject == 'Contact' || parentObject == 'Lead') {
                        tCount = Database.countQuery('SELECT COUNT() FROM Task WHERE WhoId = \'' + String.escapeSingleQuotes(parentRecordId) + '\'');
                    } else {
                        tCount = Database.countQuery('SELECT COUNT() FROM Task WHERE WhatId = \'' + String.escapeSingleQuotes(parentRecordId) + '\'');
                    }
                    ObjectCountWrapper ocw = new ObjectCountWrapper();
                    ocw.objectApiName = objApi;
                    ocw.totalCount = tCount;
                    result.add(ocw);
                } catch (Exception e) { System.debug('Error: ' + e.getMessage()); }
                continue;
            }
        
            // Dynamic Child Relationship Counting
            for (Schema.ChildRelationship cr : parentDesc.getChildRelationships()) {
                if (cr.getChildSObject() != null && cr.getChildSObject().getDescribe().getName() == objApi) {
                    try {
                        String fkField = cr.getField().getDescribe().getName();
                        String q = 'SELECT COUNT() FROM ' + objApi + ' WHERE ' + fkField + ' = \'' + String.escapeSingleQuotes(parentRecordId) + '\'';
                        Integer countVal = Database.countQuery(q);
                    
                        ObjectCountWrapper ocw = new ObjectCountWrapper();
                        ocw.objectApiName = objApi;
                        ocw.totalCount = countVal;
                        result.add(ocw);
                    } catch (Exception e) { System.debug('Error: ' + e.getMessage()); }
                    break; 
                }
            }
        }
        return result;
    }

    @AuraEnabled
    public static List<RecordWrapper> getRelatedRecords(
        String parentObject,
        String relatedObject,
        Id parentRecordId
    ) {
        List<RecordWrapper> response = new List<RecordWrapper>();
        
        if (String.isBlank(parentObject) || String.isBlank(relatedObject) || parentRecordId == null) {
            return response;
        }
    
        // CASE 1: Current Record Detail (Self selection)
        if (parentObject == relatedObject) {
            try {
                String nameField = 'Name';
                if (parentObject == 'Case') nameField = 'CaseNumber';
                if (parentObject == 'Task') nameField = 'Subject';
            
                String query = 'SELECT Id, ' + nameField + ' FROM ' + parentObject + 
                              ' WHERE Id = \'' + String.escapeSingleQuotes(parentRecordId) + '\'';
                
                SObject record = Database.query(query);
                RecordWrapper rw = new RecordWrapper();
                rw.recordId = (Id)record.get('Id');
                rw.recordName = String.valueOf(record.get(nameField));
                rw.objectApiName = parentObject;
                response.add(rw);
            } catch(Exception e) {
                System.debug('❌ [HIERARCHY DEBUG] Self fetch failed: ' + e.getMessage());
            }
            return response;
        }
    
        // CASE 2: Child Records fetch based on Metadata proof
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        Schema.DescribeSObjectResult parentDesc = globalMap.get(parentObject).getDescribe();
    
        for (Schema.ChildRelationship cr : parentDesc.getChildRelationships()) {
            if (cr.getChildSObject() == null) continue;
            
            String childApiName = cr.getChildSObject().getDescribe().getName();
            if (childApiName != relatedObject) continue;
        
            try {
                String foreignKeyField = cr.getField().getDescribe().getName();
                String childNameField = 'Name';
                
                // Proof: Dynamic naming for Case and Task
                if (relatedObject == 'Case') childNameField = 'CaseNumber';
                if (relatedObject == 'Task') childNameField = 'Subject';
                if (relatedObject == 'Event') childNameField = 'Subject';
            
                String soql = 'SELECT Id, ' + childNameField + ' FROM ' + relatedObject + 
                             ' WHERE ' + foreignKeyField + 
                             ' = \'' + String.escapeSingleQuotes(parentRecordId) + '\' LIMIT 100';
            
                for (SObject sob : Database.query(soql)) {
                    RecordWrapper rw = new RecordWrapper();
                    rw.recordId = (Id)sob.get('Id');
                    rw.recordName = String.valueOf(sob.get(childNameField));
                    rw.objectApiName = relatedObject;
                    response.add(rw);
                }
            } catch (Exception e) {
                System.debug('❌ [HIERARCHY DEBUG] Related fetch failed for ' + relatedObject + ': ' + e.getMessage());
            }
            break; 
        }
        return response;
    }


    

        // ================= HIERARCHY =================
    @AuraEnabled
    public static List<RecordHierarchyNode> buildRecordHierarchy(
            String rootObject,
            Id rootRecordId,
            Integer maxDepth
        ) {
            List<RecordHierarchyNode> result = new List<RecordHierarchyNode>();

            if (String.isBlank(rootObject) || rootRecordId == null) {
                return result;
            }

            Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
            Set<String> visited = new Set<String>();

            buildRecursiveHierarchy(
                rootObject,
                rootRecordId,
                null,
                0,
                maxDepth,
                globalMap,
                visited,
                result
            );

            return result;
        }

            // ================= INTERNAL RECURSIVE HIERARCHY BUILDER =================
    private static void buildRecursiveHierarchy(
        String objectApi,
        Id recordId,
        String parentNodeId,
        Integer level,
        Integer maxDepth,
        Map<String, Schema.SObjectType> globalMap,
        Set<String> visited,
        List<RecordHierarchyNode> result
    ) {
        // ---------- BASIC GUARDS ----------
        if (level > maxDepth) return;
        if (String.isBlank(objectApi) || recordId == null) return;
        if (!globalMap.containsKey(objectApi)) return;

        String visitKey = objectApi + ':' + String.valueOf(recordId);
        if (visited.contains(visitKey)) return;
        visited.add(visitKey);

        // ---------- FETCH CURRENT RECORD ----------
        SObject currentRecord;
        try {
            currentRecord = Database.query(
                'SELECT Id, Name FROM ' + objectApi +
                ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\''
            );
        } catch (Exception e) {
            return;
        }

        // ---------- ADD NODE ----------
        RecordHierarchyNode node = new RecordHierarchyNode();
        node.nodeId = visitKey;
        node.objectApiName = objectApi;
        node.recordId = recordId;
        node.recordName = String.valueOf(currentRecord.get('Name'));
        node.level = level;
        node.parentNodeId = parentNodeId;
        result.add(node);

        // ---------- CHILD RECORDS (INLINE DESCRIBE – SAFE) ----------
        for (Schema.ChildRelationship cr :
            globalMap.get(objectApi).getDescribe().getChildRelationships()
        ) {
            if (cr.getChildSObject() == null) continue;

            String childObject = cr.getChildSObject().getDescribe().getName();
            String fkField = cr.getField().getDescribe().getName();

            String soql =
                'SELECT Id FROM ' + childObject +
                ' WHERE ' + fkField +
                ' = \'' + String.escapeSingleQuotes(recordId) + '\'' +
                ' LIMIT 3';

            for (SObject child : Database.query(soql)) {
                buildRecursiveHierarchy(
                    childObject,
                    (Id) child.get('Id'),
                    node.nodeId,
                    level + 1,
                    maxDepth,
                    globalMap,
                    visited,
                    result
                );
            }
        }
    }


}