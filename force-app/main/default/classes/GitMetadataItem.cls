/**
 * Standalone DTO representing a metadata item for Git provider operations.
 * Completely independent of Salesforce SObjects.
 */
public class GitMetadataItem {
    @AuraEnabled public String metadataType {get;set;}
    @AuraEnabled public String apiName {get;set;}
    @AuraEnabled public String filePath {get;set;}
    @AuraEnabled public String deploymentAction {get;set;}
}