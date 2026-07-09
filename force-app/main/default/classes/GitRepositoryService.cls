/**
 * Domain service class responsible for managing Git Repository registration,
 * field validations, lifecycle state transitions, and archiving.
 * Excludes remote callouts, webhooks processing, and credentials resolution.
 */
public with sharing class GitRepositoryService {

    public class GitRepositoryServiceException extends Exception {}

    // Lifecycle Status Constants
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_REGISTERED = 'Registered';
    public static final String STATUS_VERIFIED = 'Verified';
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_ARCHIVED = 'Archived';

    // Valid Git Providers
    private static final Set<String> VALID_PROVIDERS = new Set<String>{
        'GitHub', 'GitLab', 'Bitbucket', 'Azure_DevOps'
    };

    // DTO class for repository action responses
    public class RepositoryResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id repositoryId {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    // DTO class for repository validation results
    public class ValidationResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
    }

    /**
     * Helper to instantiate a default RepositoryResult response.
     */
    private static RepositoryResult createDefaultResult() {
        RepositoryResult result = new RepositoryResult();
        result.success = false;
        result.errors = new List<String>();
        return result;
    }

    /**
     * Registers a new repository record in Draft status after validation.
     */
    public static RepositoryResult createRepository(
        String name,
        String identifier,
        String url,
        String provider,
        String owner,
        String defaultBranch
    ) {
        ValidationResult valRes = validateCreate(name, identifier, url, provider, owner, defaultBranch);
        if (!valRes.success) {
            RepositoryResult errResult = createDefaultResult();
            errResult.message = valRes.message;
            errResult.errors = valRes.errors;
            return errResult;
        }

        try {
            Git_Repository__c repo = new Git_Repository__c();
            repo.Repository_Name__c = name;
            repo.Repository_Identifier__c = identifier;
            repo.GitHub_URL__c = url;
            repo.Git_Provider__c = provider;
            repo.Repository_Owner__c = owner;
            repo.Default_Branch__c = defaultBranch;
            repo.Status__c = STATUS_DRAFT;
            
            insert repo;

            RepositoryResult result = createDefaultResult();
            result.success = true;
            result.message = 'Repository registered successfully in Draft status.';
            result.repositoryId = repo.Id;
            result.status = STATUS_DRAFT;
            return result;
        } catch (Exception ex) {
            throw new GitRepositoryServiceException('Failed to create repository: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Updates configuration properties for an existing repository record.
     * Does not automatically modify the repository's lifecycle status.
     */
    public static RepositoryResult updateRepository(
        Id repositoryId,
        String name,
        String identifier,
        String url,
        String provider,
        String owner,
        String defaultBranch
    ) {
        if (repositoryId == null) {
            throw new GitRepositoryServiceException('Repository ID cannot be null.');
        }

        ValidationResult valRes = validateUpdate(repositoryId, name, identifier, url, provider, owner, defaultBranch);
        if (!valRes.success) {
            RepositoryResult errResult = createDefaultResult();
            errResult.message = valRes.message;
            errResult.errors = valRes.errors;
            errResult.repositoryId = repositoryId;
            return errResult;
        }

        try {
            Git_Repository__c repo = new Git_Repository__c(Id = repositoryId);
            repo.Repository_Name__c = name;
            repo.Repository_Identifier__c = identifier;
            repo.GitHub_URL__c = url;
            repo.Git_Provider__c = provider;
            repo.Repository_Owner__c = owner;
            repo.Default_Branch__c = defaultBranch;
            
            update repo;

            RepositoryResult result = createDefaultResult();
            result.success = true;
            result.message = 'Repository updated successfully.';
            result.repositoryId = repositoryId;
            return result;
        } catch (Exception ex) {
            throw new GitRepositoryServiceException('Failed to update repository: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Performs creation validations on repository fields.
     */
    private static ValidationResult validateCreate(
        String name,
        String identifier,
        String url,
        String provider,
        String owner,
        String defaultBranch
    ) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (String.isBlank(name)) {
            result.errors.add('Repository Name is mandatory.');
            result.success = false;
        }
        if (String.isBlank(identifier)) {
            result.errors.add('Repository Identifier is mandatory.');
            result.success = false;
        }
        if (String.isBlank(url)) {
            result.errors.add('Repository URL is mandatory.');
            result.success = false;
        } else if (!url.startsWithIgnoreCase('http://') && !url.startsWithIgnoreCase('https://')) {
            result.errors.add('Repository URL must be a valid HTTP or HTTPS URL.');
            result.success = false;
        }
        if (String.isBlank(provider)) {
            result.errors.add('Repository Provider is mandatory.');
            result.success = false;
        } else {
            if (!VALID_PROVIDERS.contains(provider)) {
                result.errors.add('Invalid Repository Provider: ' + provider);
                result.success = false;
            }
        }
        if (String.isBlank(owner)) {
            result.errors.add('Repository Owner is mandatory.');
            result.success = false;
        }
        if (String.isBlank(defaultBranch)) {
            result.errors.add('Default Branch is mandatory.');
            result.success = false;
        }

        if (!result.success) {
            result.message = 'Validation failed for repository creation.';
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Performs update validations on editable fields.
     */
    private static ValidationResult validateUpdate(
        Id repositoryId,
        String name,
        String identifier,
        String url,
        String provider,
        String owner,
        String defaultBranch
    ) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (repositoryId == null) {
            result.errors.add('Repository ID is mandatory.');
            result.success = false;
        }
        if (String.isBlank(name)) {
            result.errors.add('Repository Name is mandatory.');
            result.success = false;
        }
        if (String.isBlank(defaultBranch)) {
            result.errors.add('Default Branch is mandatory.');
            result.success = false;
        }
        if (String.isBlank(url)) {
            result.errors.add('Repository URL is mandatory.');
            result.success = false;
        } else if (!url.startsWithIgnoreCase('http://') && !url.startsWithIgnoreCase('https://')) {
            result.errors.add('Repository URL must be a valid HTTP or HTTPS URL.');
            result.success = false;
        }
        
        if (provider != null) {
            if (!VALID_PROVIDERS.contains(provider)) {
                result.errors.add('Invalid Repository Provider: ' + provider);
                result.success = false;
            }
        }

        if (!result.success) {
            result.message = 'Validation failed for repository update.';
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Validates repository lifecycle status transitions.
     * Allowed flow: Draft -> Registered -> Verified -> Active -> Archived.
     */
    private static ValidationResult validateLifecycleTransition(String currentStatus, String targetStatus) {
        ValidationResult result = new ValidationResult();
        result.errors = new List<String>();
        result.success = true;

        if (currentStatus == targetStatus) {
            result.message = 'Validation passed.';
            return result;
        }

        Boolean isValid = false;
        if (currentStatus == STATUS_DRAFT && targetStatus == STATUS_REGISTERED) {
            isValid = true;
        } else if (currentStatus == STATUS_REGISTERED && targetStatus == STATUS_VERIFIED) {
            isValid = true;
        } else if (currentStatus == STATUS_VERIFIED && targetStatus == STATUS_ACTIVE) {
            isValid = true;
        } else if (currentStatus == STATUS_ACTIVE && targetStatus == STATUS_ARCHIVED) {
            isValid = true;
        }

        if (!isValid) {
            result.success = false;
            String errMsg = 'Invalid status transition from ' + currentStatus + ' to ' + targetStatus;
            result.errors.add(errMsg);
            result.message = errMsg;
        } else {
            result.message = 'Validation passed.';
        }
        return result;
    }

    /**
     * Core reusable state transition handler.
     */
    public static RepositoryResult transitionRepositoryStatus(Id repositoryId, String targetStatus) {
        if (repositoryId == null) {
            throw new GitRepositoryServiceException('Repository ID cannot be null.');
        }

        try {
            Git_Repository__c repo = [
                SELECT Id, Status__c 
                FROM Git_Repository__c 
                WHERE Id = :repositoryId 
                LIMIT 1
            ];

            ValidationResult valRes = validateLifecycleTransition(repo.Status__c, targetStatus);
            if (!valRes.success) {
                throw new GitRepositoryServiceException(valRes.message);
            }

            repo.Status__c = targetStatus;
            update repo;

            RepositoryResult result = createDefaultResult();
            result.success = true;
            result.message = 'Repository status transitioned to ' + targetStatus + ' successfully.';
            result.repositoryId = repositoryId;
            result.status = targetStatus;
            return result;
        } catch (Exception ex) {
            throw new GitRepositoryServiceException('Failed to transition repository status: ' + ex.getMessage(), ex);
        }
    }

    /**
     * Transitions status to Archived for the given repository.
     */
    public static void archiveRepository(Id repositoryId) {
        transitionRepositoryStatus(repositoryId, STATUS_ARCHIVED);
    }
}