public with sharing class MetadataExplorerController {

    public class MetadataItem {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public MetadataItem(
            String label,
            String value
        ){
            this.label = label;
            this.value = value;
        }
    }

    public class MetadataTypeWrapper{

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public MetadataTypeWrapper(
            String label,
            String value
        ){
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataTypeWrapper> getMetadataTypes(
        Id sourceEnvironmentId
    ){

        List<MetadataTypeWrapper> results =
            new List<MetadataTypeWrapper>();

        try{

            DeploymentCredentialController.CredentialWrapper credential =

                DeploymentCredentialController.getCredentialByEnvironment(
                        sourceEnvironmentId
                    );

            MetadataAuthenticationService.OAuthTokenResponse token =

                MetadataAuthenticationService.generateAccessToken(
                        credential.credentialId
                    );

            MetadataService.MetadataPort service =
                new MetadataService.MetadataPort();

            service.endpoint_x =

                token.instanceUrl +

                '/services/Soap/m/64.0';

            MetadataService.SessionHeader_element
                sessionHeader =

                new MetadataService.SessionHeader_element();

            sessionHeader.sessionId =
                token.accessToken;

            service.SessionHeader =
                sessionHeader;

            MetadataService.DescribeMetadataResult
                describeResult =

                service.describeMetadata(
                    Double.valueOf('64')
                );

            if(
                describeResult != null &&
                describeResult.metadataObjects != null
            ){

                for(
                    MetadataService.DescribeMetadataObject obj :

                    describeResult.metadataObjects
                ){

                    if(
                        String.isNotBlank(
                            obj.xmlName
                        )
                    ){

                        results.add(

                            new MetadataTypeWrapper(

                                obj.xmlName,

                                obj.xmlName
                            )
                        );
                    }
                }
            }

            // results.sort(new MetadataTypeSorter());

            return results;

        }
        catch(Exception ex){

            throw new AuraHandledException(
                ex.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataItem> getMetadata(
        String componentType,
        Id sourceEnvironmentId
    ){

        List<MetadataItem> results =
            new List<MetadataItem>();

        try{

            DeploymentCredentialController.CredentialWrapper credential =

                DeploymentCredentialController.getCredentialByEnvironment(
                        sourceEnvironmentId
                    );

            if(
                credential == null ||
                String.isBlank(
                    credential.credentialId
                )
            ){
                throw new AuraHandledException(
                    'Credential not found.'
                );
            }

            MetadataAuthenticationService.OAuthTokenResponse token =

                MetadataAuthenticationService.generateAccessToken(
                        credential.credentialId
                    );

            MetadataService.MetadataPort service =
                new MetadataService.MetadataPort();

            service.endpoint_x = token.instanceUrl + '/services/Soap/m/64.0';

            MetadataService.SessionHeader_element sessionHeader = new MetadataService.SessionHeader_element();

            sessionHeader.sessionId =
                token.accessToken;

            service.SessionHeader =
                sessionHeader;

            MetadataService.ListMetadataQuery query =
                new MetadataService.ListMetadataQuery();

            query.type_x =
                componentType;

            MetadataService.ListMetadataQuery[] queries =

                new MetadataService.ListMetadataQuery[]{
                        query
                    };

            MetadataService.FileProperties[] files =

                service.listMetadata(

                    queries,

                    Double.valueOf('64')
                );

            if(
                files != null
            ){

                for(
                    MetadataService.FileProperties file :

                    files
                ){

                    if(
                        String.isNotBlank(
                            file.fullName
                        )
                    ){

                        results.add(

                            new MetadataItem(

                                file.fullName,

                                file.fullName
                            )
                        );
                    }
                }
            }

            return results;
        } catch(Exception ex){

            throw new AuraHandledException(
                ex.getMessage()
            );
        }
    }

}