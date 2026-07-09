/**
 * Standalone DTO representing the result returned from version control providers.
 * Contains only direct provider execution properties.
 */
public class GitCommitResult {
    @AuraEnabled public Boolean success {get;set;}
    @AuraEnabled public String commitId {get;set;}
    @AuraEnabled public String pullRequestNumber {get;set;}
    @AuraEnabled public String pullRequestUrl {get;set;}
    @AuraEnabled public List<String> errors {get;set;}
}