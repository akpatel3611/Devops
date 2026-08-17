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
        System.debug(LoggingLevel.INFO, '[DeploymentValidationController.validateDeployment] START - SourceEnv: ' + sourceEnvironmentId + ' | TargetEnv: ' + targetEnvironmentId + ' | MetadataType: ' + metadataType + ' | Components Count: ' + (componentNames != null ? componentNames.size() : 0));
        List<ValidationResult> results = new List<ValidationResult>();

        if (sourceEnvironmentId == null || targetEnvironmentId == null) {
            System.debug(LoggingLevel.WARN, '[DeploymentValidationController.validateDeployment] Warning: Missing Source or Target environment ID.');
            throw new AuraHandledException('Source and Target environments are required.');
        }

        List<Deployment_Request__c> reqs = [
            SELECT Id FROM Deployment_Request__c
            WHERE Source_Environment__c = :sourceEnvironmentId
              AND Target_Environment__c = :targetEnvironmentId
              AND Status__c IN ('Draft', 'Failed', 'Validated')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (reqs.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[DeploymentValidationController.validateDeployment] Warning: No active Draft deployment request found.');
            throw new AuraHandledException('No active Draft deployment request found for the selected environments. Please Save your selections first.');
        }

        System.debug(LoggingLevel.DEBUG, '[DeploymentValidationController.validateDeployment] Found Deployment Request ID: ' + reqs[0].Id + '. Triggering validation deployment...');

        try {
            DeploymentRuntimeService.startDeployment(reqs[0].Id, 'Validate');
            
            ValidationResult vRes = new ValidationResult(
                'ValidationRequest',
                'PENDING',
                String.valueOf(reqs[0].Id)
            );
            results.add(vRes);
            System.debug(LoggingLevel.INFO, '[DeploymentValidationController.validateDeployment] SUCCESS - Triggered validation job ID: ' + reqs[0].Id);
            return results;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DeploymentValidationController.validateDeployment] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());
        }
    }
}