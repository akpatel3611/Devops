public without sharing class MetadataAuthenticationService {

    public class CredentialWrapper {

        @AuraEnabled
        public Id credentialId;

        @AuraEnabled
        public String credentialName;

        @AuraEnabled
        public String instanceUrl;

        @AuraEnabled
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
    System.debug(LoggingLevel.DEBUG, 'MetadataAuthenticationService.generateAccessToken:start credentialId=' + credentialId);

    Credentials__c credentialRecord = [
        SELECT Id,
               Name,
               Instance_URL__c,
               Connected_App_Client_Id__c,
               Connected_App_Client_Secret__c,
               SFDX_Auth_URL__c
        FROM Credentials__c
        WHERE Id = :credentialId
        LIMIT 1
    ];

    Boolean isGitHub = String.isNotBlank(credentialRecord.Instance_URL__c) && credentialRecord.Instance_URL__c.contains('github.com');

    // Try SFDX CLI Refresh Token flow if client credentials are not fully configured or instance URL is github.com
    if ((isGitHub || String.isBlank(credentialRecord.Connected_App_Client_Id__c) || String.isBlank(credentialRecord.Connected_App_Client_Secret__c)) 
        && String.isNotBlank(credentialRecord.SFDX_Auth_URL__c)) {
        
        try {
            String sfdxAuthUrl = credentialRecord.SFDX_Auth_URL__c;
            String urlWithoutProtocol = sfdxAuthUrl.substring(8); // remove 'force://'
            Integer atIndex = urlWithoutProtocol.lastIndexOf('@');
            if (atIndex != -1) {
                String credentialsPart = urlWithoutProtocol.substring(0, atIndex);
                String instanceUrlPart = urlWithoutProtocol.substring(atIndex + 1);

                String refreshToken = '';
                String clientId = 'PlatformCLI';

                List<String> parts = credentialsPart.split('::');
                if (parts.size() >= 2) {
                    refreshToken = parts[1];
                } else {
                    List<String> subParts = credentialsPart.split(':');
                    if (subParts.size() >= 3) {
                        refreshToken = subParts[2];
                    } else if (subParts.size() >= 2) {
                        refreshToken = subParts[1];
                    }
                }

                if (String.isNotBlank(refreshToken)) {
                    String endpoint = 'https://' + instanceUrlPart + '/services/oauth2/token';
                    HttpRequest request = new HttpRequest();
                    request.setEndpoint(endpoint);
                    request.setMethod('POST');
                    request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

                    String body = 'grant_type=refresh_token' +
                                  '&client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
                                  '&refresh_token=' + EncodingUtil.urlEncode(refreshToken, 'UTF-8');
                    request.setBody(body);

                    HttpResponse response = new Http().send(request);
                    if (response.getStatusCode() == 200) {
                        Map<String, Object> jsonData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                        OAuthTokenResponse result = new OAuthTokenResponse();
                        result.accessToken = (String) jsonData.get('access_token');
                        result.instanceUrl = 'https://' + instanceUrlPart;
                        return result;
                    } else {
                        System.debug(LoggingLevel.WARN, 'SFDX Refresh Token exchange failed: Status ' + response.getStatusCode() + ': ' + response.getBody());
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Fallback SFDX Refresh Token exchange warning: ' + ex.getMessage());
        }
    }

    if (String.isBlank(credentialRecord.Instance_URL__c)) {
        System.debug(LoggingLevel.ERROR, 'MetadataAuthenticationService.generateAccessToken:missing Instance_URL__c credentialId=' + credentialId + ', credentialName=' + credentialRecord.Name);
        throw new AuraHandledException('Credential "' + credentialRecord.Name + '" is missing Instance URL. Fill Credentials__c.Instance_URL__c with a full URL like https://your-domain.my.salesforce.com.');
    }

    if (!credentialRecord.Instance_URL__c.startsWith('https://') && !credentialRecord.Instance_URL__c.startsWith('http://')) {
        System.debug(LoggingLevel.ERROR, 'MetadataAuthenticationService.generateAccessToken:invalid Instance_URL__c credentialId=' + credentialId + ', instanceUrl=' + credentialRecord.Instance_URL__c);
        throw new AuraHandledException('Credential "' + credentialRecord.Name + '" has invalid Instance URL: ' + credentialRecord.Instance_URL__c + '. It must start with https://.');
    }

    if (String.isBlank(credentialRecord.Connected_App_Client_Id__c) || String.isBlank(credentialRecord.Connected_App_Client_Secret__c)) {
        System.debug(LoggingLevel.ERROR, 'MetadataAuthenticationService.generateAccessToken:missing OAuth client config credentialId=' + credentialId + ', credentialName=' + credentialRecord.Name);
        throw new AuraHandledException('Credential "' + credentialRecord.Name + '" is missing Connected App Client Id or Client Secret.');
    }

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

    System.debug(LoggingLevel.DEBUG, 'MetadataAuthenticationService.generateAccessToken:response credentialId=' + credentialId + ', statusCode=' + response.getStatusCode() + ', body=' + response.getBody());

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
    } else {
        throw new AuraHandledException('Failed to generate access token for credential "' + credentialRecord.Name + '". Status ' + response.getStatusCode() + ': ' + response.getBody());
    }

    if (String.isBlank(result.accessToken) || String.isBlank(result.instanceUrl)) {
        throw new AuraHandledException('OAuth token response for credential "' + credentialRecord.Name + '" did not include a usable access token and instance URL.');
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