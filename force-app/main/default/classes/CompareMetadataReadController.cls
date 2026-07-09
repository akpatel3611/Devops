public with sharing class CompareMetadataReadController {

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

        for(
            String componentName :
            componentNames
        ){

            try{

                MetadataService.IReadResult sourceRead =

                    sourceService.readMetadata(

                        metadataType,

                        new String[]{
                            componentName
                        }
                    );

                MetadataService.IReadResult targetRead =

                    targetService.readMetadata(

                        metadataType,

                        new String[]{
                            componentName
                        }
                    );

                String sourceJson =
                    JSON.serialize(
                        sourceRead
                    );

                String targetJson =
                    JSON.serialize(
                        targetRead
                    );

                if(
                    sourceJson ==
                    targetJson
                ){

                    results.add(

                        new CompareResult(

                            componentName,

                            'SAME'
                        )
                    );
                }
                else{

                    results.add(

                        new CompareResult(

                            componentName,

                            'CHANGED'
                        )
                    );
                }
            }
            catch(Exception ex){

                System.debug(
                    'COMPARE ERROR = ' +
                    ex.getMessage()
                );
                        
                System.debug(
                    'COMPARE STACK = ' +
                    ex.getStackTraceString()
                );
                        
                results.add(
                        
                    new CompareResult(
                        
                        componentName,
                        
                        'ERROR'
                    )
                );
            }
        }

        return results;
    }
}