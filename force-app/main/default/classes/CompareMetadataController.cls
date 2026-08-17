public with sharing class CompareMetadataController {

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
        Id targetEnvironmentId,
        String metadataType,
        List<String> componentNames
    ){
        System.debug(LoggingLevel.INFO, '[CompareMetadataController.compareMetadata] START - targetEnvironmentId: ' + targetEnvironmentId + ' | MetadataType: ' + metadataType + ' | Components Count: ' + (componentNames != null ? componentNames.size() : 0));
        List<CompareResult> results = new List<CompareResult>();
        if (componentNames == null || componentNames.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[CompareMetadataController.compareMetadata] Warning: componentNames list is empty or null.');
            return results;
        }

        try {
            List<MetadataExplorerController.MetadataItem> targetMetadata = MetadataExplorerController.getMetadata(
                metadataType,
                targetEnvironmentId
            );
            System.debug(LoggingLevel.DEBUG, '[CompareMetadataController.compareMetadata] Fetched ' + (targetMetadata != null ? targetMetadata.size() : 0) + ' items from target environment.');

            Set<String> targetNames = new Set<String>();
            if (targetMetadata != null) {
                for (MetadataExplorerController.MetadataItem item : targetMetadata) {
                    if (item != null && String.isNotBlank(item.value)) {
                        targetNames.add(item.value);
                    }
                }
            }

            for (String component : componentNames) {
                if (targetNames.contains(component)) {
                    results.add(new CompareResult(component, 'EXISTS'));
                    System.debug(LoggingLevel.FINE, '[CompareMetadataController.compareMetadata] Component: ' + component + ' -> EXISTS');
                } else {
                    results.add(new CompareResult(component, 'MISSING'));
                    System.debug(LoggingLevel.FINE, '[CompareMetadataController.compareMetadata] Component: ' + component + ' -> MISSING');
                }
            }

            System.debug(LoggingLevel.INFO, '[CompareMetadataController.compareMetadata] SUCCESS - Evaluated ' + results.size() + ' metadata comparison results.');
            return results;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[CompareMetadataController.compareMetadata] Exception: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Failed to compare metadata: ' + ex.getMessage());
        }
    }
}