public with sharing class MetadataApiService {

    @AuraEnabled(cacheable=true)
    public static List<String> getMetadataTypes() {
        System.debug(LoggingLevel.INFO, '[MetadataApiService.getMetadataTypes] START');
        try {
            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            MetadataService.SessionHeader_element sessionHeader = new MetadataService.SessionHeader_element();
            sessionHeader.sessionId = UserInfo.getSessionId();
            service.SessionHeader = sessionHeader;

            MetadataService.DescribeMetadataResult result = service.describeMetadata(Double.valueOf('64'));
            List<String> metadataTypes = new List<String>();

            if (result != null && result.metadataObjects != null) {
                for (MetadataService.DescribeMetadataObject metadataObject : result.metadataObjects) {
                    if (metadataObject != null && String.isNotBlank(metadataObject.xmlName)) {
                        metadataTypes.add(metadataObject.xmlName);
                    }
                }
            }

            metadataTypes.sort();
            System.debug(LoggingLevel.INFO, '[MetadataApiService.getMetadataTypes] SUCCESS - Described ' + metadataTypes.size() + ' metadata types.');
            return metadataTypes;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataApiService.getMetadataTypes] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to get metadata types: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getMetadataComponents(String metadataType) {
        System.debug(LoggingLevel.INFO, '[MetadataApiService.getMetadataComponents] START - metadataType: ' + metadataType);
        if (String.isBlank(metadataType)) {
            System.debug(LoggingLevel.WARN, '[MetadataApiService.getMetadataComponents] Warning: metadataType is blank.');
            return new List<String>();
        }

        try {
            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            MetadataService.SessionHeader_element sessionHeader = new MetadataService.SessionHeader_element();
            sessionHeader.sessionId = UserInfo.getSessionId();
            service.SessionHeader = sessionHeader;

            MetadataService.ListMetadataQuery query = new MetadataService.ListMetadataQuery();
            query.type_x = metadataType;

            MetadataService.FileProperties[] fileProperties = service.listMetadata(new List<MetadataService.ListMetadataQuery>{ query }, Double.valueOf('64'));
            List<String> componentNames = new List<String>();

            if (fileProperties != null) {
                for (MetadataService.FileProperties fp : fileProperties) {
                    if (fp != null && String.isNotBlank(fp.fullName)) {
                        componentNames.add(fp.fullName);
                    }
                }
            }

            componentNames.sort();
            System.debug(LoggingLevel.INFO, '[MetadataApiService.getMetadataComponents] SUCCESS - Found ' + componentNames.size() + ' components for type: ' + metadataType);
            return componentNames;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataApiService.getMetadataComponents] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to get metadata components for ' + metadataType + ': ' + ex.getMessage());
        }
    }
}