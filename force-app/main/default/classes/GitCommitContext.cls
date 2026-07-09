/**
 * Standalone DTO representing the context parameters passed to version control providers.
 * Contains only primitive runtime values and completely independent DTOs.
 * Free of any Salesforce SObject types or Record IDs.
 */
public class GitCommitContext {
    @AuraEnabled public String repositoryName {get;set;}
    @AuraEnabled public String repositoryOwner {get;set;}
    @AuraEnabled public String repositoryUrl {get;set;}
    @AuraEnabled public String defaultBranch {get;set;}
    @AuraEnabled public String providerType {get;set;}
    @AuraEnabled public String developerUsername {get;set;}
    @AuraEnabled public List<GitMetadataItem> selectedMetadata {get;set;}
    @AuraEnabled public String featureBranchName {get;set;}
    @AuraEnabled public Datetime executionTimestamp {get;set;}
}