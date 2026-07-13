public without sharing class MetadataAuthenticationService {

    public class CredentialWrapper {

        @AuraEnabled
        public Id credentialId;

        @AuraEnabled
        public String credentialName;

        @AuraEnabled
        public String instanceUrl;

        @AuraEnabled
        public String sfdxAuthUrl;

        @AuraEnabled
        public String authType;
    }

    public class OAuthTokenResponse {

        @AuraEnabled
        public String accessToken;

        @AuraEnabled
        public String instanceUrl;
    }
    @AuraEnabled(cacheable=true)
    public static CredentialWrapper getCredential(
        Id credentialId
    ){

        Credentials__c credentialRecord = [

            SELECT Id,
                   Name,
                   Instance_URL__c,
                   SFDX_Auth_URL__c
            FROM Credentials__c
            WHERE Id = :credentialId
            LIMIT 1
        ];

        CredentialWrapper result =
            new CredentialWrapper();

        result.credentialId =
            credentialRecord.Id;

        result.credentialName =
            credentialRecord.Name;

        result.instanceUrl =
            credentialRecord.Instance_URL__c;

        result.sfdxAuthUrl =
            credentialRecord.SFDX_Auth_URL__c;

        result.authType =
            'SFDX Auth URL';

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static String getInstanceUrl(
        Id credentialId
    ){

        Credentials__c credentialRecord = [

            SELECT Instance_URL__c
            FROM Credentials__c
            WHERE Id = :credentialId
            LIMIT 1
        ];

        return credentialRecord.Instance_URL__c;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasSfdxAuthUrl(
        Id credentialId
    ){

        Credentials__c credentialRecord = [

            SELECT SFDX_Auth_URL__c
            FROM Credentials__c
            WHERE Id = :credentialId
            LIMIT 1
        ];

        return String.isNotBlank(
            credentialRecord.SFDX_Auth_URL__c
        );
    }

    @AuraEnabled(cacheable=true)
    public static String getOrgDomainFromSfdxUrl(
        Id credentialId
    ){

        Credentials__c credentialRecord = [

            SELECT SFDX_Auth_URL__c

            FROM Credentials__c

            WHERE Id = :credentialId

            LIMIT 1
        ];

        if(
            String.isBlank(
                credentialRecord.SFDX_Auth_URL__c
            )
        ){
            return null;
        }

        String sfdxUrl =
            credentialRecord.SFDX_Auth_URL__c;

        Integer atIndex =
            sfdxUrl.lastIndexOf('@');

        if(atIndex == -1){
            return null;
        }

        return
            sfdxUrl.substring(
                atIndex + 1
            );
    }

    @AuraEnabled(cacheable=true)
public static String getSfdxAuthUrl(
    Id credentialId
){

    Credentials__c credentialRecord = [

        SELECT SFDX_Auth_URL__c

        FROM Credentials__c

        WHERE Id = :credentialId

        LIMIT 1
    ];

    return credentialRecord.SFDX_Auth_URL__c;
}

@AuraEnabled(cacheable=true)
public static String getClientId(
    Id credentialId
){

    Credentials__c credentialRecord = [

        SELECT Connected_App_Client_Id__c

        FROM Credentials__c

        WHERE Id = :credentialId

        LIMIT 1
    ];

    return
        credentialRecord.Connected_App_Client_Id__c;
}

@AuraEnabled(cacheable=true)
public static String getClientSecret(
    Id credentialId
){

    Credentials__c credentialRecord = [

        SELECT Connected_App_Client_Secret__c

        FROM Credentials__c

        WHERE Id = :credentialId

        LIMIT 1
    ];

    return
        credentialRecord
            .Connected_App_Client_Secret__c;
}

@AuraEnabled(cacheable=true)
public static Boolean isOAuthReady(
    Id credentialId
){

    Credentials__c credentialRecord = [

        SELECT Connected_App_Client_Id__c,
               Connected_App_Client_Secret__c,
               Instance_URL__c

        FROM Credentials__c

        WHERE Id = :credentialId

        LIMIT 1
    ];

    return

        String.isNotBlank(
            credentialRecord
            .Connected_App_Client_Id__c
        )

        &&

        String.isNotBlank(
            credentialRecord
            .Connected_App_Client_Secret__c
        )

        &&

        String.isNotBlank(
            credentialRecord
            .Instance_URL__c
        );
}
@AuraEnabled
public static OAuthTokenResponse generateAccessToken(
    Id credentialId
){

    Credentials__c credentialRecord = [

        SELECT Instance_URL__c,
               Connected_App_Client_Id__c,
               Connected_App_Client_Secret__c

        FROM Credentials__c

        WHERE Id = :credentialId

        LIMIT 1
    ];

    HttpRequest request =
        new HttpRequest();

    request.setEndpoint(

        credentialRecord.Instance_URL__c +

        '/services/oauth2/token'
    );

    request.setMethod(
        'POST'
    );

    request.setHeader(
        'Content-Type',
        'application/x-www-form-urlencoded'
    );

    request.setBody(

        'grant_type=client_credentials'

        +

        '&client_id='

        +

        EncodingUtil.urlEncode(

            credentialRecord
            .Connected_App_Client_Id__c,

            'UTF-8'
        )

        +

        '&client_secret='

        +

        EncodingUtil.urlEncode(

            credentialRecord
            .Connected_App_Client_Secret__c,

            'UTF-8'
        )
    );

    HttpResponse response =

        new Http().send(
            request
        );

    System.debug(
        response.getBody()
    );

    OAuthTokenResponse result =

        new OAuthTokenResponse();

    if(
        response.getStatusCode() == 200
    ){

        Map<String,Object> jsonData =

            (Map<String,Object>)
            JSON.deserializeUntyped(

                response.getBody()
            );

        result.accessToken =

            (String)
            jsonData.get(
                'access_token'
            );

        result.instanceUrl =

            credentialRecord
            .Instance_URL__c;
    }

    return result;
}
@AuraEnabled
public static String getApexClasses(
    Id credentialId
){
    OAuthTokenResponse tokenResponse =
        generateAccessToken(
            credentialId
        );

    HttpRequest request =
        new HttpRequest();

    request.setEndpoint(

        tokenResponse.instanceUrl +

        '/services/data/v64.0/tooling/query/?q=' +

        EncodingUtil.urlEncode(

            'SELECT Id, Name FROM ApexClass ORDER BY Name',

            'UTF-8'
        )
    );

    request.setMethod(
        'GET'
    );

    request.setHeader(
        'Authorization',
        'Bearer ' +
        tokenResponse.accessToken
    );

    HttpResponse response =

        new Http().send(
            request
        );

    return
        response.getBody();
}

@AuraEnabled
public static String getMetadataFromSourceOrg(
    Id credentialId,
    String soqlQuery
){

    OAuthTokenResponse tokenResponse =

        generateAccessToken(
            credentialId
        );

    HttpRequest request =
        new HttpRequest();

    request.setEndpoint(

        tokenResponse.instanceUrl +

        '/services/data/v64.0/tooling/query/?q=' +

        EncodingUtil.urlEncode(

            soqlQuery,

            'UTF-8'
        )
    );

    request.setMethod(
        'GET'
    );

    request.setHeader(
        'Authorization',

        'Bearer ' +

        tokenResponse.accessToken
    );

    HttpResponse response =

        new Http().send(
            request
        );

    return response.getBody();
}

}