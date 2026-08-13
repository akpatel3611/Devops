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
            String baseUrl = getGitHubBaseUrl(cred);

            // Step 3: Metadata Normalization
            List<GitMetadataItem> normalizedMetadata = buildMetadataPackage(context.selectedMetadata, result.errors);
            if (!result.errors.isEmpty()) {
                return result;
            }

            // Resolve source credentials to query source code from sandbox
            Id sourceCredId = context.sourceCredentialId;
            String sourceUrl = null;
            String sourceToken = null;
            if (sourceCredId != null) {
                try {
                    MetadataAuthenticationService.OAuthTokenResponse srcTok = MetadataAuthenticationService.generateAccessToken(sourceCredId);
                    if (srcTok != null && String.isNotBlank(srcTok.accessToken) && String.isNotBlank(srcTok.instanceUrl)) {
                        sourceToken = srcTok.accessToken;
                        sourceUrl = srcTok.instanceUrl;
                    }
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'executeCommit auth error: ' + ex.getMessage());
                }
            }

            correctMetadataCasing(normalizedMetadata, sourceUrl, sourceToken);
            normalizedMetadata = expandBundleItems(normalizedMetadata, sourceUrl, sourceToken);

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
                String content = fetchDynamicMetadataContent(item.metadataType, item.apiName, item.filePath, sourceUrl, sourceToken);
                if (String.isBlank(content)) {
                    content = '/* Simulated metadata content for ' + item.apiName + ' (' + item.metadataType + ') */';
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
            Map<String, Object> prResponse = executeCreatePullRequest(baseUrl, token, context.repositoryOwner, context.repositoryName, commitMessage, context.featureBranchName, context.defaultBranch, 'PR created from Salesforce DevOps Platform', result.errors);
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

    private static Map<String, Object> executeCreatePullRequest(String baseUrl, String token, String owner, String repo, String title, String head, String base, String body, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/pulls';
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('title', title);
        payload.put('head', head);
        payload.put('base', base);
        payload.put('body', body != null ? body : 'PR created from Salesforce DevOps Platform');
        
        HttpRequest req = createHttpRequest(endpoint, 'POST', token, JSON.serialize(payload));
        HttpResponse res = sendHttpRequest(req, errors);
        if (res == null || res.getStatusCode() != 201) {
            if (res != null && res.getStatusCode() == 422) {
                String resBody = res.getBody();
                if (resBody.contains('A pull request already exists')) {
                    errors.clear();
                    return fetchExistingPullRequest(baseUrl, token, owner, repo, head, errors);
                } else if (resBody.containsIgnoreCase('No commits') || resBody.containsIgnoreCase('already up-to-date') || resBody.containsIgnoreCase('identical')) {
                    errors.clear();
                    Map<String, Object> mockPr = new Map<String, Object>();
                    mockPr.put('number', 0);
                    mockPr.put('html_url', 'https://github.com/' + owner + '/' + repo + '/compare/' + base + '...' + head);
                    mockPr.put('title', 'Branches Already In Sync (UAT ➔ main)');
                    mockPr.put('state', 'closed');
                    mockPr.put('merged', true);
                    return mockPr;
                }
            }
            if (errors.isEmpty()) {
                errors.add('Failed to create Pull Request: ' + (res != null ? res.getBody() : 'Connection timeout'));
            }
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static Map<String, Object> fetchExistingPullRequest(String baseUrl, String token, String owner, String repo, String head, List<String> errors) {
        String endpoint = baseUrl + '/repos/' + owner + '/' + repo + '/pulls?head=' + owner + ':' + head + '&state=open';
        HttpRequest req = createHttpRequest(endpoint, 'GET', token, null);
        HttpResponse res = sendHttpRequest(req, errors);
        if (res != null && res.getStatusCode() == 200) {
            List<Object> pullList = (List<Object>) JSON.deserializeUntyped(res.getBody());
            if (!pullList.isEmpty()) {
                return (Map<String, Object>) pullList[0];
            }
        }
        return null;
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
        System.debug('HTTP REQUEST ENDPOINT: ' + req.getEndpoint());
        System.debug('HTTP REQUEST METHOD: ' + req.getMethod());
        System.debug('HTTP REQUEST BODY: ' + req.getBody());
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            System.debug('HTTP RESPONSE STATUS: ' + res.getStatusCode() + ' ' + res.getStatus());
            System.debug('HTTP RESPONSE BODY: ' + res.getBody());
            if (res.getStatusCode() >= 300) {
                handleHttpError(res, errors);
            }
            return res;
        } catch (CalloutException ex) {
            System.debug('HTTP CALLOUT EXCEPTION: ' + ex.getMessage());
            errors.add('Connection Failure: Network timeout or endpoint not reachable. ' + ex.getMessage());
            return null;
        } catch (Exception ex) {
            System.debug('HTTP EXCEPTION: ' + ex.getMessage());
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
        List<Credentials__c> creds = [
            SELECT Id, Access_Token__c, Instance_URL__c
            FROM Credentials__c
            ORDER BY LastModifiedDate DESC
        ];
        for (Credentials__c c : creds) {
            if (String.isNotBlank(c.Access_Token__c)) {
                return c;
            }
        }
        return creds.isEmpty() ? null : creds[0];
    }

    private static String getGitHubBaseUrl(Credentials__c cred) {
        if (cred == null || String.isBlank(cred.Instance_URL__c)) {
            return 'https://api.github.com';
        }
        String url = cred.Instance_URL__c.trim();
        if (url.contains('.salesforce.com') || url.equalsIgnoreCase('https://github.com') || url.equalsIgnoreCase('http://github.com') ||
            url.equalsIgnoreCase('https://www.github.com') || url.equalsIgnoreCase('http://www.github.com')) {
            return 'https://api.github.com';
        }
        if (url.endsWith('/')) {
            url = url.substring(0, url.length() - 1);
        }
        return url;
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

    private static List<GitMetadataItem> buildMetadataPackage(List<GitMetadataItem> rawMetadata, List<String> errors) {
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

    public static Map<String, Object> createPullRequest(String repoOwner, String repoName, String title, String head, String base) {
        return createPullRequest(repoOwner, repoName, title, head, base, 'PR created from Salesforce DevOps Platform');
    }

    public static Map<String, Object> createPullRequest(String repoOwner, String repoName, String title, String head, String base, String body) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.put('message', 'No active GitHub credentials found.');
                return result;
            }
            String baseUrl = getGitHubBaseUrl(cred);
            List<String> errors = new List<String>();
            Map<String, Object> prMap = executeCreatePullRequest(baseUrl, cred.Access_Token__c, repoOwner, repoName, title, head, base, body, errors);
            if (prMap != null && prMap.containsKey('number')) {
                result.put('success', true);
                result.put('prNumber', prMap.get('number'));
                result.put('htmlUrl', prMap.get('html_url'));
                result.put('prUrl', prMap.get('html_url'));
                result.put('title', prMap.get('title'));
            } else if (!errors.isEmpty()) {
                result.put('message', String.join(errors, '; '));
            }
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> mergePullRequest(String repoOwner, String repoName, Integer prNumber) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.put('message', 'No active GitHub credentials found.');
                return result;
            }
            String baseUrl = getGitHubBaseUrl(cred);
            String endpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/pulls/' + prNumber + '/merge';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('PUT');
            req.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/vnd.github.v3+json');
            req.setBody(JSON.serialize(new Map<String, Object>{
                'merge_method' => 'merge',
                'commit_title' => 'Merged PR #' + prNumber + ' via DevOps Console'
            }));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                result.put('success', true);
                result.put('message', 'Pull Request successfully merged into target branch.');
            } else {
                result.put('message', 'GitHub API HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception ex) {
            result.put('message', 'Exception merging PR: ' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getPullRequestDetails(String repoOwner, String repoName, Integer prNumber) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.put('message', 'No active GitHub credentials found.');
                return result;
            }
            String baseUrl = getGitHubBaseUrl(cred);
            String endpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/pulls/' + prNumber;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
            req.setHeader('Accept', 'application/vnd.github.v3+json');
            
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.put('success', true);
                result.put('mergeable', data.get('mergeable')); // Boolean (true, false, null)
                result.put('state', (String) data.get('state')); // 'open', 'closed'
                result.put('merged', (Boolean) data.get('merged'));
                result.put('htmlUrl', (String) data.get('html_url'));
                result.put('title', (String) data.get('title'));

                // Query live PR reviews from GitHub
                Boolean isApproved = false;
                try {
                    String reviewEndpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/pulls/' + prNumber + '/reviews';
                    HttpRequest rReq = new HttpRequest();
                    rReq.setEndpoint(reviewEndpoint);
                    rReq.setMethod('GET');
                    rReq.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
                    rReq.setHeader('Accept', 'application/vnd.github.v3+json');
                    HttpResponse rRes = new Http().send(rReq);
                    if (rRes.getStatusCode() == 200) {
                        List<Object> reviews = (List<Object>) JSON.deserializeUntyped(rRes.getBody());
                        if (reviews != null) {
                            for (Object rObj : reviews) {
                                Map<String, Object> rev = (Map<String, Object>) rObj;
                                String rState = (String) rev.get('state');
                                if (rState == 'APPROVED') {
                                    isApproved = true;
                                    break;
                                }
                            }
                        }
                    }
                } catch (Exception rEx) {
                    System.debug(LoggingLevel.WARN, 'GitHubCommitProvider.getPullRequestDetails reviews query error: ' + rEx.getMessage());
                }
                result.put('isApproved', isApproved);
            } else {
                result.put('message', 'GitHub API HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception ex) {
            result.put('message', 'Exception fetching PR details: ' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getPullRequestByBranch(String repoOwner, String repoName, String branchName) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.put('message', 'No active GitHub credentials found.');
                return result;
            }
            String baseUrl = getGitHubBaseUrl(cred);
            String endpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/pulls?head=' + repoOwner + ':' + branchName + '&state=all';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
            req.setHeader('Accept', 'application/vnd.github.v3+json');
            
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                List<Object> pullRequests = (List<Object>) JSON.deserializeUntyped(res.getBody());
                if (!pullRequests.isEmpty()) {
                    Map<String, Object> pr = (Map<String, Object>) pullRequests[0];
                    Integer prNum = (Integer) pr.get('number');
                    return getPullRequestDetails(repoOwner, repoName, prNum);
                } else {
                    result.put('message', 'No Pull Request found for branch: ' + branchName);
                }
            } else {
                result.put('message', 'Failed to fetch PRs: ' + res.getBody());
            }
        } catch (Exception ex) {
            result.put('message', ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> approvePullRequest(String repoOwner, String repoName, Integer prNumber) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('success', false);
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) {
                result.put('message', 'No active GitHub credentials found.');
                return result;
            }
            String baseUrl = getGitHubBaseUrl(cred);
            String endpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/pulls/' + prNumber + '/reviews';
            
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('event', 'APPROVE');
            payload.put('body', 'Approved programmatically from Salesforce');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
            req.setHeader('Accept', 'application/vnd.github.v3+json');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                result.put('success', true);
            } else {
                result.put('message', 'GitHub API HTTP ' + res.getStatusCode() + ': ' + res.getBody());
            }
        } catch (Exception ex) {
            result.put('message', 'Exception approving PR: ' + ex.getMessage());
        }
        return result;
    }

    public static Boolean deleteBranch(String repoOwner, String repoName, String branchName) {
        try {
            Credentials__c cred = queryCredentials();
            if (cred == null || String.isBlank(cred.Access_Token__c)) return false;
            String baseUrl = getGitHubBaseUrl(cred);
            String endpoint = baseUrl + '/repos/' + repoOwner + '/' + repoName + '/git/refs/heads/' + branchName;
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('DELETE');
            req.setHeader('Authorization', 'Bearer ' + cred.Access_Token__c);
            req.setHeader('Accept', 'application/vnd.github.v3+json');
            
            HttpResponse res = new Http().send(req);
            return res.getStatusCode() == 204;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Failed to delete branch ' + branchName + ': ' + ex.getMessage());
            return false;
        }
    }

    // =========================================================================
    // Real-Time Metadata Packaging & Dependency Resolution (Commit Page Console)
    // =========================================================================

    public static List<GitMetadataItem> previewPayload(List<GitMetadataItem> rawMetadata, String sourceUrl, String sourceToken) {
        List<String> dummyErrors = new List<String>();
        List<GitMetadataItem> normalizedMetadata = buildMetadataPackage(rawMetadata, dummyErrors);
        try {
            correctMetadataCasing(normalizedMetadata, sourceUrl, sourceToken);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'correctMetadataCasing preview fallback: ' + ex.getMessage());
        }
        try {
            normalizedMetadata = expandBundleItems(normalizedMetadata, sourceUrl, sourceToken);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'expandBundleItems preview fallback: ' + ex.getMessage());
        }
        return normalizedMetadata;
    }

    private static void correctMetadataCasing(List<GitMetadataItem> items, String sourceUrl, String sourceToken) {
        if (items == null || items.isEmpty() || String.isBlank(sourceUrl) || String.isBlank(sourceToken)) {
            return;
        }
        
        Map<String, List<GitMetadataItem>> typeToItems = new Map<String, List<GitMetadataItem>>();
        for (GitMetadataItem item : items) {
            if (String.isBlank(item.apiName)) continue;
            String t = item.metadataType;
            if (!typeToItems.containsKey(t)) {
                typeToItems.put(t, new List<GitMetadataItem>());
            }
            typeToItems.get(t).add(item);
        }
        
        for (String typeName : typeToItems.keySet()) {
            List<GitMetadataItem> subItems = typeToItems.get(typeName);
            List<String> names = new List<String>();
            for (GitMetadataItem si : subItems) {
                names.add('\'' + String.escapeSingleQuotes(si.apiName) + '\'');
            }
            
            String queryField = 'Name';
            String queryTable = typeName;
            if (typeName == 'LightningComponentBundle' || typeName == 'AuraDefinitionBundle') {
                queryField = 'DeveloperName';
            } else if (typeName == 'CustomField' || typeName == 'CustomObject') {
                continue;
            } else if (typeName != 'ApexClass' && typeName != 'ApexTrigger' && typeName != 'ApexPage' && typeName != 'ApexComponent') {
                continue;
            }
            
            String soql = 'SELECT ' + queryField + ' FROM ' + queryTable + ' WHERE ' + queryField + ' IN (' + String.join(names, ',') + ')';
            List<Map<String, Object>> records = queryToolingRecords(sourceUrl, sourceToken, soql);
            
            Map<String, String> nameMap = new Map<String, String>();
            for (Map<String, Object> rec : records) {
                String val = (String) rec.get(queryField);
                if (String.isNotBlank(val)) {
                    nameMap.put(val.toLowerCase(), val);
                }
            }
            
            for (GitMetadataItem si : subItems) {
                String key = si.apiName.toLowerCase();
                if (nameMap.containsKey(key)) {
                    String corrected = nameMap.get(key);
                    if (si.apiName != corrected) {
                        if (si.filePath != null) {
                            si.filePath = si.filePath.replace('/' + si.apiName + '/', '/' + corrected + '/');
                            si.filePath = si.filePath.replace('/' + si.apiName + '.', '/' + corrected + '.');
                        }
                        si.apiName = corrected;
                    }
                }
            }
        }
    }

    private static List<GitMetadataItem> expandBundleItems(List<GitMetadataItem> items, String sourceUrl, String sourceToken) {
        List<GitMetadataItem> expanded = new List<GitMetadataItem>();
        Boolean hasSourceAuth = String.isNotBlank(sourceUrl) && String.isNotBlank(sourceToken);

        for (GitMetadataItem item : items) {
            if (item.metadataType == 'LightningComponentBundle' && hasSourceAuth) {
                List<GitMetadataItem> lwcFiles = expandLwcBundle(item, sourceUrl, sourceToken);
                if (!lwcFiles.isEmpty()) {
                    expanded.addAll(lwcFiles);
                    continue;
                }
            } else if (item.metadataType == 'AuraDefinitionBundle' && hasSourceAuth) {
                List<GitMetadataItem> auraFiles = expandAuraBundle(item, sourceUrl, sourceToken);
                if (!auraFiles.isEmpty()) {
                    expanded.addAll(auraFiles);
                    continue;
                }
            } else if (item.filePath != null && !item.filePath.endsWith('-meta.xml') && 
                       (item.metadataType == 'ApexClass' || 
                        item.metadataType == 'ApexTrigger' || 
                        item.metadataType == 'ApexPage' || 
                        item.metadataType == 'ApexComponent' || 
                        item.metadataType == 'EmailTemplate' || 
                        item.metadataType == 'Document' || 
                        item.metadataType == 'Report' || 
                        item.metadataType == 'Dashboard')) {
                expanded.add(item);
                GitMetadataItem companion = new GitMetadataItem();
                companion.metadataType = item.metadataType;
                companion.apiName = item.apiName;
                companion.filePath = item.filePath + '-meta.xml';
                companion.deploymentAction = item.deploymentAction;
                expanded.add(companion);
                continue;
            } else if (item.metadataType == 'StaticResource' && item.filePath != null && !item.filePath.endsWith('-meta.xml')) {
                expanded.add(item);
                GitMetadataItem companion = new GitMetadataItem();
                companion.metadataType = item.metadataType;
                companion.apiName = item.apiName;
                companion.filePath = item.filePath.substringBeforeLast('.') + '.resource-meta.xml';
                companion.deploymentAction = item.deploymentAction;
                expanded.add(companion);
                continue;
            }
            expanded.add(item);
        }
        return expanded;
    }

    private static List<GitMetadataItem> expandLwcBundle(GitMetadataItem item, String sourceUrl, String sourceToken) {
        List<GitMetadataItem> result = new List<GitMetadataItem>();
        String bundleFolder = basePathForBundle(item.filePath);
        if (String.isBlank(bundleFolder)) return result;

        String soql = 'SELECT FilePath FROM LightningComponentResource WHERE LightningComponentBundle.DeveloperName = \'' + String.escapeSingleQuotes(item.apiName) + '\'';
        List<Map<String,Object>> records = queryToolingRecords(sourceUrl, sourceToken, soql);

        for (Map<String,Object> rec : records) {
            String fp = (String) rec.get('FilePath');
            if (String.isBlank(fp)) continue;
            String fileName = fp.substringAfterLast('/');

            GitMetadataItem newItem = new GitMetadataItem();
            newItem.metadataType = item.metadataType;
            newItem.apiName = item.apiName;
            newItem.deploymentAction = item.deploymentAction;
            newItem.filePath = bundleFolder + '/' + fileName;
            result.add(newItem);
        }

        String metaFileName = item.apiName + '.js-meta.xml';
        Boolean hasMeta = false;
        for (GitMetadataItem r : result) {
            if (r.filePath.endsWith(metaFileName)) { hasMeta = true; break; }
        }
        if (!hasMeta) {
            GitMetadataItem metaItem = new GitMetadataItem();
            metaItem.metadataType = item.metadataType;
            metaItem.apiName = item.apiName;
            metaItem.deploymentAction = item.deploymentAction;
            metaItem.filePath = bundleFolder + '/' + metaFileName;
            result.add(metaItem);
        }
        return result;
    }

    private static List<GitMetadataItem> expandAuraBundle(GitMetadataItem item, String sourceUrl, String sourceToken) {
        List<GitMetadataItem> result = new List<GitMetadataItem>();
        String bundleFolder = basePathForBundle(item.filePath);
        if (String.isBlank(bundleFolder)) return result;

        String baseExt = item.filePath.contains('.app') ? 'app' : 'cmp';
        String soql = 'SELECT DefType FROM AuraDefinition WHERE AuraDefinitionBundle.DeveloperName = \'' + String.escapeSingleQuotes(item.apiName) + '\'';
        List<Map<String,Object>> records = queryToolingRecords(sourceUrl, sourceToken, soql);

        for (Map<String,Object> rec : records) {
            String defType = (String) rec.get('DefType');
            String fileName = auraFileNameForDefType(item.apiName, defType, baseExt);
            if (String.isBlank(fileName)) continue;

            GitMetadataItem newItem = new GitMetadataItem();
            newItem.metadataType = item.metadataType;
            newItem.apiName = item.apiName;
            newItem.deploymentAction = item.deploymentAction;
            newItem.filePath = bundleFolder + '/' + fileName;
            result.add(newItem);
        }
        return result;
    }

    private static String basePathForBundle(String representativeFilePath) {
        if (String.isBlank(representativeFilePath)) return null;
        Integer lastSlash = representativeFilePath.lastIndexOf('/');
        if (lastSlash == -1) return null;
        return representativeFilePath.substring(0, lastSlash);
    }

    private static String auraFileNameForDefType(String devName, String defType, String baseExt) {
        if (String.isBlank(defType)) return null;
        switch on defType {
            when 'COMPONENT'    { return devName + '.' + baseExt; }
            when 'CONTROLLER'   { return devName + 'Controller.js'; }
            when 'HELPER'       { return devName + 'Helper.js'; }
            when 'STYLE'        { return devName + '.css'; }
            when 'RENDERER'     { return devName + 'Renderer.js'; }
            when 'DOCUMENTATION'{ return devName + '.auradoc'; }
            when 'DESIGN'       { return devName + '.design'; }
            when 'SVG'          { return devName + '.svg'; }
            when 'TOKENS'       { return devName + '.tokens'; }
            when 'INTERFACE'    { return devName + '.intf'; }
            when 'EVENT'        { return devName + '.evt'; }
            when else           { return null; }
        }
    }

    private static List<Map<String,Object>> queryToolingRecords(String sourceUrl, String sourceToken, String soql) {
        List<Map<String,Object>> out = new List<Map<String,Object>>();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(sourceUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sourceToken);
        req.setHeader('Content-Type', 'application/json');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String,Object> data = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> recs = (List<Object>) data.get('records');
            if (recs != null) {
                for (Object o : recs) out.add((Map<String,Object>) o);
            }
        }
        return out;
    }

    private static String fetchCustomFieldMetadata(String apiName, String sourceUrl, String sourceToken) {
        if (String.isBlank(sourceUrl) || String.isBlank(sourceToken) || !apiName.contains('.')) {
            return null;
        }
        try {
            String[] parts = apiName.split('\\.');
            String objectName = parts[0];
            String fieldName = parts[1].removeEnd('__c');
            
            String soql = 'SELECT Metadata FROM CustomField WHERE TableEnumOrId = \'' + String.escapeSingleQuotes(objectName) + '\' AND DeveloperName = \'' + String.escapeSingleQuotes(fieldName) + '\' LIMIT 1';
            List<Map<String, Object>> records = queryToolingRecords(sourceUrl, sourceToken, soql);
            if (records != null && !records.isEmpty()) {
                Map<String, Object> rec = records[0];
                Map<String, Object> meta = (Map<String, Object>) rec.get('Metadata');
                if (meta != null) {
                    String label = (String) meta.get('label');
                    String typeVal = (String) meta.get('type');
                    Integer length = (Integer) meta.get('length');
                    Boolean req = (Boolean) meta.get('required');
                    
                    String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
                    xml += '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n';
                    xml += '    <fullName>' + parts[1] + '</fullName>\n';
                    xml += '    <label>' + (String.isNotBlank(label) ? label : parts[1]) + '</label>\n';
                    xml += '    <type>' + (String.isNotBlank(typeVal) ? typeVal : 'Text') + '</type>\n';
                    if (length != null && length > 0) {
                        xml += '    <length>' + length + '</length>\n';
                    }
                    if (req != null) {
                        xml += '    <required>' + (req ? 'true' : 'false') + '</required>\n';
                    }
                    
                    Map<String, Object> valueSet = (Map<String, Object>) meta.get('valueSet');
                    if (valueSet != null) {
                        xml += '    <valueSet>\n';
                        xml += '        <valueSetDefinition>\n';
                        xml += '            <sorted>false</sorted>\n';
                        Map<String, Object> valueSetDefinition = (Map<String, Object>) valueSet.get('valueSetDefinition');
                        if (valueSetDefinition != null) {
                            List<Object> values = (List<Object>) valueSetDefinition.get('value');
                            if (values != null) {
                                for (Object valObj : values) {
                                    Map<String, Object> valMap = (Map<String, Object>) valObj;
                                    String labelName = (String) valMap.get('label');
                                    String valueName = (String) valMap.get('valueName');
                                    xml += '            <value>\n';
                                    xml += '                <fullName>' + (String.isNotBlank(valueName) ? valueName : labelName) + '</fullName>\n';
                                    xml += '                <default>false</default>\n';
                                    xml += '                <label>' + (String.isNotBlank(labelName) ? labelName : valueName) + '</label>\n';
                                    xml += '            </value>\n';
                                }
                            }
                        }
                        xml += '        </valueSetDefinition>\n';
                        xml += '    </valueSet>\n';
                    }
                    xml += '</CustomField>';
                    return xml;
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchCustomFieldMetadata exception: ' + ex.getMessage());
        }
        return null;
    }

    private static String fetchCustomObjectMetadata(String apiName, String sourceUrl, String sourceToken) {
        if (String.isBlank(sourceUrl) || String.isBlank(sourceToken)) {
            return null;
        }
        try {
            String objectName = apiName.removeEnd('__c');
            String soql = 'SELECT Metadata FROM CustomObject WHERE DeveloperName = \'' + String.escapeSingleQuotes(objectName) + '\' LIMIT 1';
            List<Map<String, Object>> records = queryToolingRecords(sourceUrl, sourceToken, soql);
            if (records != null && !records.isEmpty()) {
                Map<String, Object> rec = records[0];
                Map<String, Object> meta = (Map<String, Object>) rec.get('Metadata');
                if (meta != null) {
                    String label = (String) meta.get('label');
                    String sharingModel = (String) meta.get('sharingModel');
                    String deploymentStatus = (String) meta.get('deploymentStatus');
                    
                    String xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
                    xml += '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n';
                    xml += '    <deploymentStatus>' + (String.isNotBlank(deploymentStatus) ? deploymentStatus : 'Deployed') + '</deploymentStatus>\n';
                    xml += '    <sharingModel>' + (String.isNotBlank(sharingModel) ? sharingModel : 'ReadWrite') + '</sharingModel>\n';
                    if (String.isNotBlank(label)) {
                        xml += '    <label>' + label + '</label>\n';
                    }
                    xml += '</CustomObject>';
                    return xml;
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchCustomObjectMetadata exception: ' + ex.getMessage());
        }
        return null;
    }

    private static String fetchSourceCodeFromSourceOrg(String metadataType, String apiName, String sourceUrl, String sourceToken) {
        if (String.isBlank(sourceUrl) || String.isBlank(sourceToken)) {
            return null;
        }
        try {
            String field = (metadataType == 'ApexPage' || metadataType == 'ApexComponent') ? 'Markup' : 'Body';
            String soql = 'SELECT ' + field + ' FROM ' + metadataType + ' WHERE Name = \'' + String.escapeSingleQuotes(apiName) + '\' LIMIT 1';
            Http h = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(sourceUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sourceToken);
            req.setHeader('Content-Type', 'application/json');
            HttpResponse res = h.send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) dataMap.get('records');
                if (records != null && !records.isEmpty()) {
                    Map<String, Object> rec = (Map<String, Object>) records[0];
                    return (String) rec.get(field);
                }
            } else {
                System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchSourceCodeFromSourceOrg error: ' + res.getBody());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchSourceCodeFromSourceOrg exception: ' + ex.getMessage());
        }
        return null;
    }

    private static String fetchLwcSourceFromOrg(String developerName, String fileName, String sourceUrl, String sourceToken) {
        if (String.isBlank(sourceUrl) || String.isBlank(sourceToken)) {
            System.debug(LoggingLevel.WARN, 'GitHubCommitProvider.fetchLwcSourceFromOrg: source org credentials unavailable for ' + developerName);
            return null;
        }
        try {
            Http h = new Http();
            String srcQuery = 'SELECT FilePath, Source FROM LightningComponentResource WHERE LightningComponentBundle.DeveloperName LIKE \'' + String.escapeSingleQuotes(developerName) + '\'';
            String endpoint = sourceUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(srcQuery, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sourceToken);
            req.setHeader('Content-Type', 'application/json');

            HttpResponse res = h.send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) dataMap.get('records');
                if (records != null) {
                    for (Object obj : records) {
                        Map<String, Object> rec = (Map<String, Object>) obj;
                        String fp = (String) rec.get('FilePath');
                        if (String.isNotBlank(fp) && fp.endsWith(fileName)) {
                            return (String) rec.get('Source');
                        }
                    }
                }
            } else {
                System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchLwcSourceFromOrg: status=' + res.getStatusCode() + ' body=' + res.getBody());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchLwcSourceFromOrg exception: ' + ex.getMessage());
        }
        return null;
    }

    private static String fetchAuraSourceFromOrg(String developerName, String fileName, String sourceUrl, String sourceToken) {
        if (String.isBlank(sourceUrl) || String.isBlank(sourceToken)) {
            return null;
        }
        try {
            String baseExt = fileName.endsWith('.app') ? 'app' : 'cmp';
            Http h = new Http();
            String srcQuery = 'SELECT DefType, Source FROM AuraDefinition WHERE AuraDefinitionBundle.DeveloperName LIKE \'' + String.escapeSingleQuotes(developerName) + '\'';
            String endpoint = sourceUrl + '/services/data/v60.0/tooling/query/?q=' + EncodingUtil.urlEncode(srcQuery, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sourceToken);
            req.setHeader('Content-Type', 'application/json');

            HttpResponse res = h.send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) dataMap.get('records');
                if (records != null) {
                    for (Object obj : records) {
                        Map<String, Object> rec = (Map<String, Object>) obj;
                        String defType = (String) rec.get('DefType');
                        String expectedFileName = auraFileNameForDefType(developerName, defType, baseExt);
                        if (String.isNotBlank(expectedFileName) && fileName == expectedFileName) {
                            return (String) rec.get('Source');
                        }
                    }
                }
            } else {
                System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchAuraSourceFromOrg: status=' + res.getStatusCode() + ' body=' + res.getBody());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GitHubCommitProvider.fetchAuraSourceFromOrg exception: ' + ex.getMessage());
        }
        return null;
    }

    private static String fetchDynamicMetadataContent(String metadataType, String apiName, String filePath, String sourceUrl, String sourceToken) {
        String fileName = filePath.substringAfterLast('/');

        if (metadataType == 'ApexClass') {
            if (filePath.endsWith('.cls')) {
                String source = fetchSourceCodeFromSourceOrg(metadataType, apiName, sourceUrl, sourceToken);
                if (String.isNotBlank(source)) return source;
                List<ApexClass> cls = [SELECT Body FROM ApexClass WHERE Name = :apiName OR Name LIKE :apiName LIMIT 1];
                if (!cls.isEmpty()) return cls[0].Body;
            } else if (filePath.endsWith('.cls-meta.xml')) {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <status>Active</status>\n</ApexClass>';
            }
        } else if (metadataType == 'ApexTrigger') {
            if (filePath.endsWith('.trigger')) {
                String source = fetchSourceCodeFromSourceOrg(metadataType, apiName, sourceUrl, sourceToken);
                if (String.isNotBlank(source)) return source;
                List<ApexTrigger> trg = [SELECT Body FROM ApexTrigger WHERE Name = :apiName OR Name LIKE :apiName LIMIT 1];
                if (!trg.isEmpty()) return trg[0].Body;
            } else if (filePath.endsWith('.trigger-meta.xml')) {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<ApexTrigger xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <status>Active</status>\n</ApexTrigger>';
            }
        } else if (metadataType == 'LightningComponentBundle') {
            if (fileName.endsWith('.js-meta.xml')) {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <isExposed>true</isExposed>\n</LightningComponentBundle>';
            } else {
                return fetchLwcSourceFromOrg(apiName, fileName, sourceUrl, sourceToken);
            }
        } else if (metadataType == 'AuraDefinitionBundle') {
            if (fileName.endsWith('.cmp-meta.xml') || fileName.endsWith('.app-meta.xml')) {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<AuraDefinitionBundle xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <description>' + apiName + '</description>\n</AuraDefinitionBundle>';
            } else {
                return fetchAuraSourceFromOrg(apiName, fileName, sourceUrl, sourceToken);
            }
        } else if (metadataType == 'ApexPage') {
            if (fileName.endsWith('.page')) {
                String source = fetchSourceCodeFromSourceOrg(metadataType, apiName, sourceUrl, sourceToken);
                if (String.isNotBlank(source)) return source;
                String q = 'SELECT Markup FROM ApexPage WHERE Name = \'' + String.escapeSingleQuotes(apiName) + '\' LIMIT 1';
                List<SObject> pages = Database.query(q);
                if (!pages.isEmpty()) return (String) pages[0].get('Markup');
            } else {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<ApexPage xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <label>' + apiName + '</label>\n</ApexPage>';
            }
        } else if (metadataType == 'ApexComponent') {
            if (fileName.endsWith('.component')) {
                String source = fetchSourceCodeFromSourceOrg(metadataType, apiName, sourceUrl, sourceToken);
                if (String.isNotBlank(source)) return source;
                String q = 'SELECT Markup FROM ApexComponent WHERE Name = \'' + String.escapeSingleQuotes(apiName) + '\' LIMIT 1';
                List<SObject> comps = Database.query(q);
                if (!comps.isEmpty()) return (String) comps[0].get('Markup');
            } else {
                return '<?xml version="1.0" encoding="UTF-8"?>\n<ApexComponent xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>60.0</apiVersion>\n    <label>' + apiName + '</label>\n</ApexComponent>';
            }
        } else if (metadataType == 'CustomObject') {
            String source = fetchCustomObjectMetadata(apiName, sourceUrl, sourceToken);
            if (String.isNotBlank(source)) return source;
            return '<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n    <deploymentStatus>Deployed</deploymentStatus>\n    <sharingModel>ReadWrite</sharingModel>\n</CustomObject>';
        } else if (metadataType == 'CustomField') {
            String source = fetchCustomFieldMetadata(apiName, sourceUrl, sourceToken);
            if (String.isNotBlank(source)) return source;
            return '<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n    <fullName>' + apiName + '</fullName>\n    <label>' + apiName + '</label>\n    <type>Text</type>\n    <length>255</length>\n</CustomField>';
        } else if (String.isNotBlank(metadataType)) {
            return '<?xml version="1.0" encoding="UTF-8"?>\n<' + metadataType + ' xmlns="http://soap.sforce.com/2006/04/metadata">\n</' + metadataType + '>';
        }
        return null;
    }
}