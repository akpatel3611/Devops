public with sharing class MetadataApiService {

    @AuraEnabled(cacheable=true)
    public static List<String> getMetadataTypes() {

        MetadataService.MetadataPort service =
            new MetadataService.MetadataPort();

        MetadataService.SessionHeader_element sessionHeader =
            new MetadataService.SessionHeader_element();

        sessionHeader.sessionId =
            UserInfo.getSessionId();

        service.SessionHeader =
            sessionHeader;

        MetadataService.DescribeMetadataResult result =
            service.describeMetadata(
                Double.valueOf('64')
            );

        List<String> metadataTypes =
            new List<String>();

        for(
            MetadataService.DescribeMetadataObject metadataObject :
            result.metadataObjects
        ){

            metadataTypes.add(
                metadataObject.xmlName
            );
        }

        metadataTypes.sort();

        return metadataTypes;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getMetadataComponents(
        String metadataType
    ){

        MetadataService.MetadataPort service =
            new MetadataService.MetadataPort();

        MetadataService.SessionHeader_element sessionHeader =
            new MetadataService.SessionHeader_element();

        sessionHeader.sessionId =
            UserInfo.getSessionId();

        service.SessionHeader =
            sessionHeader;

        MetadataService.ListMetadataQuery query =
            new MetadataService.ListMetadataQuery();

        query.type_x =
            metadataType;

        MetadataService.ListMetadataQuery[] queries =
            new MetadataService.ListMetadataQuery[]{
                query
            };

        MetadataService.FileProperties[] files =
            service.listMetadata(
                queries,
                Double.valueOf('64')
            );

        List<String> componentNames =
            new List<String>();

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

                    componentNames.add(
                        file.fullName
                    );
                }
            }
        }

        componentNames.sort();

        return componentNames;
    }

    @AuraEnabled
public static List<String> testSourceMetadata(
    Id credentialId
){

    MetadataAuthenticationService.OAuthTokenResponse token =

        MetadataAuthenticationService.generateAccessToken(
            credentialId
        );

    MetadataService.MetadataPort service =
        new MetadataService.MetadataPort();

    service.endpoint_x =

        token.instanceUrl +

        '/services/Soap/m/64.0';

    MetadataService.SessionHeader_element sessionHeader =

        new MetadataService.SessionHeader_element();

    sessionHeader.sessionId =

        token.accessToken;

    service.SessionHeader =
        sessionHeader;

    MetadataService.DescribeMetadataResult result =

        service.describeMetadata(
            Double.valueOf('64')
        );

    List<String> metadataTypes =
        new List<String>();

    for(
        MetadataService.DescribeMetadataObject obj :
        result.metadataObjects
    ){

        metadataTypes.add(
            obj.xmlName
        );
    }

    return metadataTypes;
}
}