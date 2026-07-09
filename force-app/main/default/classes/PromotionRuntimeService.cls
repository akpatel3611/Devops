/**
 * Service class that acts as the single unified entry point for orchestrating Promotion configurations.
 * Manages promotion creation, updates, lifecycle validation, status changes, and archiving.
 * Excludes deployment, SOAP connection, callouts, and approvals orchestration.
 */
public with sharing class PromotionRuntimeService {

    public class PromotionRuntimeServiceException extends Exception {}

    // Lifecycle Status Constants
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_READY = 'Ready';
    public static final String STATUS_EXECUTING = 'Executing';
    public static final String STATUS_WAITING_FOR_APPROVAL = 'Waiting For Approval';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_CANCELLED = 'Cancelled';

    // DTO class for promotion action responses
    public class PromotionResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id promotionId {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO class for validation results
    public class ValidationResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    /**
     * Helper to instantiate a default PromotionResult response.
     */
    private static PromotionResult createDefaultResult() {
        PromotionResult result = new PromotionResult();
        result.success = false;
        result.errors = new List<String>();
        return result;
    }

    /**
     * Registers a new promotion record in Draft status after validation.
     */
    public static PromotionResult createPromotion(
        String name,
        Id pipelineId,
        Id sourceEnvId,
        Id targetEnvId,
        String description,
        Id releaseId
    ) {
        ValidationResult valRes = validateCreate(name, pipelineId, sourceEnvId, targetEnvId);
        if (!valRes.success) {
            PromotionResult errResult = createDefaultResult();
            errResult.message = valRes.message;
            errResult.errors = valRes.errors;
            return errResult;
        }

        // Verify duplicate promotion does not exist (Change 1)
        List<Promotion__c> duplicates = [
            SELECT Id 
            FROM Promotion__c 
            WHERE (Promotion_Name__c = :name)
               OR (Pipeline__c = :pipelineId 
                   AND Source_Environment__c = :sourceEnvId 
                   AND Target_Environment__c = :targetEnvId 
                   AND Release__c = :releaseId
                   AND Status__c NOT IN ('Completed', 'Failed', 'Cancelled'))
            LIMIT 1
        ];
        if (!duplicates.isEmpty()) {
            PromotionResult errResult = createDefaultResult();
            errResult.message = 'A duplicate promotion already exists with the same name or active environment routing.';
            errResult.errors.add('A duplicate promotion already exists with the same name or active environment routing.');
            return errResult;
        }

        try {
            Promotion__c prom = new Promotion__c();
            prom.Promotion_Name__c = name;
            prom.Pipeline__c = pipelineId;
            prom.Source_Environment__c = sourceEnvId;
            prom.Target_Environment__c = targetEnvId;
            prom.Description__c = description;
            prom.Release__c = releaseId;
            prom.Status__c = STATUS_DRAFT;
            prom.Promotion_Date__c = System.now();
            
            insert prom;

            PromotionResult result = createDefaultResult();
            result.success = true;
            result.message = 'Promotion registered successfully in Draft status.';
            result.promotionId = prom.Id;
            result.status = STATUS_DRAFT;
            return result;
        } catch (Exception ex) {
            throw new PromotionRuntimeServiceException('Failed to create promotion: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Updates configuration properties for an existing promotion record.
     * Does not automatically modify the lifecycle status.
     */
    public static PromotionResult updatePromotion(
        Id promotionId,
        String name,
        Id pipelineId,
        Id sourceEnvId,
        Id targetEnvId,
        String description,
        Id releaseId
    ) {
        if (promotionId == null) {
            throw new PromotionRuntimeServiceException('Promotion ID cannot be null.');
        }

        ValidationResult valRes = validateUpdate(promotionId, name, pipelineId, sourceEnvId, targetEnvId);
        if (!valRes.success) {
            PromotionResult errResult = createDefaultResult();
            errResult.message = valRes.message;
            errResult.errors = valRes.errors;
            errResult.promotionId = promotionId;
            return errResult;
        }

        // Verify that the Promotion record actually exists (Change 2)
        List<Promotion__c> existing = [
            SELECT Id 
            FROM Promotion__c 
            WHERE Id = :promotionId 
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            PromotionResult errResult = createDefaultResult();
            errResult.message = 'The Promotion record with ID ' + promotionId + ' does not exist.';
            errResult.errors.add('The Promotion record with ID ' + promotionId + ' does not exist.');
            errResult.promotionId = promotionId;
            return errResult;
        }

        try {
            Promotion__c prom = new Promotion__c(Id = promotionId);
            prom.Promotion_Name__c = name;
            prom.Pipeline__c = pipelineId;
            prom.Source_Environment__c = sourceEnvId;
            prom.Target_Environment__c = targetEnvId;
            prom.Description__c = description;
            prom.Release__c = releaseId;
            
            update prom;

            PromotionResult result = createDefaultResult();
            result.success = true;
            result.message = 'Promotion updated successfully.';
            result.promotionId = promotionId;
            return result;
        } catch (Exception ex) {
            throw new PromotionRuntimeServiceException('Failed to update promotion: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Performs validations required during promotion creation.
     */
    private static ValidationResult validateCreate(
        String name,
        Id pipelineId,
        Id sourceEnvId,
        Id targetEnvId
    ) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (String.isBlank(name)) {
            result.errors.add('Promotion Name is mandatory.');
            result.success = false;
        }
        if (pipelineId == null) {
            result.errors.add('Pipeline is mandatory.');
            result.success = false;
        }
        if (sourceEnvId == null) {
            result.errors.add('Source Environment is mandatory.');
            result.success = false;
        }
        if (targetEnvId == null) {
            result.errors.add('Target Environment is mandatory.');
            result.success = false;
        }
        if (sourceEnvId != null && targetEnvId != null && sourceEnvId == targetEnvId) {
            result.errors.add('Source and Target environments cannot be the same.');
            result.success = false;
        }

        if (!result.success) {
            result.message = 'Validation failed for promotion creation.';
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Performs validations required during promotion updates.
     */
    private static ValidationResult validateUpdate(
        Id promotionId,
        String name,
        Id pipelineId,
        Id sourceEnvId,
        Id targetEnvId
    ) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (promotionId == null) {
            result.errors.add('Promotion ID is mandatory.');
            result.success = false;
        }
        if (String.isBlank(name)) {
            result.errors.add('Promotion Name is mandatory.');
            result.success = false;
        }
        if (pipelineId == null) {
            result.errors.add('Pipeline is mandatory.');
            result.success = false;
        }
        if (sourceEnvId == null) {
            result.errors.add('Source Environment is mandatory.');
            result.success = false;
        }
        if (targetEnvId == null) {
            result.errors.add('Target Environment is mandatory.');
            result.success = false;
        }
        if (sourceEnvId != null && targetEnvId != null && sourceEnvId == targetEnvId) {
            result.errors.add('Source and Target environments cannot be the same.');
            result.success = false;
        }

        if (!result.success) {
            result.message = 'Validation failed for promotion update.';
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Validates promotion lifecycle transitions.
     * Allowed flow: Draft -> Ready / Executing / Cancelled; Ready -> Executing / Cancelled;
     * Executing -> Waiting For Approval / Completed / Failed / Cancelled;
     * Waiting For Approval -> Executing / Failed / Cancelled.
     */
    public static ValidationResult validateLifecycleTransition(String currentStatus, String targetStatus) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (currentStatus == targetStatus) {
            result.message = 'Validation passed.';
            return result;
        }

        Boolean isValid = false;
        if (currentStatus == STATUS_DRAFT) {
            if (targetStatus == STATUS_READY || targetStatus == STATUS_EXECUTING || targetStatus == STATUS_CANCELLED) {
                isValid = true;
            }
        } else if (currentStatus == STATUS_READY) {
            if (targetStatus == STATUS_EXECUTING || targetStatus == STATUS_CANCELLED) {
                isValid = true;
            }
        } else if (currentStatus == STATUS_EXECUTING) {
            if (targetStatus == STATUS_WAITING_FOR_APPROVAL || targetStatus == STATUS_COMPLETED || targetStatus == STATUS_FAILED || targetStatus == STATUS_CANCELLED) {
                isValid = true;
            }
        } else if (currentStatus == STATUS_WAITING_FOR_APPROVAL) {
            if (targetStatus == STATUS_EXECUTING || targetStatus == STATUS_FAILED || targetStatus == STATUS_CANCELLED) {
                isValid = true;
            }
        }

        if (!isValid) {
            result.success = false;
            String errMsg = 'Invalid status transition from ' + currentStatus + ' to ' + targetStatus;
            result.errors.add(errMsg);
            result.message = errMsg;
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Core reusable state transition handler.
     */
    public static PromotionResult transitionPromotionStatus(Id promotionId, String targetStatus) {
        if (promotionId == null) {
            throw new PromotionRuntimeServiceException('Promotion ID cannot be null.');
        }

        try {
            Promotion__c prom = [
                SELECT Id, Status__c 
                FROM Promotion__c 
                WHERE Id = :promotionId 
                LIMIT 1
            ];

            ValidationResult valRes = validateLifecycleTransition(prom.Status__c, targetStatus);
            if (!valRes.success) {
                throw new PromotionRuntimeServiceException(valRes.message);
            }

            prom.Status__c = targetStatus;
            update prom;

            PromotionResult result = createDefaultResult();
            result.success = true;
            result.message = 'Promotion status transitioned to ' + targetStatus + ' successfully.';
            result.promotionId = promotionId;
            result.status = targetStatus;
            return result;
        } catch (Exception ex) {
            throw new PromotionRuntimeServiceException('Failed to transition promotion status: ' + ex.getMessage(), ex);
        }
    }
}