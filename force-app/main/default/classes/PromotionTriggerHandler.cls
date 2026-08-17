public with sharing class PromotionTriggerHandler {
    
    public static Boolean isExecuting = false;

    public static void handleAfterInsert(List<Promotion__c> newPromotions) {
        if (isExecuting) return;
        isExecuting = true;
        
        for (Promotion__c promo : newPromotions) {
            try {
                // Auto-start is disabled as per user requirements. 
                // Promotion should remain in Draft/Ready and not automatically execute.
                // PipelinePromotionExecutionEngine.startPromotion(promo.Id);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to auto-start promotion ' + promo.Id + ': ' + ex.getMessage());
            }
        }
        
        isExecuting = false;
    }
}