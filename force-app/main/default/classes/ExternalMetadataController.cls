public with sharing class ExternalMetadataController {

    @AuraEnabled(cacheable=true)
    public static String validateSourceEnvironment(
        Id environmentId
    ){
        System.debug(LoggingLevel.INFO, '[ExternalMetadataController.validateSourceEnvironment] START - environmentId: ' + environmentId);
        if (environmentId == null) {
            System.debug(LoggingLevel.WARN, '[ExternalMetadataController.validateSourceEnvironment] Warning: environmentId is null.');
            return 'CREDENTIAL_NOT_FOUND';
        }

        try {
            List<Credentials__c> credentials = [
                SELECT Id,
                       Name,
                       Instance_URL__c,
                       SFDX_Auth_URL__c
                FROM Credentials__c
                WHERE Deployment_Environment__c = :environmentId
                LIMIT 1
            ];
        
            if (credentials.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[ExternalMetadataController.validateSourceEnvironment] Warning: No credentials record found for environment ID: ' + environmentId);
                return 'CREDENTIAL_NOT_FOUND';
            }
        
            Credentials__c credential = credentials[0];
            System.debug(LoggingLevel.DEBUG, '[ExternalMetadataController.validateSourceEnvironment] Found Credential: ' + credential.Name + ' | HasInstanceUrl: ' + String.isNotBlank(credential.Instance_URL__c) + ' | HasAuthUrl: ' + String.isNotBlank(credential.SFDX_Auth_URL__c));
        
            if (String.isBlank(credential.Instance_URL__c)) {
                System.debug(LoggingLevel.WARN, '[ExternalMetadataController.validateSourceEnvironment] INSTANCE_URL_MISSING for credential: ' + credential.Name);
                return 'INSTANCE_URL_MISSING';
            }
        
            if (String.isBlank(credential.SFDX_Auth_URL__c)) {
                System.debug(LoggingLevel.WARN, '[ExternalMetadataController.validateSourceEnvironment] SFDX_AUTH_URL_MISSING for credential: ' + credential.Name);
                return 'SFDX_AUTH_URL_MISSING';
            }
        
            System.debug(LoggingLevel.INFO, '[ExternalMetadataController.validateSourceEnvironment] SUCCESS - Environment state is READY.');
            return 'READY';
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[ExternalMetadataController.validateSourceEnvironment] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to validate environment credentials: ' + ex.getMessage());
        }
    }
}