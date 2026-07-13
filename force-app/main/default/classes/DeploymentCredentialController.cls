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

        CredentialWrapper result =
            new CredentialWrapper();

        Credentials__c credential = [

            SELECT Id,
                   Name,
                   Instance_URL__c,
                   SFDX_Auth_URL__c

            FROM Credentials__c

            WHERE Deployment_Environment__c = :environmentId

            LIMIT 1
        ];

        result.credentialId = credential.Id;
        result.credentialName = credential.Name;
        result.instanceUrl = credential.Instance_URL__c;
        result.sfdxAuthUrl = credential.SFDX_Auth_URL__c;

        return result;
    }
}