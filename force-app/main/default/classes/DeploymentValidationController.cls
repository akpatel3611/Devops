public with sharing class DeploymentValidationController {

    public class ValidationResult {

        @AuraEnabled
        public String checkName;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String message;

        public ValidationResult(
            String checkName,
            String status,
            String message
        ){
            this.checkName = checkName;
            this.status = status;
            this.message = message;
        }
    }

    @AuraEnabled
    public static List<ValidationResult> validateDeployment(
        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        String metadataType,
        List<String> componentNames
    ){
        List<ValidationResult> results = new List<ValidationResult>();

        if (sourceEnvironmentId == null || targetEnvironmentId == null) {
            throw new AuraHandledException('Source and Target environments are required.');
        }

        List<Deployment_Request__c> reqs = [
            SELECT Id FROM Deployment_Request__c
            WHERE Source_Environment__c = :sourceEnvironmentId
              AND Target_Environment__c = :targetEnvironmentId
              AND Status__c = 'Draft'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (reqs.isEmpty()) {
            throw new AuraHandledException('No active Draft deployment request found for the selected environments. Please Save your selections first.');
        }

        try {
            DeploymentRuntimeService.startDeployment(reqs[0].Id, 'Validate');
            
            results.add(new ValidationResult(
                'ValidationRequest',
                'PENDING',
                String.valueOf(reqs[0].Id)
            ));
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }

        return results;
    }
}