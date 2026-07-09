/**
 * Orchestration engine that controls Promotion movement through Pipeline stages.
 * Owns: Stage navigation, approval waits, promotion completion/failure/cancellation.
 * Never: Executes deployments directly, manages credentials, performs callouts.
 * Delegates deployment execution to DeploymentRuntimeService (frozen).
 */
public with sharing class PipelinePromotionExecutionEngine {

    public class PipelinePromotionExecutionException extends Exception {}

    // Orchestration Status Constants
    public static final String STATUS_DRAFT = PromotionRuntimeService.STATUS_DRAFT;
    public static final String STATUS_READY = PromotionRuntimeService.STATUS_READY;
    public static final String STATUS_EXECUTING = PromotionRuntimeService.STATUS_EXECUTING;
    public static final String STATUS_WAITING_FOR_APPROVAL = PromotionRuntimeService.STATUS_WAITING_FOR_APPROVAL;
    public static final String STATUS_COMPLETED = PromotionRuntimeService.STATUS_COMPLETED;
    public static final String STATUS_FAILED = PromotionRuntimeService.STATUS_FAILED;
    public static final String STATUS_CANCELLED = PromotionRuntimeService.STATUS_CANCELLED;

    // Stage Type Constants (matching Stage__c.Stage_Type__c picklist)
    private static final String STAGE_TYPE_DEPLOY = 'Deploy';
    private static final String STAGE_TYPE_VALIDATION = 'Validation';
    private static final String STAGE_TYPE_APPROVAL = 'Approval';
    private static final String STAGE_TYPE_NOTIFICATION = 'Notification';
    private static final String STAGE_TYPE_BUILD = 'Build';

    // DTO for engine operation results
    public class EngineResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id promotionId {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public Id currentStageId {get;set;}
        @AuraEnabled public Id deploymentRequestId {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    /**
     * Helper to instantiate a default EngineResult response.
     */
    private static EngineResult createDefaultResult() {
        EngineResult result = new EngineResult();
        result.success = false;
        result.errors = new List<String>();
        return result;
    }

    /**
     * Starts promotion execution through the pipeline.
     * Loads pipeline stages, sets the first active stage, transitions to Executing.
     */
    public static EngineResult startPromotion(Id promotionId) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            // Load promotion with required fields
            Promotion__c prom = [
                SELECT Id, Status__c, Pipeline__c, Source_Environment__c,
                       Target_Environment__c, Current_Stage__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            // Validate current status allows starting
            if (prom.Status__c != STATUS_DRAFT && prom.Status__c != STATUS_READY) {
                EngineResult errResult = createDefaultResult();
                errResult.message = 'Promotion can only be started from Draft or Ready status. Current status: ' + prom.Status__c;
                errResult.errors.add(errResult.message);
                errResult.promotionId = promotionId;
                return errResult;
            }

            if (prom.Pipeline__c == null) {
                throw new PipelinePromotionExecutionException('Promotion has no Pipeline assigned.');
            }

            // Load active pipeline stages ordered by Stage_Order
            List<Stage__c> stages = [
                SELECT Id, Name, Stage_Type__c, Stage_Order__c, Target_Environment__c
                FROM Stage__c
                WHERE Pipeline__c = :prom.Pipeline__c
                  AND Status__c = 'Active'
                ORDER BY Stage_Order__c ASC
            ];

            if (stages.isEmpty()) {
                throw new PipelinePromotionExecutionException('No active stages found for the assigned Pipeline.');
            }

            // Set first stage and transition to Executing
            Stage__c firstStage = stages[0];
            prom.Current_Stage__c = firstStage.Id;
            update prom;
            PromotionRuntimeService.transitionPromotionStatus(promotionId, STATUS_EXECUTING);

            // Execute the first stage
            return executeCurrentStage(promotionId);

        } catch (PipelinePromotionExecutionException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to start promotion: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Executes the current stage based on its type.
     * Deploy/Validation: Creates Deployment_Request__c and delegates to DeploymentRuntimeService.
     * Approval: Transitions to Waiting For Approval and stops.
     * Notification/Build: Logs placeholder and advances to next stage.
     */
    public static EngineResult executeCurrentStage(Id promotionId) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            // Load promotion with current stage
            Promotion__c prom = [
                SELECT Id, Status__c, Pipeline__c, Source_Environment__c,
                       Target_Environment__c, Current_Stage__c,
                       Current_Deployment_Request__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            if (prom.Current_Stage__c == null) {
                throw new PipelinePromotionExecutionException('No current stage is set on the Promotion.');
            }

            // Load current stage details
            Stage__c currentStage = [
                SELECT Id, Name, Stage_Type__c, Stage_Order__c, Target_Environment__c
                FROM Stage__c
                WHERE Id = :prom.Current_Stage__c
                LIMIT 1
            ];

            String stageType = currentStage.Stage_Type__c;

            // Route based on stage type
            if (stageType == STAGE_TYPE_DEPLOY || stageType == STAGE_TYPE_VALIDATION) {
                return handleDeployStage(prom, currentStage, stageType);
            } else if (stageType == STAGE_TYPE_APPROVAL) {
                return handleApprovalStage(prom, currentStage);
            } else if (stageType == STAGE_TYPE_NOTIFICATION || stageType == STAGE_TYPE_BUILD) {
                return handlePassthroughStage(prom, currentStage);
            } else {
                throw new PipelinePromotionExecutionException('Unsupported Stage Type: ' + stageType);
            }

        } catch (PipelinePromotionExecutionException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to execute current stage: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Advances the promotion to the next pipeline stage.
     * If no more stages remain, transitions to Completed.
     */
    public static EngineResult advanceToNextStage(Id promotionId) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            Promotion__c prom = [
                SELECT Id, Status__c, Pipeline__c, Current_Stage__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            if (prom.Current_Stage__c == null) {
                throw new PipelinePromotionExecutionException('No current stage is set. Cannot advance.');
            }

            // Get the current stage order
            Stage__c currentStage = [
                SELECT Id, Stage_Order__c
                FROM Stage__c
                WHERE Id = :prom.Current_Stage__c
                LIMIT 1
            ];

            // Find the next active stage
            List<Stage__c> nextStages = [
                SELECT Id, Name, Stage_Type__c, Stage_Order__c, Target_Environment__c
                FROM Stage__c
                WHERE Pipeline__c = :prom.Pipeline__c
                  AND Status__c = 'Active'
                  AND Stage_Order__c > :currentStage.Stage_Order__c
                ORDER BY Stage_Order__c ASC
                LIMIT 1
            ];

            if (nextStages.isEmpty()) {
                // No more stages — pipeline is complete
                prom.Current_Stage__c = null;
                update prom;
                PromotionRuntimeService.transitionPromotionStatus(promotionId, STATUS_COMPLETED);

                EngineResult result = createDefaultResult();
                result.success = true;
                result.message = 'All pipeline stages completed. Promotion marked as Completed.';
                result.promotionId = promotionId;
                result.status = STATUS_COMPLETED;
                return result;
            }

            // Set next stage and continue execution
            Stage__c nextStage = nextStages[0];
            prom.Current_Stage__c = nextStage.Id;
            update prom;
            PromotionRuntimeService.transitionPromotionStatus(promotionId, STATUS_EXECUTING);

            // Execute the next stage
            return executeCurrentStage(promotionId);

        } catch (PipelinePromotionExecutionException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to advance to next stage: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Resumes a promotion that was Waiting For Approval.
     * Advances to the next stage in the pipeline.
     */
    public static EngineResult approvePromotion(Id promotionId) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            Promotion__c prom = [
                SELECT Id, Status__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            if (prom.Status__c != STATUS_WAITING_FOR_APPROVAL) {
                EngineResult errResult = createDefaultResult();
                errResult.message = 'Promotion is not in Waiting For Approval status. Current status: ' + prom.Status__c;
                errResult.errors.add(errResult.message);
                errResult.promotionId = promotionId;
                return errResult;
            }

            return advanceToNextStage(promotionId);

        } catch (PipelinePromotionExecutionException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to approve promotion: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Transitions a promotion to Failed status with a reason.
     */
    public static EngineResult failPromotion(Id promotionId, String reason) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            PromotionRuntimeService.transitionPromotionStatus(promotionId, STATUS_FAILED);

            EngineResult result = createDefaultResult();
            result.success = true;
            result.message = 'Promotion marked as Failed. Reason: ' + (String.isBlank(reason) ? 'No reason provided.' : reason);
            result.promotionId = promotionId;
            result.status = STATUS_FAILED;
            return result;

        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to fail promotion: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Transitions a promotion to Cancelled status.
     */
    public static EngineResult cancelPromotion(Id promotionId) {
        if (promotionId == null) {
            throw new PipelinePromotionExecutionException('Promotion ID cannot be null.');
        }

        try {
            Promotion__c prom = [
                SELECT Id, Status__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            if (prom.Status__c == STATUS_COMPLETED || prom.Status__c == STATUS_CANCELLED) {
                EngineResult errResult = createDefaultResult();
                errResult.message = 'Cannot cancel a promotion that is already ' + prom.Status__c + '.';
                errResult.errors.add(errResult.message);
                errResult.promotionId = promotionId;
                return errResult;
            }

            PromotionRuntimeService.transitionPromotionStatus(promotionId, STATUS_CANCELLED);

            EngineResult result = createDefaultResult();
            result.success = true;
            result.message = 'Promotion cancelled successfully.';
            result.promotionId = promotionId;
            result.status = STATUS_CANCELLED;
            return result;

        } catch (Exception ex) {
            throw new PipelinePromotionExecutionException('Failed to cancel promotion: ' + ex.getMessage(), ex);
        }
    }

    // ===========================
    // Private Stage Handlers
    // ===========================

    /**
     * Handles Deploy and Validation stage types.
     * Creates a Deployment_Request__c, updates the promotion tracking fields,
     * and delegates execution to DeploymentRuntimeService.startDeployment().
     */
    private static EngineResult handleDeployStage(Promotion__c prom, Stage__c stage, String stageType) {
        if (stage.Target_Environment__c == null) {
            throw new PipelinePromotionExecutionException(
                'Stage "' + stage.Name + '" has no Target Environment configured. Cannot create Deployment Request.'
            );
        }

        // Determine action type for DeploymentRuntimeService
        String actionType = (stageType == STAGE_TYPE_VALIDATION) ? 'Validate' : 'Deploy';

        // Create Deployment Request
        Deployment_Request__c dr = new Deployment_Request__c();
        dr.Pipeline__c = prom.Pipeline__c;
        dr.Source_Environment__c = prom.Source_Environment__c;
        dr.Target_Environment__c = stage.Target_Environment__c;
        dr.Promotion__c = prom.Id;
        dr.Status__c = 'Draft';
        insert dr;

        // Update promotion tracking
        prom.Current_Deployment_Request__c = dr.Id;
        update prom;

        // Delegate to DeploymentRuntimeService
        DeploymentRuntimeService.DeploymentResult deployResult =
            DeploymentRuntimeService.startDeployment(dr.Id, actionType);

        EngineResult result = createDefaultResult();
        result.success = true;
        result.message = 'Stage "' + stage.Name + '" (' + actionType + ') initiated. Deployment Request created and execution started.';
        result.promotionId = prom.Id;
        result.status = STATUS_EXECUTING;
        result.currentStageId = stage.Id;
        result.deploymentRequestId = dr.Id;
        return result;
    }

    /**
     * Handles Approval stage type.
     * Transitions the promotion to Waiting For Approval and stops execution.
     */
    private static EngineResult handleApprovalStage(Promotion__c prom, Stage__c stage) {
        PromotionRuntimeService.transitionPromotionStatus(prom.Id, STATUS_WAITING_FOR_APPROVAL);

        EngineResult result = createDefaultResult();
        result.success = true;
        result.message = 'Stage "' + stage.Name + '" requires approval. Promotion paused at Waiting For Approval.';
        result.promotionId = prom.Id;
        result.status = STATUS_WAITING_FOR_APPROVAL;
        result.currentStageId = stage.Id;
        return result;
    }

    /**
     * Handles Notification and Build stage types.
     * These are passthrough stages that auto-advance to the next stage.
     */
    private static EngineResult handlePassthroughStage(Promotion__c prom, Stage__c stage) {
        // Placeholder: future phases will add notification/build logic here.
        // For Phase-1, these stages auto-advance.
        return advanceToNextStage(prom.Id);
    }
}