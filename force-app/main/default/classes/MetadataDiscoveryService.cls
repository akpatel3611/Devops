public with sharing class MetadataDiscoveryService {

    public class MetadataTypeOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class MetadataComponent {
        @AuraEnabled public String name;
        @AuraEnabled public String type;
    }

    @AuraEnabled(cacheable=true)
    public static String getSourceOrgDomain(Id credentialId) {
        System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getSourceOrgDomain] START - credentialId: ' + credentialId);
        try {
            String domain = MetadataAuthenticationService.getOrgDomainFromSfdxUrl(credentialId);
            System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getSourceOrgDomain] SUCCESS - Domain: ' + domain);
            return domain;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataDiscoveryService.getSourceOrgDomain] Exception: ' + ex.getMessage());
            throw new AuraHandledException('Failed to get org domain: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getRawSfdxAuthUrl(Id credentialId) {
        System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getRawSfdxAuthUrl] START - credentialId: ' + credentialId);
        try {
            String url = MetadataAuthenticationService.getSfdxAuthUrl(credentialId);
            System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getRawSfdxAuthUrl] SUCCESS - Auth URL resolved.');
            return url;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataDiscoveryService.getRawSfdxAuthUrl] Exception: ' + ex.getMessage());
            throw new AuraHandledException('Failed to get raw SFDX auth URL: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getEnvironmentMetadataSource(Id credentialId) {
        System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getEnvironmentMetadataSource] START - credentialId: ' + credentialId);
        try {
            String domain = MetadataAuthenticationService.getOrgDomainFromSfdxUrl(credentialId);
            System.debug(LoggingLevel.INFO, '[MetadataDiscoveryService.getEnvironmentMetadataSource] SUCCESS - Domain: ' + domain);
            return domain;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataDiscoveryService.getEnvironmentMetadataSource] Exception: ' + ex.getMessage());
            throw new AuraHandledException('Failed to get environment metadata source: ' + ex.getMessage());
        }
    }
}