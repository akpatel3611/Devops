/**
 * Coordinator service for handling approval lifecycle transitions on Promotion records.
 * Decouples approval validations (checking deployment status and results) from the routing engine.
 * Delegates actual stage navigation and DML execution to PipelinePromotionExecutionEngine.
 */
public with sharing class PromotionApprovalRuntimeService {

    public class PromotionApprovalException extends Exception {}

    // Deployment Request Status Constants (to avoid raw hardcoded values inside business logic)
    private static final String DEPLOYMENT_STATUS_COMPLETED = 'Completed';
    private static final String DEPLOYMENT_STATUS_VALIDATED = 'Validated';

    // DTO for approval operation results
    public class ApprovalResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id promotionId {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    private static ApprovalResult createFailedResult(String errorMsg) {
        ApprovalResult res = new ApprovalResult();
        res.success = false;
        res.message = errorMsg;
        res.errors = new List<String>{ errorMsg };
        return res;
    }

    /**
     * Holder class for the validation results to ensure clean reuse between methods.
     */
    private class ValidationHolder {
        public Boolean isValid;
        public String errorMessage;
    }

    /**
     * Reusable validation helper that performs complete stage-execution precondition checks.
     */
    private static ValidationHolder validatePromotionForStageExecution(Id promotionId) {
        ValidationHolder holder = new ValidationHolder();
        holder.isValid = true;

        List<Promotion__c> promotions = [
            SELECT Id, Status__c, Current_Stage__c, Current_Deployment_Request__c
            FROM Promotion__c
            WHERE Id = :promotionId
            LIMIT 1
        ];

        if (promotions.isEmpty()) {
            holder.isValid = false;
            holder.errorMessage = 'Promotion record not found for ID: ' + promotionId;
            return holder;
        }

        Promotion__c prom = promotions[0];

        if (prom.Status__c != PromotionRuntimeService.STATUS_WAITING_FOR_APPROVAL && 
            prom.Status__c != PromotionRuntimeService.STATUS_EXECUTING) {
            holder.isValid = false;
            holder.errorMessage = 'Promotion status is not valid for stage execution. Current status: ' + prom.Status__c;
            return holder;
        }

        if (prom.Current_Stage__c == null) {
            holder.isValid = false;
            holder.errorMessage = 'Promotion has no current stage configured.';
            return holder;
        }

        if (prom.Current_Deployment_Request__c == null) {
            holder.isValid = false;
            holder.errorMessage = 'No active deployment request exists for the current stage.';
            return holder;
        }

        List<Deployment_Request__c> dreqs = [
            SELECT Id, Status__c
            FROM Deployment_Request__c
            WHERE Id = :prom.Current_Deployment_Request__c
            LIMIT 1
        ];

        if (dreqs.isEmpty()) {
            holder.isValid = false;
            holder.errorMessage = 'Deployment Request record not found.';
            return holder;
        }

        Deployment_Request__c dreq = dreqs[0];

        // Validate that the current deployment request completed successfully
        if (dreq.Status__c != DEPLOYMENT_STATUS_COMPLETED && dreq.Status__c != DEPLOYMENT_STATUS_VALIDATED) {
            holder.isValid = false;
            holder.errorMessage = 'Current deployment request has not completed successfully. Status: ' + dreq.Status__c;
            return holder;
        }

        return holder;
    }

    /**
     * Approves the current stage of the Promotion, validating that the deployment completed successfully,
     * and advances the Promotion to the next stage.
     */
    public static ApprovalResult approvePromotion(Id promotionId) {
        if (promotionId == null) {
            return createFailedResult('Promotion ID cannot be null.');
        }

        try {
            ValidationHolder valHolder = validatePromotionForStageExecution(promotionId);
            if (!valHolder.isValid) {
                return createFailedResult(valHolder.errorMessage);
            }

            // All validations passed. Delegate navigation to the engine
            PipelinePromotionExecutionEngine.EngineResult engRes = 
                PipelinePromotionExecutionEngine.advanceToNextStage(promotionId);

            ApprovalResult result = new ApprovalResult();
            result.success = engRes.success;
            result.message = engRes.message;
            result.promotionId = engRes.promotionId;
            result.status = engRes.status;
            result.errors = engRes.errors;
            return result;

        } catch (Exception ex) {
            return createFailedResult('Failed to approve promotion: ' + ex.getMessage());
        }
    }

    /**
     * Rejects the promotion, halting execution and setting status to Failed.
     */
    public static ApprovalResult rejectPromotion(Id promotionId, String reason) {
        if (promotionId == null) {
            return createFailedResult('Promotion ID cannot be null.');
        }

        try {
            List<Promotion__c> promotions = [
                SELECT Id, Status__c
                FROM Promotion__c
                WHERE Id = :promotionId
                LIMIT 1
            ];

            if (promotions.isEmpty()) {
                return createFailedResult('Promotion record not found for ID: ' + promotionId);
            }

            Promotion__c prom = promotions[0];

            if (prom.Status__c != PromotionRuntimeService.STATUS_WAITING_FOR_APPROVAL && 
                prom.Status__c != PromotionRuntimeService.STATUS_EXECUTING) {
                return createFailedResult('Promotion status is not valid for rejection. Current status: ' + prom.Status__c);
            }

            String rejectReason = 'Rejected: ' + (String.isBlank(reason) ? 'No reason provided.' : reason);
            PipelinePromotionExecutionEngine.EngineResult engRes = 
                PipelinePromotionExecutionEngine.failPromotion(promotionId, rejectReason);

            ApprovalResult result = new ApprovalResult();
            result.success = engRes.success;
            result.message = engRes.message;
            result.promotionId = engRes.promotionId;
            result.status = engRes.status;
            result.errors = engRes.errors;
            return result;

        } catch (Exception ex) {
            return createFailedResult('Failed to reject promotion: ' + ex.getMessage());
        }
    }

    /**
     * Resumes a promotion that was paused at Waiting For Approval.
     */
    public static ApprovalResult resumePromotion(Id promotionId) {
        if (promotionId == null) {
            return createFailedResult('Promotion ID cannot be null.');
        }

        try {
            // Verify that the promotion is paused and deployment has completed successfully
            ValidationHolder valHolder = validatePromotionForStageExecution(promotionId);
            if (!valHolder.isValid) {
                return createFailedResult(valHolder.errorMessage);
            }

            PipelinePromotionExecutionEngine.EngineResult engRes = 
                PipelinePromotionExecutionEngine.advanceToNextStage(promotionId);

            ApprovalResult result = new ApprovalResult();
            result.success = engRes.success;
            result.message = engRes.message;
            result.promotionId = engRes.promotionId;
            result.status = engRes.status;
            result.errors = engRes.errors;
            return result;

        } catch (Exception ex) {
            return createFailedResult('Failed to resume promotion: ' + ex.getMessage());
        }
    }

    /**
     * Cancels the promotion, stopping execution.
     */
    public static ApprovalResult cancelPromotion(Id promotionId) {
        if (promotionId == null) {
            return createFailedResult('Promotion ID cannot be null.');
        }

        try {
            PipelinePromotionExecutionEngine.EngineResult engRes = 
                PipelinePromotionExecutionEngine.cancelPromotion(promotionId);

            ApprovalResult result = new ApprovalResult();
            result.success = engRes.success;
            result.message = engRes.message;
            result.promotionId = engRes.promotionId;
            result.status = engRes.status;
            result.errors = engRes.errors;
            return result;

        } catch (Exception ex) {
            return createFailedResult('Failed to cancel promotion: ' + ex.getMessage());
        }
    }
}