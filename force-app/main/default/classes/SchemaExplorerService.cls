public with sharing class SchemaExplorerService {
    public class RelatedObjectInfo {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String relationshipType;
    }
    public class HierarchyNode {
        @AuraEnabled public String nodeId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String label;
        @AuraEnabled public Integer level;
        @AuraEnabled public String parentNodeId;
        @AuraEnabled public String relationshipType;

    }
            @AuraEnabled(cacheable=true)
            public static List<RelatedObjectInfo> getRelatedObjects(String objectApiName) {
                List<RelatedObjectInfo> response = new List<RelatedObjectInfo>();

                if (String.isBlank(objectApiName)) {
                    return response;
                }
                Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();

                if (!globalMap.containsKey(objectApiName)) {

                    return response;

                }
                // 🔒 SAFE DESCRIBE (ERROR FREE)
                Schema.SObjectType rootType = globalMap.get(objectApiName);
                Schema.DescribeSObjectResult rootDesc = rootType.getDescribe();
                Set<String> added = new Set<String>();
                /* ===================== PARENT OBJECTS ===================== */

                // Rule: REFERENCE fields = Parent side
                Integer parentCount = 0;

                for (Schema.SObjectField field : rootDesc.fields.getMap().values()) {
                    if (parentCount >= 3) {
                        break;
                    }
                    Schema.DescribeFieldResult fd = field.getDescribe();
                    if (fd.getType() != Schema.DisplayType.REFERENCE) {
                        continue;

                    }
                    for (Schema.SObjectType refType : fd.getReferenceTo()) {

                        if (refType == null) {
                            continue;
                        }

                        Schema.DescribeSObjectResult parentDesc = refType.getDescribe();
                        String parentApi = parentDesc.getName();
                        if (added.contains(parentApi)) {
                            continue;
                        }
                        RelatedObjectInfo info = new RelatedObjectInfo();
                        info.objectApiName = parentApi;
                        info.objectLabel = parentDesc.getLabel();
                        info.relationshipType = 'Parent';
                        response.add(info);
                        added.add(parentApi);
                        parentCount++;
                    }
                }

                /* ===================== CHILD OBJECTS ===================== */

                // Rule: ChildRelationship = direct child
                // 3. Children

                /* ===================== CHILD OBJECTS ===================== */

                for (Schema.ChildRelationship cr : rootDesc.getChildRelationships()) {
                    if (cr.getChildSObject() == null) continue;
                    Schema.DescribeSObjectResult childDesc =
                        cr.getChildSObject().getDescribe();
                    String childApi = childDesc.getName();
                    if (added.contains(childApi)) continue;
                    if (childApi.contains('__History')) continue;
                    if (childApi.contains('Feed')) continue;
                    if (childApi == 'User') continue;
                    RelatedObjectInfo childInfo = new RelatedObjectInfo();
                    childInfo.objectApiName = childApi;
                    childInfo.objectLabel = childDesc.getLabel();
                    childInfo.relationshipType = 'Child';
                    response.add(childInfo);
                    added.add(childApi);

                    /* ===================== SUB CHILD ===================== */

                    for (Schema.ChildRelationship subCr : childDesc.getChildRelationships()) {
                        if (subCr.getChildSObject() == null) continue;
                        Schema.DescribeSObjectResult subDesc =
                            subCr.getChildSObject().getDescribe();
                        String subApi = subDesc.getName();

                        if (added.contains(subApi)) continue;
                        if (subApi.contains('__History')) continue;

                        if (subApi.contains('Feed')) continue;

                        if (subApi == 'User') continue;
                        RelatedObjectInfo subInfo = new RelatedObjectInfo();
                        subInfo.objectApiName = subApi;
                        subInfo.objectLabel = subDesc.getLabel();
                        subInfo.relationshipType = 'SubChild';
                        response.add(subInfo);
                        added.add(subApi);
                    }
                }          
                return response;
            }

        @AuraEnabled(cacheable=true)
        public static List<RelatedObjectInfo> getRecordLevelParents(
            String parentObjectApi,
            Id recordId
        ) {

            List<RelatedObjectInfo> result = new List<RelatedObjectInfo>();
            if (String.isBlank(parentObjectApi) || recordId == null) return result;
            Schema.DescribeSObjectResult d = Schema.getGlobalDescribe().get(parentObjectApi).getDescribe();
            for (Schema.SObjectField f : d.fields.getMap().values()) {

                Schema.DescribeFieldResult fd = f.getDescribe();

                if (fd.getType() != Schema.DisplayType.REFERENCE) continue;

                String fieldName = fd.getName();
                String soql =
                    'SELECT ' + fieldName +
                    ' FROM ' + parentObjectApi +
                    ' WHERE Id = :recordId';
                SObject rec = Database.query(soql);

                if (rec.get(fieldName) != null) {

                    for (Schema.SObjectType ref : fd.getReferenceTo()) {

                        RelatedObjectInfo info = new RelatedObjectInfo();

                        info.objectApiName = ref.getDescribe().getName();

                        info.objectLabel = ref.getDescribe().getLabel();

                        info.relationshipType = 'Parent';

                        result.add(info);

                    }

                }

            }

            return result;

        }



    @AuraEnabled(cacheable=true)
    public static List<HierarchyNode> getObjectHierarchyTree(String objectApi) {
        System.debug('======= [HIERARCHY RESTORE START] =======');
        List<HierarchyNode> nodes = new List<HierarchyNode>();
        
        if(String.isBlank(objectApi)) return nodes;
    
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        if(!globalMap.containsKey(objectApi)) return nodes;
    
        Schema.DescribeSObjectResult rootDesc = globalMap.get(objectApi).getDescribe();
        Set<String> exclude = new Set<String>{'User','Profile','RecordType','Group','FeedItem','CollaborationGroup','Organization','OrganizationChangeEvent'};
        Set<String> addedNodes = new Set<String>();
    
        // ---------------------------------------------------------
        // 1. ROW 1 (LEVEL 0): MOST RELEVANT 3 PARENTS (Lookups)
        // ---------------------------------------------------------
        Integer pLimit = 0;
        for(Schema.SObjectField f : rootDesc.fields.getMap().values()){
            Schema.DescribeFieldResult fd = f.getDescribe();
            if(fd.getType() == Schema.DisplayType.REFERENCE) {
                for(Schema.SObjectType ref : fd.getReferenceTo()){
                    String pApi = ref.getDescribe().getName();
                    // Proof: Anchor object cannot be its own Parent in Row 1
                    if(exclude.contains(pApi) || pApi == objectApi || addedNodes.contains(pApi) || pLimit >= 3) continue;
                    
                    HierarchyNode row1ParentNode = new HierarchyNode();
                    row1ParentNode.nodeId = 'R1-' + pApi;
                    row1ParentNode.objectApiName = pApi;
                    row1ParentNode.label = ref.getDescribe().getLabel() + ' (Parent)';
                    row1ParentNode.level = 0;
                    row1ParentNode.relationshipType = 'Parent';
                    nodes.add(row1ParentNode);
                    addedNodes.add(pApi);
                    pLimit++;
                }
            }
            if(pLimit >= 3) break;
        }
    
        // ---------------------------------------------------------
        // 2. ROW 2 (LEVEL 1): SELECT OBJECT'S ACTUAL CHILDREN
        // ---------------------------------------------------------
        for(Schema.ChildRelationship cr : rootDesc.getChildRelationships()){
            if(cr.getChildSObject() == null) continue;
            Schema.DescribeSObjectResult childDesc = cr.getChildSObject().getDescribe();
            String cApi = childDesc.getName();
            
            if(exclude.contains(cApi) || cApi.contains('History') || cApi.contains('Feed') || addedNodes.contains(cApi)) continue;
        
            HierarchyNode row2Node = new HierarchyNode();
            row2Node.nodeId = 'R2-' + cApi;
            row2Node.objectApiName = cApi;
            row2Node.label = childDesc.getLabel();
            row2Node.level = 1;
            // row2Node.parentNodeId = 'ROOT'; 
            row2Node.relationshipType = 'Child';
            // Note: These are linked to the searched Anchor
            nodes.add(row2Node);
            addedNodes.add(cApi);
        
            // ---------------------------------------------------------
            // 3. ROW 3 (LEVEL 2): SUB-CHILDREN (Linked to R2 parents)
            // ---------------------------------------------------------
            Integer scLimit = 0;
            for(Schema.ChildRelationship subCr : childDesc.getChildRelationships()){
                if(scLimit >= 5) break; 
                if(subCr.getChildSObject() == null) continue;
                
                Schema.DescribeSObjectResult scDesc = subCr.getChildSObject().getDescribe();
                String scApi = scDesc.getName();
                
                // Check to avoid self-lookup loops and anchor duplication
                if(exclude.contains(scApi) || scApi == cApi || scApi == objectApi || scApi.contains('History') || scApi.contains('Feed') || addedNodes.contains(scApi)) continue;
            
                HierarchyNode row3Node = new HierarchyNode();
                row3Node.nodeId = 'R3-' + cApi + '-' + scApi; // prefix based identification
                row3Node.objectApiName = scApi;
                row3Node.label = scDesc.getLabel();
                row3Node.level = 2;
                row3Node.parentNodeId = row2Node.nodeId; // STRICT CHAINING TO ROW 2
                row3Node.relationshipType = 'SubChild';
                nodes.add(row3Node);
                scLimit++;
            }
        }
        
        System.debug('✅ [HIERARCHY RESTORED] Total Discovery Nodes: ' + nodes.size());
        return nodes;
    }
    /* =========================================================
       INTERNAL RECURSIVE BUILDER (NO ASSUMPTIONS)
       ========================================================= */

    private static void buildObjectHierarchy(
        String objectApi,
        String parentNodeId,
        Integer level,
        Map<String, Schema.SObjectType> globalMap,
        Set<String> visited,
        List<HierarchyNode> result
    ) {
        if (!globalMap.containsKey(objectApi)) return;
        if (level > 2) return; // 🔴 IMPORTANT: only parent + child for now
        Schema.DescribeSObjectResult objDescribe =
            globalMap.get(objectApi).getDescribe();
        // ================= ROOT NODE =================
        if (level == 0) {
            HierarchyNode root = new HierarchyNode();
            root.nodeId = objectApi;
            root.objectApiName = objectApi;
            root.label = objDescribe.getLabel();
            root.level = 0;
            root.parentNodeId = null;
            root.relationshipType = 'Root';
            result.add(root);
            // 🔹 PARENTS (MAX 3)
            Integer parentCount = 0;
            Set<String> addedParents = new Set<String>();

            for (Schema.SObjectField f : objDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fd = f.getDescribe();
                if (fd.getType() != Schema.DisplayType.REFERENCE) continue;

                for (Schema.SObjectType ref : fd.getReferenceTo()) {
                    String parentApi = ref.getDescribe().getName();
                    if (addedParents.contains(parentApi)) continue;
                    // ❌ REMOVE SYSTEM / USELESS OBJECTS
                    if (parentApi == 'User') continue;
                    if (parentApi.contains('__History')) continue;
                    if (parentApi.contains('Feed')) continue;
                    if (parentCount >= 3) break;

                    HierarchyNode parent = new HierarchyNode();
                    parent.nodeId = objectApi + '->' + parentApi;
                    parent.objectApiName = parentApi;
                    parent.label = ref.getDescribe().getLabel();
                    parent.level = 1;
                    parent.parentNodeId = objectApi;
                    parent.relationshipType = 'Parent';
                    result.add(parent);
                    addedParents.add(parentApi);
                   parentCount++;
                }
               if (parentCount >= 3) break;
            }
            return;
        }

        // ================= CHILD LEVEL =================
        if (level == 1) {
            Integer childCount = 0;
            Set<String> addedChildren = new Set<String>();
            for (Schema.ChildRelationship cr : objDescribe.getChildRelationships()) {
                if (cr.getChildSObject() == null) continue;
                String childApi = cr.getChildSObject().getDescribe().getName();

                // ❌ self loop remove
                if (childApi == objectApi) continue;

                if (addedChildren.contains(childApi)) continue;
                if (childCount >= 5) break;
                HierarchyNode child = new HierarchyNode();
                child.nodeId = parentNodeId + '->' + childApi;
                child.objectApiName = childApi;
                child.label = cr.getChildSObject().getDescribe().getLabel();
                child.level = 2;
                child.parentNodeId = parentNodeId;
                child.relationshipType = 'Child';
                result.add(child);
                addedChildren.add(childApi);
                childCount++;
            }
        }
    }
    // ============== SIMPLE HIERARCHY META (OPTIONAL) ==============
    // Yeh method UI me abhi direct use nahi kar rahe, sirf future ke liye metadata graph ke liye.
    @AuraEnabled(cacheable=true)
    public static List<HierarchyNode> getHierarchyGraph(String rootObjectApiName) {
        List<HierarchyNode> graph = new List<HierarchyNode>();
        if (String.isBlank(rootObjectApiName)) return graph;
        Map<String, Schema.SObjectType> globalMap = Schema.getGlobalDescribe();
        if (!globalMap.containsKey(rootObjectApiName)) return graph;
        Set<String> visited = new Set<String>();
        HierarchyNode root = new HierarchyNode();
        root.nodeId = rootObjectApiName;
        root.objectApiName = rootObjectApiName;
        root.label = globalMap.get(rootObjectApiName).getDescribe().getLabel();
        root.level = 0;
        root.parentNodeId = null;
        graph.add(root);
        visited.add(rootObjectApiName);

        buildHierarchyRecursive(
            rootObjectApiName,
            1,
            rootObjectApiName,
            globalMap,
            visited,
            graph
        );
        return graph;
    }

    private static void buildHierarchyRecursive(
        String parentApi,
        Integer level,
        String parentNodeId,
        Map<String, Schema.SObjectType> globalMap,
        Set<String> visited,
        List<HierarchyNode> graph
    ) {
        if (!globalMap.containsKey(parentApi)) return;
        if (level > 4) return; // depth guard
        Schema.DescribeSObjectResult parentDesc =
            globalMap.get(parentApi).getDescribe();

        for (Schema.ChildRelationship cr : parentDesc.getChildRelationships()) {
            if (cr.getChildSObject() == null) continue;
            String childApi = cr.getChildSObject().getDescribe().getName();
            if (String.isBlank(childApi) || visited.contains(childApi)) continue;
            HierarchyNode node = new HierarchyNode();
            node.nodeId = parentApi + '->' + childApi;
            node.objectApiName = childApi;
            node.label = cr.getChildSObject().getDescribe().getLabel();
            node.level = level;
            node.parentNodeId = parentNodeId;
            graph.add(node);
            visited.add(childApi);
            buildHierarchyRecursive(
                childApi,
                level + 1,
                childApi,
                globalMap,
                visited,
                graph
            );
        }
    }
}