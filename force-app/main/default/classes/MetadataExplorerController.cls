public with sharing class MetadataExplorerController {

    public class MetadataItem implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String fullName;
        @AuraEnabled public String type;
        @AuraEnabled public String lastModifiedByName;
        @AuraEnabled public String lastModifiedDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String createdDate;

        public MetadataItem(String label, String value) {
            this.label = label;
            this.value = value;
            this.fullName = value;
        }

        public Integer compareTo(Object compareTo) {
            MetadataItem other = (MetadataItem) compareTo;
            String name1 = this.label != null ? this.label.toLowerCase() : '';
            String name2 = other != null && other.label != null ? other.label.toLowerCase() : '';
            return name1.compareTo(name2);
        }
    }

    public class MetadataTypeWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public MetadataTypeWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    private class SessionContext {
        public String accessToken;
        public String instanceUrl;
    }

    private static SessionContext resolveSessionContext(Id sourceEnvironmentId) {
        SessionContext ctx = new SessionContext();
        if (sourceEnvironmentId != null) {
            try {
                DeploymentCredentialController.CredentialWrapper credential = 
                    DeploymentCredentialController.getCredentialByEnvironment(sourceEnvironmentId);

                if (credential != null && String.isNotBlank(credential.credentialId)) {
                    MetadataAuthenticationService.OAuthTokenResponse token = 
                        MetadataAuthenticationService.generateAccessToken(credential.credentialId);
                    if (token != null && String.isNotBlank(token.accessToken)) {
                        ctx.accessToken = token.accessToken;
                        ctx.instanceUrl = token.instanceUrl;
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'OAuth token resolution warning: ' + ex.getMessage());
            }
        }

        if (String.isBlank(ctx.accessToken)) {
            ctx.accessToken = UserInfo.getSessionId();
            ctx.instanceUrl = Url.getOrgDomainUrl().toExternalForm();
        }

        return ctx;
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataTypeWrapper> getMetadataTypes(Id sourceEnvironmentId) {
        System.debug(LoggingLevel.INFO, '[MetadataExplorerController.getMetadataTypes] START - sourceEnvironmentId: ' + sourceEnvironmentId);
        List<MetadataTypeWrapper> results = new List<MetadataTypeWrapper>();
        Set<String> typeNames = new Set<String>();

        try {
            SessionContext ctx = resolveSessionContext(sourceEnvironmentId);

            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            service.endpoint_x = ctx.instanceUrl + '/services/Soap/m/64.0';

            MetadataService.SessionHeader_element sessionHeader = new MetadataService.SessionHeader_element();
            sessionHeader.sessionId = ctx.accessToken;
            service.SessionHeader = sessionHeader;

            MetadataService.DescribeMetadataResult describeResult = service.describeMetadata(Double.valueOf('64'));

            if (describeResult != null && describeResult.metadataObjects != null) {
                for (MetadataService.DescribeMetadataObject obj : describeResult.metadataObjects) {
                    if (String.isNotBlank(obj.xmlName)) {
                        typeNames.add(obj.xmlName);
                    }
                    if (obj.childXmlNames != null) {
                        for (String child : obj.childXmlNames) {
                            if (String.isNotBlank(child)) {
                                typeNames.add(child);
                            }
                        }
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataExplorerController.getMetadataTypes] Describe error: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
        }

        if (typeNames.isEmpty()) {
            typeNames.addAll(new List<String>{
                'ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent',
                'CustomObject', 'CustomField', 'CustomLabel', 'Flow',
                'Layout', 'PermissionSet', 'Profile', 'LightningComponentBundle',
                'AuraDefinitionBundle', 'RecordType', 'ValidationRule', 'FlexiPage',
                'CustomTab', 'CustomApplication'
            });
        }

        List<String> sortedTypes = new List<String>(typeNames);
        sortedTypes.sort();

        for (String typeName : sortedTypes) {
            results.add(new MetadataTypeWrapper(typeName, typeName));
        }

        System.debug(LoggingLevel.INFO, '[MetadataExplorerController.getMetadataTypes] SUCCESS - Total types count: ' + results.size());
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<MetadataItem> getMetadata(String componentType, Id sourceEnvironmentId) {
        System.debug(LoggingLevel.INFO, '[MetadataExplorerController.getMetadata] START - componentType: ' + componentType + ' | sourceEnv: ' + sourceEnvironmentId);
        List<MetadataItem> results = new List<MetadataItem>();
        if (String.isBlank(componentType)) {
            System.debug(LoggingLevel.WARN, '[MetadataExplorerController.getMetadata] Warning: componentType is blank.');
            return results;
        }

        try {
            SessionContext ctx = resolveSessionContext(sourceEnvironmentId);

            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            service.endpoint_x = ctx.instanceUrl + '/services/Soap/m/64.0';
            service.timeout_x = 120000;

            MetadataService.SessionHeader_element sessionHeader = new MetadataService.SessionHeader_element();
            sessionHeader.sessionId = ctx.accessToken;
            service.SessionHeader = sessionHeader;

            MetadataService.ListMetadataQuery query = new MetadataService.ListMetadataQuery();
            query.type_x = componentType;

            MetadataService.ListMetadataQuery[] queries = new MetadataService.ListMetadataQuery[]{ query };
            MetadataService.FileProperties[] files = service.listMetadata(queries, Double.valueOf('64'));

            if (files != null) {
                for (MetadataService.FileProperties file : files) {
                    if (String.isNotBlank(file.fullName)) {
                        MetadataItem item = new MetadataItem(file.fullName, file.fullName);
                        item.fullName = file.fullName;
                        item.type = String.isNotBlank(file.type_x) ? file.type_x : componentType;

                        item.lastModifiedByName = String.isNotBlank(file.lastModifiedByName) ? file.lastModifiedByName : UserInfo.getName();

                        if (file.lastModifiedDate != null && file.lastModifiedDate.getTime() > 0) {
                            item.lastModifiedDate = file.lastModifiedDate.format('yyyy-MM-dd HH:mm');
                        } else {
                            item.lastModifiedDate = '';
                        }

                        item.createdByName = String.isNotBlank(file.createdByName) ? file.createdByName : UserInfo.getName();
                        if (file.createdDate != null && file.createdDate.getTime() > 0) {
                            item.createdDate = file.createdDate.format('yyyy-MM-dd HH:mm');
                        } else {
                            item.createdDate = '';
                        }

                        results.add(item);
                    }
                }
            }

            results.sort();
            System.debug(LoggingLevel.INFO, '[MetadataExplorerController.getMetadata] SUCCESS - Fetched ' + results.size() + ' items for type: ' + componentType);
            return results;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[MetadataExplorerController.getMetadata] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());
        }
    }
}