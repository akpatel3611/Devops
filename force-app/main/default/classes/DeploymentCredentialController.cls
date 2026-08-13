public without sharing class DeploymentCredentialController {

    public class CredentialWrapper {

        @AuraEnabled
        public String credentialId;

        @AuraEnabled
        public String credentialName;

        @AuraEnabled
        public String instanceUrl;

        @AuraEnabled
        public String sfdxAuthUrl;
    }

    @AuraEnabled(cacheable=true)
    public static CredentialWrapper getCredentialByEnvironment(
        Id environmentId
    ){
        System.debug(LoggingLevel.INFO, '[DeploymentCredentialController.getCredentialByEnvironment] START - environmentId: ' + environmentId);
        if (environmentId == null) {
            System.debug(LoggingLevel.WARN, '[DeploymentCredentialController.getCredentialByEnvironment] Warning: environmentId is null.');
            return new CredentialWrapper();
        }

        try {
            CredentialWrapper result = new CredentialWrapper();

            List<Credentials__c> credList = [
                SELECT Id, Name, Instance_URL__c, SFDX_Auth_URL__c
                FROM Credentials__c
                WHERE Deployment_Environment__c = :environmentId
                  AND (NOT Instance_URL__c LIKE '%github.com%')
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];

            if (credList.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, '[DeploymentCredentialController.getCredentialByEnvironment] Fallback: Querying all credentials for env ID: ' + environmentId);
                credList = [
                    SELECT Id, Name, Instance_URL__c, SFDX_Auth_URL__c
                    FROM Credentials__c
                    WHERE Deployment_Environment__c = :environmentId
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];
            }

            if (!credList.isEmpty()) {
                Credentials__c credential = credList[0];
                result.credentialId = credential.Id;
                result.credentialName = credential.Name;
                result.instanceUrl = credential.Instance_URL__c;
                result.sfdxAuthUrl = credential.SFDX_Auth_URL__c;
                System.debug(LoggingLevel.INFO, '[DeploymentCredentialController.getCredentialByEnvironment] SUCCESS - Resolved credential: ' + credential.Name + ' | ID: ' + credential.Id);
            } else {
                System.debug(LoggingLevel.WARN, '[DeploymentCredentialController.getCredentialByEnvironment] Warning: No credentials found for environment ID: ' + environmentId);
            }

            return result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DeploymentCredentialController.getCredentialByEnvironment] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to load credential: ' + ex.getMessage());
        }
    }
}