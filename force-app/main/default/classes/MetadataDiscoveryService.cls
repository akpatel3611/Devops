public with sharing class MetadataDiscoveryService {

    public class MetadataTypeOption {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;
    }

    public class MetadataComponent {

        @AuraEnabled
        public String name;

        @AuraEnabled
        public String type;
    }

    @AuraEnabled(cacheable=true)
    public static String getSourceOrgDomain(
        Id credentialId
    ){

        return
            MetadataAuthenticationService.getOrgDomainFromSfdxUrl(
                credentialId
            );
    }

    @AuraEnabled(cacheable=true)
public static String getRawSfdxAuthUrl(
    Id credentialId
){

    return
        MetadataAuthenticationService.getSfdxAuthUrl(
            credentialId
        );
}

@AuraEnabled(cacheable=true)
public static String getEnvironmentMetadataSource(
    Id credentialId
){

    return
        MetadataAuthenticationService.getOrgDomainFromSfdxUrl(
            credentialId
        );
}

@AuraEnabled(cacheable=true)
public static String getSourceEnvironmentStatus(
    Id environmentId
){

    return
        ExternalMetadataController.validateSourceEnvironment(
                environmentId
            );
}

@AuraEnabled(cacheable=true)
public static String getInstanceUrlByEnvironment(
    Id environmentId
){

    DeploymentCredentialController.CredentialWrapper
        credential =

        DeploymentCredentialController.getCredentialByEnvironment(
                environmentId
            );

    return
        credential.instanceUrl;
}
}