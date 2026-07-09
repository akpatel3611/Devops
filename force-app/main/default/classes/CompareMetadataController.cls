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

        List<CompareResult> results =
            new List<CompareResult>();

        List<MetadataExplorerController.MetadataItem>
            targetMetadata =

            MetadataExplorerController.getMetadata(

                metadataType,

                targetEnvironmentId
            );

        Set<String> targetNames =
            new Set<String>();

        for(
            MetadataExplorerController.MetadataItem item :
            targetMetadata
        ){

            targetNames.add(
                item.value
            );
        }

        for(
            String component :
            componentNames
        ){

            if(
                targetNames.contains(
                    component
                )
            ){

                results.add(

                    new CompareResult(

                        component,

                        'EXISTS'
                    )
                );
            }
            else{

                results.add(

                    new CompareResult(

                        component,

                        'MISSING'
                    )
                );
            }
        }

        return results;
    }
}