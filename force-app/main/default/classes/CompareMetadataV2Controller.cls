public with sharing class CompareMetadataV2Controller {

    public class CompareResult {
        @AuraEnabled public String componentName;
        @AuraEnabled public String status;

        public CompareResult(String componentName, String status) {
            this.componentName = componentName;
            this.status = status;
        }
    }

    @AuraEnabled
    public static List<CompareResult> compareMetadata(
        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        String metadataType,
        List<String> componentNames
    ){
        System.debug(LoggingLevel.INFO, '[CompareMetadataV2Controller.compareMetadata] START - SourceEnv: ' + sourceEnvironmentId + ' | TargetEnv: ' + targetEnvironmentId + ' | MetadataType: ' + metadataType + ' | Components Count: ' + (componentNames != null ? componentNames.size() : 0));
        List<CompareResult> results = new List<CompareResult>();
        if (componentNames == null || componentNames.isEmpty() || sourceEnvironmentId == null || targetEnvironmentId == null) {
            System.debug(LoggingLevel.WARN, '[CompareMetadataV2Controller.compareMetadata] Warning: Missing environment IDs or empty component list.');
            return results;
        }

        try {
            DeploymentCredentialController.CredentialWrapper sourceCredential = DeploymentCredentialController.getCredentialByEnvironment(sourceEnvironmentId);
            DeploymentCredentialController.CredentialWrapper targetCredential = DeploymentCredentialController.getCredentialByEnvironment(targetEnvironmentId);

            System.debug(LoggingLevel.DEBUG, '[CompareMetadataV2Controller.compareMetadata] Generating access tokens for Source Credential ID: ' + sourceCredential.credentialId + ' & Target Credential ID: ' + targetCredential.credentialId);
            MetadataAuthenticationService.OAuthTokenResponse sourceToken = MetadataAuthenticationService.generateAccessToken(sourceCredential.credentialId);
            MetadataAuthenticationService.OAuthTokenResponse targetToken = MetadataAuthenticationService.generateAccessToken(targetCredential.credentialId);

            MetadataService.MetadataPort sourceService = new MetadataService.MetadataPort();
            sourceService.endpoint_x = sourceToken.instanceUrl + '/services/Soap/m/64.0';
            MetadataService.SessionHeader_element sourceHeader = new MetadataService.SessionHeader_element();
            sourceHeader.sessionId = sourceToken.accessToken;
            sourceService.SessionHeader = sourceHeader;

            MetadataService.MetadataPort targetService = new MetadataService.MetadataPort();
            targetService.endpoint_x = targetToken.instanceUrl + '/services/Soap/m/64.0';
            MetadataService.SessionHeader_element targetHeader = new MetadataService.SessionHeader_element();
            targetHeader.sessionId = targetToken.accessToken;
            targetService.SessionHeader = targetHeader;

            for (String componentName : componentNames) {
                try {
                    MetadataService.IReadResult sourceRead = sourceService.readMetadata(metadataType, new String[]{ componentName });
                    MetadataService.IReadResult targetRead = targetService.readMetadata(metadataType, new String[]{ componentName });

                    String sourceJson = JSON.serialize(sourceRead);
                    String targetJson = JSON.serialize(targetRead);

                    if (sourceJson == targetJson) {
                        results.add(new CompareResult(componentName, 'SAME'));
                        System.debug(LoggingLevel.FINE, '[CompareMetadataV2Controller.compareMetadata] Component: ' + componentName + ' -> SAME');
                    } else {
                        results.add(new CompareResult(componentName, 'CHANGED'));
                        System.debug(LoggingLevel.FINE, '[CompareMetadataV2Controller.compareMetadata] Component: ' + componentName + ' -> CHANGED');
                    }
                } catch (Exception itemEx) {
                    System.debug(LoggingLevel.WARN, '[CompareMetadataV2Controller.compareMetadata] Error reading metadata for component: ' + componentName + ' - Message: ' + itemEx.getMessage());
                    results.add(new CompareResult(componentName, 'ERROR'));
                }
            }

            System.debug(LoggingLevel.INFO, '[CompareMetadataV2Controller.compareMetadata] SUCCESS - Evaluated ' + results.size() + ' metadata comparison results.');
            return results;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[CompareMetadataV2Controller.compareMetadata] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to compare metadata V2: ' + ex.getMessage());
        }
    }
}