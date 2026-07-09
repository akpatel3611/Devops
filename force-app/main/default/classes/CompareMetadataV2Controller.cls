public with sharing class CompareMetadataV2Controller {

    public class CompareResult {

        @AuraEnabled
        public String componentName;

        @AuraEnabled
        public String status;

        public CompareResult(
            String componentName,
            String status
        ){
            this.componentName =
                componentName;

            this.status =
                status;
        }
    }

    @AuraEnabled
    public static List<CompareResult> compareMetadata(

        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        String metadataType,
        List<String> componentNames
    ){

        List<CompareResult> results =
            new List<CompareResult>();

        if(
            componentNames == null ||
            componentNames.isEmpty()
        ){
            return results;
        }

        DeploymentCredentialController.CredentialWrapper sourceCredential =

            DeploymentCredentialController.getCredentialByEnvironment(
                sourceEnvironmentId
            );

        DeploymentCredentialController.CredentialWrapper targetCredential =

            DeploymentCredentialController.getCredentialByEnvironment(
                targetEnvironmentId
            );

        MetadataAuthenticationService.OAuthTokenResponse sourceToken =

            MetadataAuthenticationService.generateAccessToken(
                sourceCredential.credentialId
            );

        MetadataAuthenticationService.OAuthTokenResponse targetToken =

            MetadataAuthenticationService.generateAccessToken(
                targetCredential.credentialId
            );

        MetadataService.MetadataPort sourceService =
            new MetadataService.MetadataPort();

        sourceService.endpoint_x =
            sourceToken.instanceUrl +
            '/services/Soap/m/64.0';

        MetadataService.SessionHeader_element sourceHeader =
            new MetadataService.SessionHeader_element();

        sourceHeader.sessionId =
            sourceToken.accessToken;

        sourceService.SessionHeader =
            sourceHeader;

        MetadataService.MetadataPort targetService =
            new MetadataService.MetadataPort();

        targetService.endpoint_x =
            targetToken.instanceUrl +
            '/services/Soap/m/64.0';

        MetadataService.SessionHeader_element targetHeader =
            new MetadataService.SessionHeader_element();

        targetHeader.sessionId =
            targetToken.accessToken;

        targetService.SessionHeader =
            targetHeader;

        MetadataService.ListMetadataQuery query =
            new MetadataService.ListMetadataQuery();

        query.type_x =
            metadataType;

        MetadataService.FileProperties[] targetFiles =

            targetService.listMetadata(

                new MetadataService.ListMetadataQuery[]{
                    query
                },
                64
            );

        Set<String> targetComponents =
            new Set<String>();

        if(
            targetFiles != null
        ){

            for(
                MetadataService.FileProperties file :
                targetFiles
            ){

                if(
                    String.isNotBlank(
                        file.fullName
                    )
                ){

                    targetComponents.add(
                        file.fullName
                    );
                }
            }
        }

        for(
            String component :
            componentNames
        ){

            if(
                !targetComponents.contains(
                    component
                )
            ){

                results.add(

                    new CompareResult(

                        component,

                        'NEW'
                    )
                );

                continue;
            }

            results.add(

                new CompareResult(

                    component,

                    'SAME'
                )
            );
        }

        return results;
    }
}