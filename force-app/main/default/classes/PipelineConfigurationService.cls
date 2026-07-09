/**
 * Service class that acts as the single unified entry point for Pipeline Configuration management.
 * Owns: CRUD operations on Pipeline__c and Stage__c configuration, pipeline activation, archiving, and order validation.
 * Never: Performs deployments, calls execution queueables, runs approvals, or handles runtime orchestration.
 */
public with sharing class PipelineConfigurationService {

    public class PipelineConfigurationException extends Exception {}

    // Pipeline Status Constants
    public static final String PIPELINE_STATUS_DRAFT = 'Draft';
    public static final String PIPELINE_STATUS_ACTIVE = 'Active';
    public static final String PIPELINE_STATUS_INACTIVE = 'Inactive';

    // Stage Status Constants
    public static final String STAGE_STATUS_ACTIVE = 'Active';
    public static final String STAGE_STATUS_INACTIVE = 'Inactive';

    // DTO class for pipeline action responses
    public class PipelineResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id pipelineId {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO class for stage action responses
    public class StageResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id stageId {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO class for validation results
    public class ValidationResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    /**
     * Helper to instantiate a failed PipelineResult response.
     */
    private static PipelineResult createFailedPipelineResult(String errorMsg) {
        PipelineResult res = new PipelineResult();
        res.success = false;
        res.message = errorMsg;
        res.errors = new List<String>{ errorMsg };
        return res;
    }

    /**
     * Helper to instantiate a failed StageResult response.
     */
    private static StageResult createFailedStageResult(String errorMsg) {
        StageResult res = new StageResult();
        res.success = false;
        res.message = errorMsg;
        res.errors = new List<String>{ errorMsg };
        return res;
    }

    /**
     * Inserts a new Pipeline__c record in Draft status.
     */
    public static PipelineResult createPipeline(
        String name,
        String type,
        Id projectId,
        String description
    ) {
        if (String.isBlank(name)) {
            return createFailedPipelineResult('Pipeline name is mandatory.');
        }

        try {
            Pipeline__c pipe = new Pipeline__c();
            pipe.Name = name;
            pipe.Pipeline_Type__c = type;
            pipe.Project__c = projectId;
            pipe.Description__c = description;
            pipe.Pipeline_Status__c = PIPELINE_STATUS_DRAFT;
            pipe.Active__c = false;
            insert pipe;

            PipelineResult res = new PipelineResult();
            res.success = true;
            res.message = 'Pipeline created successfully in Draft status.';
            res.pipelineId = pipe.Id;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedPipelineResult('Failed to create pipeline: ' + ex.getMessage());
        }
    }

    /**
     * Updates the configuration of an existing Pipeline__c record.
     */
    public static PipelineResult updatePipeline(
        Id pipelineId,
        String name,
        String type,
        Id projectId,
        String description
    ) {
        if (pipelineId == null) {
            return createFailedPipelineResult('Pipeline ID is mandatory.');
        }
        if (String.isBlank(name)) {
            return createFailedPipelineResult('Pipeline name is mandatory.');
        }

        try {
            List<Pipeline__c> existing = [
                SELECT Id 
                FROM Pipeline__c 
                WHERE Id = :pipelineId 
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                return createFailedPipelineResult('Pipeline record not found for ID: ' + pipelineId);
            }

            Pipeline__c pipe = new Pipeline__c(Id = pipelineId);
            pipe.Name = name;
            pipe.Pipeline_Type__c = type;
            pipe.Project__c = projectId;
            pipe.Description__c = description;
            update pipe;

            PipelineResult res = new PipelineResult();
            res.success = true;
            res.message = 'Pipeline updated successfully.';
            res.pipelineId = pipelineId;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedPipelineResult('Failed to update pipeline: ' + ex.getMessage());
        }
    }

    /**
     * Executes validation and activates the pipeline if valid.
     */
    public static PipelineResult activatePipeline(Id pipelineId) {
        if (pipelineId == null) {
            return createFailedPipelineResult('Pipeline ID is mandatory.');
        }

        ValidationResult valRes = validatePipeline(pipelineId);
        if (!valRes.success) {
            PipelineResult res = new PipelineResult();
            res.success = false;
            res.message = 'Pipeline validation failed. Cannot activate.';
            res.pipelineId = pipelineId;
            res.errors = valRes.errors;
            return res;
        }

        try {
            Pipeline__c pipe = new Pipeline__c(Id = pipelineId);
            pipe.Active__c = true;
            pipe.Pipeline_Status__c = PIPELINE_STATUS_ACTIVE;
            update pipe;

            PipelineResult res = new PipelineResult();
            res.success = true;
            res.message = 'Pipeline activated successfully.';
            res.pipelineId = pipelineId;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedPipelineResult('Failed to activate pipeline: ' + ex.getMessage());
        }
    }

    /**
     * Archives (retires) an existing pipeline.
     */
    public static PipelineResult archivePipeline(Id pipelineId) {
        if (pipelineId == null) {
            return createFailedPipelineResult('Pipeline ID is mandatory.');
        }

        try {
            List<Pipeline__c> existing = [
                SELECT Id 
                FROM Pipeline__c 
                WHERE Id = :pipelineId 
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                return createFailedPipelineResult('Pipeline record not found for ID: ' + pipelineId);
            }

            Pipeline__c pipe = new Pipeline__c(Id = pipelineId);
            pipe.Active__c = false;
            pipe.Pipeline_Status__c = PIPELINE_STATUS_INACTIVE;
            update pipe;

            PipelineResult res = new PipelineResult();
            res.success = true;
            res.message = 'Pipeline archived successfully.';
            res.pipelineId = pipelineId;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedPipelineResult('Failed to archive pipeline: ' + ex.getMessage());
        }
    }

    /**
     * Adds a new active stage to the pipeline.
     */
    public static StageResult addStage(
        Id pipelineId,
        String name,
        String stageType,
        Integer order,
        Id targetEnvId,
        String description
    ) {
        if (pipelineId == null) {
            return createFailedStageResult('Pipeline ID is mandatory.');
        }
        if (String.isBlank(name)) {
            return createFailedStageResult('Stage name is mandatory.');
        }
        if (String.isBlank(stageType)) {
            return createFailedStageResult('Stage Type is mandatory.');
        }
        if (order == null) {
            return createFailedStageResult('Stage Order is mandatory.');
        }

        try {
            List<Stage__c> duplicateStages = [
                SELECT Id 
                FROM Stage__c 
                WHERE Pipeline__c = :pipelineId 
                  AND Stage_Order__c = :order 
                  AND Status__c = :STAGE_STATUS_ACTIVE 
                LIMIT 1
            ];
            if (!duplicateStages.isEmpty()) {
                return createFailedStageResult('An active stage already exists with order ' + order + ' in this pipeline.');
            }

            Stage__c stage = new Stage__c();
            stage.Pipeline__c = pipelineId;
            stage.Name = name;
            stage.Stage_Type__c = stageType;
            stage.Stage_Order__c = order;
            stage.Sequence__c = order;
            stage.Target_Environment__c = targetEnvId;
            stage.Description__c = description;
            stage.Status__c = STAGE_STATUS_ACTIVE;
            insert stage;

            StageResult res = new StageResult();
            res.success = true;
            res.message = 'Stage added successfully.';
            res.stageId = stage.Id;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedStageResult('Failed to add stage: ' + ex.getMessage());
        }
    }

    /**
     * Performs logical deactivation of a stage (sets Status__c = Inactive).
     * Never physically deletes the record.
     */
    public static StageResult removeStage(Id stageId) {
        if (stageId == null) {
            return createFailedStageResult('Stage ID is mandatory.');
        }

        try {
            List<Stage__c> existing = [
                SELECT Id 
                FROM Stage__c 
                WHERE Id = :stageId 
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                return createFailedStageResult('Stage record not found for ID: ' + stageId);
            }

            Stage__c stage = new Stage__c(Id = stageId);
            stage.Status__c = STAGE_STATUS_INACTIVE;
            update stage;

            StageResult res = new StageResult();
            res.success = true;
            res.message = 'Stage logically removed successfully (status set to Inactive).';
            res.stageId = stageId;
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedStageResult('Failed to remove stage: ' + ex.getMessage());
        }
    }

    /**
     * Reorders the stages of the pipeline after validating order constraints.
     */
    public static StageResult reorderStages(Id pipelineId, Map<Id, Integer> stageOrderMap) {
        if (pipelineId == null) {
            return createFailedStageResult('Pipeline ID is mandatory.');
        }
        if (stageOrderMap == null || stageOrderMap.isEmpty()) {
            return createFailedStageResult('Stage order map cannot be empty.');
        }

        try {
            List<Stage__c> activeStages = [
                SELECT Id, Name, Stage_Order__c, Sequence__c 
                FROM Stage__c 
                WHERE Pipeline__c = :pipelineId AND Status__c = :STAGE_STATUS_ACTIVE
            ];

            if (activeStages.isEmpty()) {
                return createFailedStageResult('No active stages found for this pipeline.');
            }

            Set<Integer> uniqueOrders = new Set<Integer>();
            List<Stage__c> stagesToUpdate = new List<Stage__c>();

            for (Stage__c stage : activeStages) {
                Integer newOrder = stageOrderMap.get(stage.Id);
                if (newOrder == null) {
                    newOrder = (stage.Stage_Order__c != null) ? stage.Stage_Order__c.intValue() : null;
                }

                if (newOrder == null) {
                    return createFailedStageResult('Stage ' + stage.Name + ' order value is null.');
                }
                if (newOrder <= 0) {
                    return createFailedStageResult('Stage ' + stage.Name + ' order value must be positive (got ' + newOrder + ').');
                }
                if (uniqueOrders.contains(newOrder)) {
                    return createFailedStageResult('Duplicate stage order value detected: ' + newOrder);
                }

                uniqueOrders.add(newOrder);
                stage.Stage_Order__c = newOrder;
                stage.Sequence__c = newOrder; // Sequence matches Stage Order to prevent sequence duplicates
                stagesToUpdate.add(stage);
            }

            // Verify stage ordering remains continuous from 1 to N
            for (Integer i = 1; i <= activeStages.size(); i++) {
                if (!uniqueOrders.contains(i)) {
                    return createFailedStageResult('Stage orders must be continuous starting from 1 (missing order ' + i + ').');
                }
            }

            update stagesToUpdate;

            StageResult res = new StageResult();
            res.success = true;
            res.message = 'Stages reordered successfully.';
            res.errors = new List<String>();
            return res;
        } catch (Exception ex) {
            return createFailedStageResult('Failed to reorder stages: ' + ex.getMessage());
        }
    }

    /**
     * Validates the completeness and structural rules of the pipeline.
     */
    public static ValidationResult validatePipeline(Id pipelineId) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (pipelineId == null) {
            result.success = false;
            result.message = 'Pipeline ID cannot be null.';
            result.errors.add('Pipeline ID cannot be null.');
            return result;
        }

        List<Pipeline__c> pipelines = [
            SELECT Id, Name,
                   (SELECT Id, Name, Stage_Type__c, Stage_Order__c, Status__c, Target_Environment__c
                    FROM Stages__r
                    WHERE Status__c = :STAGE_STATUS_ACTIVE
                    ORDER BY Stage_Order__c ASC)
            FROM Pipeline__c
            WHERE Id = :pipelineId
            LIMIT 1
        ];

        if (pipelines.isEmpty()) {
            result.success = false;
            result.message = 'Pipeline does not exist.';
            result.errors.add('Pipeline does not exist.');
            return result;
        }

        Pipeline__c pipe = pipelines[0];
        if (pipe.Stages__r.isEmpty()) {
            result.success = false;
            result.message = 'Pipeline has no active stages.';
            result.errors.add('Pipeline must have at least one active stage.');
            return result;
        }

        for (Integer i = 0; i < pipe.Stages__r.size(); i++) {
            Stage__c stage = pipe.Stages__r[i];
            
            if (String.isBlank(stage.Stage_Type__c)) {
                result.success = false;
                result.errors.add('Stage ' + stage.Name + ' is missing Stage Type.');
            }
            
            if (stage.Stage_Order__c == null) {
                result.success = false;
                result.errors.add('Stage ' + stage.Name + ' is missing Stage Order.');
            } else if (stage.Stage_Order__c != i + 1) {
                result.success = false;
                result.errors.add('Stage ' + stage.Name + ' has non-continuous or duplicate order (expected ' + (i + 1) + ', got ' + stage.Stage_Order__c + ').');
            }

            if ((stage.Stage_Type__c == 'Deploy' || stage.Stage_Type__c == 'Validation') && stage.Target_Environment__c == null) {
                result.success = false;
                result.errors.add('Stage ' + stage.Name + ' of type ' + stage.Stage_Type__c + ' must have a Target Environment configured.');
            }
        }

        if (!result.success) {
            result.message = 'Pipeline validation failed.';
        } else {
            result.message = 'Pipeline is valid.';
        }

        return result;
    }
}