/**
 * GitHub implementation of the IGitCommitProvider interface.
 * Strictly encapsulates the GitHub payload generation, validations, and actual REST execution.
 */
public with sharing class GitHubCommitProvider implements IGitCommitProvider {

    /**
     * Executes the GitHub specific commit and PR REST API sequence.
     */
    public GitCommitResult executeCommit(GitCommitContext context, String commitMessage) {
        GitCommitResult result = new GitCommitResult();
        result.errors = new List<String>();
        result.success = false;

        try {
            // Step 1: Strict Context & Parameter Validation
            List<String> validationErrors = validateContext(context, commitMessage);
            if (!validationErrors.isEmpty()) {
                result.errors.addAll(validationErrors);
                return result;
            }

            // Step 2: Fetch Git repository credentials (PAT and base endpoint)
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.errors.add('Authentication Failure: No active GitHub credentials found in Salesforce.');
                return result;
            }
            String token = cred.Access_Token__c;
            String baseUrl = String.isNotBlank(cred.Instance_URL__c) && cred.Instance_URL__c.contains('github.com') ? cred.Instance_URL__c : 'https://api.github.com';

            // Step 3: Metadata Normalization
            List<GitMetadataItem> normalizedMetadata = buildMetadataPackage(context.selectedMetadata, result.errors);
            if (!result.errors.isEmpty()) {
                return result;
            }

            // Step 4: GET Default Branch Reference (Obtains latest parent commit SHA)
            String latestCommitSha = executeGetBranch(baseUrl, token, context.repositoryOwner, context.repositoryName, context.defaultBranch, result.errors);
            if (String.isBlank(latestCommitSha)) {
                return result;
            }

            // Step 5: GET Latest Commit Details (Obtains base tree SHA)
            String baseTreeSha = executeGetCommit(baseUrl, token, context.repositoryOwner, context.repositoryName, latestCommitSha, result.errors);
            if (String.isBlank(baseTreeSha)) {
                return result;
            }

            // Step 6: Create Blob for every metadata file
            List<Map<String, Object>> treeNodes = new List<Map<String, Object>>();
            for (GitMetadataItem item : normalizedMetadata) {
                String content = '/* Simulated metadata content for ' + item.apiName + ' (' + item.metadataType + ') */';
                
                if (item.metadataType == 'ApexClass') {
                    if (item.filePath.endsWith('.cls')) {
                        List<ApexClass> cls = [SELECT Body FROM ApexClass WHERE Name = :item.apiName LIMIT 1];
                        if (!cls.isEmpty()) {
                            content = cls[0].Body;
                        }
                    } else if (item.filePath.endsWith('.cls-meta.xml')) {
                        content = '<?xml version="1.0" encoding="UTF-8"?>\n<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <status>Active</status>\n</ApexClass>';
                    }
                } else if (item.metadataType == 'ApexTrigger') {
                    if (item.filePath.endsWith('.trigger')) {
                        List<ApexTrigger> trg = [SELECT Body FROM ApexTrigger WHERE Name = :item.apiName LIMIT 1];
                        if (!trg.isEmpty()) {
                            content = trg[0].Body;
                        }
                    } else if (item.filePath.endsWith('.trigger-meta.xml')) {
                        content = '<?xml version="1.0" encoding="UTF-8"?>\n<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <status>Active</status>\n</ApexTrigger>';
                    }
                } else if (item.metadataType == 'CustomObject') {
                    content = '<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n    <deploymentStatus>Deployed</deploymentStatus>\n    <sharingModel>ReadWrite</sharingModel>\n</CustomObject>';
                }

                String blobSha = executeCreateBlob(baseUrl, token, context.repositoryOwner, context.repositoryName, content, result.errors);
                if (String.isBlank(blobSha)) {
                    return result;
                }
                
                Map<String, Object> node = new Map<String, Object>();
                node.put('path', item.filePath);
                node.put('mode', '100644');
                node.put('type', 'blob');
                node.put('sha', blobSha);
                treeNodes.add(node);
            }

            // Step 7: Create Tree
            String newTreeSha = executeCreateTree(baseUrl, token, context.repositoryOwner, context.repositoryName, baseTreeSha, treeNodes, result.errors);
            if (String.isBlank(newTreeSha)) {
                return result;
            }

            // Step 8: Create Commit
            String newCommitSha = executeCreateCommit(baseUrl, token, context.repositoryOwner, context.repositoryName, commitMessage, newTreeSha, latestCommitSha, result.errors);
            if (String.isBlank(newCommitSha)) {
                return result;
            }

            // Step 9: Update Reference (Create or update feature branch to point to new commit)
            Boolean refUpdated = executeUpdateReference(baseUrl, token, context.repositoryOwner, context.repositoryName, context.featureBranchName, newCommitSha, result.errors);
            if (!refUpdated) {
                return result;
            }

            // Step 10: Create Pull Request
            Map<String, Object> prResponse = executeCreatePullRequest(baseUrl, token, context.repositoryOwner, context.repositoryName, commitMessage, context.featureBranchName, context.defaultBranch, result.errors);
            if (prResponse == null) {
                return result;
            }

            // Step 11: Populate success result parameters
            result.success = true;
            result.commitId = newCommitSha;
            result.pullRequestNumber = String.valueOf(prResponse.get('number'));
            result.pullRequestUrl = (String) prResponse.get('html_url');

        } catch (Exception ex) {
            result.success = false;
            result.errors.add('Provider Exception: ' + ex.getMessage());
        }

        return result;
    }

    // ----------------------------------------------------
    // REST API Execution Methods
    // ----------------------------------------------------

    private static String executeGetBranch(String baseUrl, String token, String owner, String repo, String branch, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/ref/heads/' + branch;
        HttpRequest req = createHttpRequest(endpoint, 'GET', token, null);
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 200) {
            if (errors.isEmpty()) {
                errors.add('Failed to retrieve branch reference: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> objMap = (Map<String, Object>) jsonMap.get('object');
        return (String) objMap.get('sha');
    }

    private static String executeGetCommit(String baseUrl, String token, String owner, String repo, String commitSha, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/commits/' + commitSha;
        HttpRequest req = createHttpRequest(endpoint, 'GET', token, null);
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 200) {
            if (errors.isEmpty()) {
                errors.add('Failed to retrieve commit details: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> treeMap = (Map<String, Object>) jsonMap.get('tree');
        return (String) treeMap.get('sha');
    }

    private static String executeCreateBlob(String baseUrl, String token, String owner, String repo, String content, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/blobs';
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('content', content);
        payload.put('encoding', 'utf-8');
        HttpRequest req = createHttpRequest(endpoint, 'POST', token, JSON.serialize(payload));
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 201) {
            if (errors.isEmpty()) {
                errors.add('Failed to create blob: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) jsonMap.get('sha');
    }

    private static String executeCreateTree(String baseUrl, String token, String owner, String repo, String baseTreeSha, List<Map<String, Object>> treeNodes, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/trees';
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('base_tree', baseTreeSha);
        payload.put('tree', treeNodes);
        HttpRequest req = createHttpRequest(endpoint, 'POST', token, JSON.serialize(payload));
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 201) {
            if (errors.isEmpty()) {
                errors.add('Failed to create tree: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) jsonMap.get('sha');
    }

    private static String executeCreateCommit(String baseUrl, String token, String owner, String repo, String message, String treeSha, String parentCommitSha, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/commits';
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('message', message);
        payload.put('tree', treeSha);
        payload.put('parents', new List<String>{ parentCommitSha });
        HttpRequest req = createHttpRequest(endpoint, 'POST', token, JSON.serialize(payload));
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 201) {
            if (errors.isEmpty()) {
                errors.add('Failed to create commit: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) jsonMap.get('sha');
    }

    private static Boolean executeUpdateReference(String baseUrl, String token, String owner, String repo, String featureBranchName, String newCommitSha, List<String> errors) {
        // First try to create reference directly (works if branch doesn't exist)
        String createEndpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/refs';
        Map<String, Object> createPayload = new Map<String, Object>();
        createPayload.put('ref', 'refs/heads/' + featureBranchName);
        createPayload.put('sha', newCommitSha);
        
        HttpRequest req = createHttpRequest(createEndpoint, 'POST', token, JSON.serialize(createPayload));
        HttpResponse res = sendHttpRequest(req, new List<String>()); // Silent failure check
        
        if (res != null && res.getStatusCode() == 201) {
            return true;
        }
        
        // If reference exists, patch it to point to new commit
        String updateEndpoint = baseUrl + '/repos/' + owner + '/' + repo + '/git/refs/heads/' + featureBranchName;
        Map<String, Object> updatePayload = new Map<String, Object>();
        updatePayload.put('sha', newCommitSha);
        updatePayload.put('force', true);
        
        HttpRequest updateReq = createHttpRequest(updateEndpoint, 'PATCH', token, JSON.serialize(updatePayload));
        HttpResponse updateRes = sendHttpRequest(updateReq, errors);
        if (updateRes == null || (updateRes.getStatusCode() != 200 && updateRes.getStatusCode() != 201)) {
            if (errors.isEmpty()) {
                errors.add('Failed to update branch reference: ' + (updateRes != null ? updateRes.getBody() : 'Connection timeout'));
            }
            return false;
        }
        return true;
    }

    private static Map<String, Object> executeCreatePullRequest(String baseUrl, String token, String owner, String repo, String title, String head, String base, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/pulls';
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('title', title);
        payload.put('head', head);
        payload.put('base', base);
        payload.put('body', 'PR created from Salesforce DevOps Platform');
        
        HttpRequest req = createHttpRequest(endpoint, 'POST', token, JSON.serialize(payload));
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 201) {
            if (errors.isEmpty()) {
                errors.add('Failed to create Pull Request: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ----------------------------------------------------
    // HTTP Helpers
    // ----------------------------------------------------

    private static HttpRequest createHttpRequest(String endpoint, String method, String token, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setTimeout(120000); // 120 seconds timeout
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('User-Agent', 'Salesforce-Release-Management');
        if (String.isNotBlank(token)) {
            req.setHeader('Authorization', 'Bearer ' + token);
        }
        if (String.isNotBlank(body)) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        return req;
    }

    private static HttpResponse sendHttpRequest(HttpRequest req, List<String> errors) {
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() >= 300) {
                handleHttpError(res, errors);
            }
            return res;
        } catch (CalloutException ex) {
            errors.add('Connection Failure: Network timeout or endpoint not reachable. ' + ex.getMessage());
            return null;
        } catch (Exception ex) {
            errors.add('Request Failure: ' + ex.getMessage());
            return null;
        }
    }

    private static void handleHttpError(HttpResponse res, List<String> errors) {
        if (res == null) {
            errors.add('Connection Failure: Timeout or network issue occurred.');
            return;
        }
        Integer code = res.getStatusCode();
        String body = res.getBody();
        String errorMsg = 'GitHub request failed (Status ' + code + ')';
        try {
            Map<String, Object> bodyMap = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (bodyMap.containsKey('message')) {
                errorMsg = (String) bodyMap.get('message');
            }
        } catch (Exception e) {}

        switch on code {
            when 401 {
                errors.add('Authentication Failure: GitHub API token is invalid or expired.');
            }
            when 403 {
                errors.add('Access Denied: Rate limit exceeded or insufficient permissions. ' + errorMsg);
            }
            when 404 {
                errors.add('Repository or resource not found on GitHub. ' + errorMsg);
            }
            when 409 {
                errors.add('Conflict: Merge conflict or reference update block. ' + errorMsg);
            }
            when 422 {
                errors.add('Validation Failed: Invalid payload parameters. ' + errorMsg);
            }
            when 429 {
                errors.add('Rate Limit Exceeded: Too many requests to GitHub. ' + errorMsg);
            }
            when 500 {
                errors.add('GitHub Server Error: GitHub service encountered an internal error.');
            }
            when else {
                errors.add(errorMsg);
            }
        }
    }

    private static Credentials__c queryCredentials() {
        // Try searching for a credential record with instance URL matching github
        List<Credentials__c> creds = [
            SELECT Id, Access_Token__c, Instance_URL__c
            FROM Credentials__c
            WHERE Instance_URL__c LIKE '%github.com%'
            LIMIT 1
        ];
        if (creds.isEmpty()) {
            creds = [
                SELECT Id, Access_Token__c, Instance_URL__c
                FROM Credentials__c
                LIMIT 1
            ];
        }
        return creds.isEmpty() ? null : creds[0];
    }

    // ----------------------------------------------------
    // Validations & DTO Processing
    // ----------------------------------------------------

    private List<String> validateContext(GitCommitContext context, String commitMessage) {
        List<String> errors = new List<String>();

        if (context == null) {
            errors.add('Commit Context is null.');
            return errors;
        }

        // Validate String inputs (reject null/blank and trim them)
        validateRequiredString('Repository Name', context.repositoryName, errors);
        validateRequiredString('Repository Owner', context.repositoryOwner, errors);
        validateRequiredString('Repository URL', context.repositoryUrl, errors);
        validateRequiredString('Default Branch', context.defaultBranch, errors);
        validateRequiredString('Provider Type', context.providerType, errors);
        validateRequiredString('Developer Username', context.developerUsername, errors);
        validateRequiredString('Feature Branch Name', context.featureBranchName, errors);
        validateRequiredString('Commit Message', commitMessage, errors);

        // Validate Execution Timestamp
        if (context.executionTimestamp == null) {
            errors.add('Execution Timestamp is missing.');
        }

        // Validate Selected Metadata
        if (context.selectedMetadata == null || context.selectedMetadata.isEmpty()) {
            errors.add('Selected Metadata collection is empty.');
        }

        return errors;
    }

    private void validateRequiredString(String fieldName, String value, List<String> errors) {
        if (value == null || String.isBlank(value.trim())) {
            errors.add(fieldName + ' configuration is missing or blank.');
        }
    }

    private List<GitMetadataItem> buildMetadataPackage(List<GitMetadataItem> rawMetadata, List<String> errors) {
        List<GitMetadataItem> normalized = new List<GitMetadataItem>();
        if (rawMetadata == null) {
            return normalized;
        }

        for (Integer i = 0; i < rawMetadata.size(); i++) {
            GitMetadataItem raw = rawMetadata[i];
            if (raw == null) {
                errors.add('Metadata item at index ' + i + ' is null.');
                continue;
            }

            Boolean isValid = true;
            if (String.isBlank(raw.metadataType)) {
                errors.add('Metadata Type is missing at index ' + i + '.');
                isValid = false;
            }
            if (String.isBlank(raw.apiName)) {
                errors.add('Metadata API Name is missing at index ' + i + '.');
                isValid = false;
            }
            if (String.isBlank(raw.filePath)) {
                errors.add('File Path is missing at index ' + i + '.');
                isValid = false;
            }
            if (String.isBlank(raw.deploymentAction)) {
                errors.add('Deployment Action is missing at index ' + i + '.');
                isValid = false;
            }

            if (isValid) {
                GitMetadataItem item = new GitMetadataItem();
                item.metadataType = raw.metadataType.trim();
                item.apiName = raw.apiName.trim();
                item.filePath = raw.filePath.trim();
                item.deploymentAction = raw.deploymentAction.trim();
                normalized.add(item);
            }
        }
        return normalized;
    }

    // Unused placeholder builders from phase-2 preserved/modified as needed
    private Map<String, Object> buildBranchPayload(String featureBranchName) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('ref', 'refs/heads/' + (featureBranchName != null ? featureBranchName.trim() : ''));
        payload.put('sha', 'TEMP_PARENT_SHA');
        return payload;
    }

    private Map<String, Object> buildTreePayload(List<GitMetadataItem> metadataItems) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('base_tree', 'TEMP_BASE_TREE_SHA');
        List<Map<String, Object>> treeNodeList = new List<Map<String, Object>>();
        for (GitMetadataItem item : metadataItems) {
            Map<String, Object> node = new Map<String, Object>();
            node.put('path', item.filePath);
            node.put('mode', '100644');
            node.put('type', 'blob');
            node.put('sha', 'TEMP_BLOB_SHA');
            treeNodeList.add(node);
        }
        payload.put('tree', treeNodeList);
        return payload;
    }

    private Map<String, Object> buildCommitPayload(String commitMessage) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('message', commitMessage != null ? commitMessage.trim() : '');
        payload.put('tree', 'TEMP_NEW_TREE_SHA');
        payload.put('parents', new List<String>{ 'TEMP_PARENT_SHA' });
        return payload;
    }

    private Map<String, Object> buildReferencePayload() {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('sha', 'TEMP_NEW_COMMIT_SHA');
        payload.put('force', true);
        return payload;
    }

    private Map<String, Object> buildPushPayload(String featureBranchName) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('branch', featureBranchName != null ? featureBranchName.trim() : '');
        payload.put('updateRef', buildReferencePayload());
        return payload;
    }

    private Map<String, Object> buildPullRequestPayload(String commitMessage, String featureBranchName, String defaultBranch) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('title', commitMessage != null ? commitMessage.trim() : '');
        payload.put('head', featureBranchName != null ? featureBranchName.trim() : '');
        payload.put('base', defaultBranch != null ? defaultBranch.trim() : '');
        return payload;
    }
}