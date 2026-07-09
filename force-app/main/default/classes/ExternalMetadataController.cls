public with sharing class ExternalMetadataController {

    @AuraEnabled(cacheable=true)
    public static String validateSourceEnvironment(
        Id environmentId
    ){
    
        List<Credentials__c> credentials = [
    
            SELECT Id,
                   Name,
                   Instance_URL__c,
                   SFDX_Auth_URL__c
    
            FROM Credentials__c
    
            WHERE Deployment_Environment__c =
                  :environmentId
    
            LIMIT 1
        ];
    
        if(
            credentials.isEmpty()
        ){
            return 'CREDENTIAL_NOT_FOUND';
        }
    
        Credentials__c credential =
            credentials[0];
    
        if(
            String.isBlank(
                credential.Instance_URL__c
            )
        ){
            return 'INSTANCE_URL_MISSING';
        }
    
        if(
            String.isBlank(
                credential.SFDX_Auth_URL__c
            )
        ){
            return 'SFDX_AUTH_URL_MISSING';
        }
    
        return 'READY';
    }
}