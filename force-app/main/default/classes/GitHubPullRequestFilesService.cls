/**
 * Service class responsible for interacting with GitHub REST API to fetch
 * changed files for Pull Requests.
 */
public with sharing class GitHubPullRequestFilesService {

    /**
     * Custom exception for GitHub Pull Request Files integration errors.
     */
    public class GitHubPullRequestFilesException extends Exception {}

    /**
     * DTO for storing execution statistics of the GitHub files fetch callout.
     */
    public class GitHubFilesFetchResult {
        public Integer totalFiles;
        public Integer totalPages;
        public Integer apiCalls;
        public Long executionTime;
        public Integer rateLimitRemaining;
        
        public GitHubFilesFetchResult() {
            this.totalFiles = 0;
            this.totalPages = 0;
            this.apiCalls = 0;
            this.executionTime = 0;
            this.rateLimitRemaining = 0;
        }
    }

    /**
     * Public entrypoint router that delegates file fetching based on event type.
     *
     * @param requestData GitHub Record Data transfer object.
     * @return List of mapped ChangedFile objects for MetadataScannerService.
     */
    public static List<MetadataScannerService.ChangedFile> fetchChangedFiles(
        GitHubRecordService.GitHubRecordData requestData
    ) {
        if (requestData == null) {
            return new List<MetadataScannerService.ChangedFile>();
        }
        
        String eventName = requestData.eventName != null ? requestData.eventName.toLowerCase().trim() : '';
        
        if (eventName == 'pull_request') {
            return fetchPullRequestFiles(requestData);
        } else if (eventName == 'push') {
            return fetchCommitFiles(requestData);
        } else if (eventName == 'compare') {
            return fetchCompareFiles(requestData);
        } else {
            return new List<MetadataScannerService.ChangedFile>();
        }
    }

    /**
     * Fetch changed files for a specific Pull Request.
     *
     * @param requestData GitHub Record Data transfer object containing repository and PR details.
     * @return List of mapped ChangedFile objects for MetadataScannerService.
     */
    public static List<MetadataScannerService.ChangedFile> fetchPullRequestFiles(
        GitHubRecordService.GitHubRecordData requestData
    ) {
        List<MetadataScannerService.ChangedFile> changedFiles = new List<MetadataScannerService.ChangedFile>();
        GitHubFilesFetchResult stats = new GitHubFilesFetchResult();
        Long startTime = System.currentTimeMillis();
        
        try {
            validateInput(requestData);
            
            MetadataAuthenticationService.OAuthTokenResponse auth = getCredential(requestData);
            String token = auth != null ? auth.accessToken : '';
            String baseUrl = auth != null ? auth.instanceUrl : '';
            
            String endpoint = buildEndpoint(requestData, baseUrl);
            Integer pageCount = 0;
            Integer maxPages = 100;
            
            List<GitHubIntegrationService.GitHubChangedFile> allRawFiles = new List<GitHubIntegrationService.GitHubChangedFile>();
            
            while (String.isNotBlank(endpoint) && pageCount < maxPages) {
                pageCount++;
                stats.apiCalls++;
                stats.totalPages++;
                
                HttpRequest req = createRequest(endpoint, token);
                HttpResponse res = executeRequest(req);
                
                // Track remaining rate limits dynamically
                String rateHeader = res.getHeader('X-RateLimit-Remaining');
                if (String.isNotBlank(rateHeader)) {
                    try {
                        stats.rateLimitRemaining = Integer.valueOf(rateHeader.trim());
                    } catch (Exception ex) {}
                }
                
                List<GitHubIntegrationService.GitHubChangedFile> wrappers = parseResponse(res);
                if (wrappers != null) {
                    allRawFiles.addAll(wrappers);
                }
                
                if (hasNextPage(res)) {
                    endpoint = extractNextPage(res);
                } else {
                    endpoint = null;
                }
            }
            
            // Validate response files items
            List<GitHubIntegrationService.GitHubChangedFile> validatedRawFiles = validateResponseFiles(allRawFiles);
            stats.totalFiles = validatedRawFiles.size();
            
            // Map wrapper to output ChangedFiles
            changedFiles.addAll(convertToScannerFiles(validatedRawFiles));
            
        } catch (GitHubPullRequestFilesException validationEx) {
            System.debug(LoggingLevel.ERROR, 'Validation Error in GitHubPullRequestFilesService: ' + validationEx.getMessage());
            throw validationEx;
        } catch (CalloutException calloutEx) {
            System.debug(LoggingLevel.ERROR, 'Callout Error in GitHubPullRequestFilesService: ' + calloutEx.getMessage());
            return new List<MetadataScannerService.ChangedFile>();
        } catch (JSONException jsonEx) {
            System.debug(LoggingLevel.ERROR, 'JSON Parsing Error in GitHubPullRequestFilesService: ' + jsonEx.getMessage());
            return new List<MetadataScannerService.ChangedFile>();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'General Error in GitHubPullRequestFilesService: ' + ex.getMessage());
            return new List<MetadataScannerService.ChangedFile>();
        } finally {
            stats.executionTime = System.currentTimeMillis() - startTime;
            System.debug(LoggingLevel.INFO, 'GitHub Pull Request Files Fetch Stats: ' + JSON.serialize(stats));
        }
        
        return changedFiles;
    }

    /**
     * Future Placeholder: Fetch changed files for a specific commit.
     */
    public static List<MetadataScannerService.ChangedFile> fetchCommitFiles(
        GitHubRecordService.GitHubRecordData requestData
    ) {
        throw new GitHubPullRequestFilesException('Method not implemented.');
    }

    /**
     * Future Placeholder: Fetch changed files between two branches/ref comparisons.
     */
    public static List<MetadataScannerService.ChangedFile> fetchCompareFiles(
        GitHubRecordService.GitHubRecordData requestData
    ) {
        throw new GitHubPullRequestFilesException('Method not implemented.');
    }

    /**
     * Future Placeholder: Fetch raw file content.
     */
    public static String fetchFileContent(
        GitHubRecordService.GitHubRecordData requestData,
        String filePath
    ) {
        throw new GitHubPullRequestFilesException('Method not implemented.');
    }

    /**
     * Future Placeholder: Fetch patch of a file.
     */
    public static String fetchFilePatch(
        GitHubRecordService.GitHubRecordData requestData,
        String filePath
    ) {
        throw new GitHubPullRequestFilesException('Method not implemented.');
    }

    /**
     * Validates input request data.
     */
    @TestVisible
    private static void validateInput(GitHubRecordService.GitHubRecordData requestData) {
        if (requestData == null) {
            throw new GitHubPullRequestFilesException('Request data is required.');
        }
        if (String.isBlank(requestData.repositoryFullName)) {
            throw new GitHubPullRequestFilesException('Repository Full Name is required.');
        }
        if (requestData.pullRequestNumber == null) {
            throw new GitHubPullRequestFilesException('Pull Request Number is required.');
        }
        if (!requestData.repositoryFullName.contains('/')) {
            throw new GitHubPullRequestFilesException('Invalid Repository Full Name format. Expected owner/repository.');
        }
    }

    /**
     * Dynamic URL endpoint builder.
     */
    @TestVisible
    private static String buildEndpoint(GitHubRecordService.GitHubRecordData requestData, String baseUrl) {
        String resolvedUrl = String.isNotBlank(baseUrl) ? baseUrl : 'https://api.github.com';
        if (resolvedUrl.endsWith('/')) {
            resolvedUrl = resolvedUrl.substring(0, resolvedUrl.length() - 1);
        }
        
        List<String> parts = requestData.repositoryFullName.split('/');
        String owner = parts[0].trim();
        String repo = parts[1].trim();
        Integer prNumber = requestData.pullRequestNumber;
        
        return resolvedUrl + '/repos/' + owner + '/' + repo + '/pulls/' + prNumber + '/files?per_page=100';
    }

    /**
     * Create HTTP Request with standard headers and timeout configuration.
     */
    @TestVisible
    private static HttpRequest createRequest(String endpoint, String token) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(120000); // 120 seconds timeout
        
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('User-Agent', 'Salesforce-Release-Management');
        
        if (String.isNotBlank(token)) {
            req.setHeader('Authorization', 'Bearer ' + token);
        }
        
        return req;
    }

    /**
     * Performs actual HTTP callout with a 2x retry mechanism on rate limits (429) or temporary service issues (503).
     */
    @TestVisible
    private static HttpResponse executeRequest(HttpRequest req) {
        Http http = new Http();
        HttpResponse res = null;
        Integer retries = 2;
        Integer attempt = 0;
        
        while (attempt <= retries) {
            attempt++;
            res = http.send(req);
            
            Integer statusCode = res.getStatusCode();
            if ((statusCode == 429 || statusCode == 503) && attempt <= retries) {
                continue;
            }
            break;
        }
        return res;
    }

    /**
     * Deserializes JSON response safely into strongly typed wrappers.
     */
    @TestVisible
    private static List<GitHubIntegrationService.GitHubChangedFile> parseResponse(HttpResponse res) {
        if (res == null) {
            throw new GitHubPullRequestFilesException('HTTP response is null.');
        }
        
        Integer statusCode = res.getStatusCode();
        if (statusCode == 200) {
            try {
                return (List<GitHubIntegrationService.GitHubChangedFile>) JSON.deserialize(
                    res.getBody(),
                    List<GitHubIntegrationService.GitHubChangedFile>.class
                );
            } catch (Exception ex) {
                throw new GitHubPullRequestFilesException('Failed to deserialize GitHub response: ' + ex.getMessage());
            }
        }
        
        String errorMsg;
        switch on statusCode {
            when 401 {
                errorMsg = 'GitHub API authentication failed (401 Unauthorized). Please check your token credentials.';
            }
            when 403 {
                errorMsg = 'GitHub API rate limit exceeded or access forbidden (403 Forbidden). body: ' + res.getBody();
            }
            when 404 {
                errorMsg = 'Requested resource not found on GitHub (404 Not Found). Please verify repository and PR details.';
            }
            when 422 {
                errorMsg = 'GitHub API validation failed (422 Unprocessable Entity). Please check your payload parameters.';
            }
            when 429 {
                errorMsg = 'Too many requests to GitHub API (429 Too Many Requests). Rate limiting active.';
            }
            when 500 {
                errorMsg = 'GitHub Internal Server Error (500). Please retry later.';
            }
            when 503 {
                errorMsg = 'GitHub Service Unavailable (503). Service temporarily offline.';
            }
            when else {
                errorMsg = 'GitHub API request failed with status code ' + statusCode + ': ' + res.getBody();
            }
        }
        throw new GitHubPullRequestFilesException(errorMsg);
    }

    /**
     * Validates changed file items to ensure scanner compatibility.
     */
    @TestVisible
    private static List<GitHubIntegrationService.GitHubChangedFile> validateResponseFiles(
        List<GitHubIntegrationService.GitHubChangedFile> rawFiles
    ) {
        List<GitHubIntegrationService.GitHubChangedFile> validatedFiles = new List<GitHubIntegrationService.GitHubChangedFile>();
        if (rawFiles == null) {
            return validatedFiles;
        }
        
        Set<String> seenFilenames = new Set<String>();
        for (GitHubIntegrationService.GitHubChangedFile file : rawFiles) {
            if (file == null) {
                continue;
            }
            
            // 1. Filename blank check
            if (String.isBlank(file.filename)) {
                System.debug(LoggingLevel.WARN, 'Validation failed: filename is blank.');
                continue;
            }
            // 2. Status blank check
            if (String.isBlank(file.status)) {
                System.debug(LoggingLevel.WARN, 'Validation failed for file ' + file.filename + ': status is blank.');
                continue;
            }
            // 3. Duplicate check
            if (seenFilenames.contains(file.filename)) {
                System.debug(LoggingLevel.WARN, 'Validation failed: duplicate filename found: ' + file.filename);
                continue;
            }
            // 4. Renamed file previous_filename check
            if (file.status.toLowerCase() == 'renamed' && String.isBlank(file.previous_filename)) {
                System.debug(LoggingLevel.WARN, 'Validation failed for renamed file ' + file.filename + ': previous_filename is blank.');
                continue;
            }
            
            seenFilenames.add(file.filename);
            validatedFiles.add(file);
        }
        return validatedFiles;
    }

    /**
     * DTO conversion helper that maps list of GitHub wrapper changes to MetadataScannerService ChangedFiles.
     */
    @TestVisible
    private static List<MetadataScannerService.ChangedFile> convertToScannerFiles(
        List<GitHubIntegrationService.GitHubChangedFile> githubFiles
    ) {
        List<MetadataScannerService.ChangedFile> scannerFiles = new List<MetadataScannerService.ChangedFile>();
        if (githubFiles == null) {
            return scannerFiles;
        }
        for (GitHubIntegrationService.GitHubChangedFile githubFile : githubFiles) {
            scannerFiles.add(mapChangedFile(githubFile));
        }
        return scannerFiles;
    }

    /**
     * Maps the parsed GitHub wrapper to MetadataScannerService.ChangedFile DTO.
     */
    @TestVisible
    private static MetadataScannerService.ChangedFile mapChangedFile(GitHubIntegrationService.GitHubChangedFile wrapper) {
        MetadataScannerService.ChangedFile file = new MetadataScannerService.ChangedFile();
        file.filename = wrapper.filename;
        file.status = wrapper.status;
        file.previousFilename = wrapper.previous_filename;
        file.sha = wrapper.sha;
        file.blobUrl = wrapper.blob_url;
        file.rawUrl = wrapper.raw_url;
        file.contentsUrl = wrapper.contents_url;
        file.sourceSystem = 'GitHub';
        
        // additions, deletions, changes can be mapped here in future if added to DTO
        
        return file;
    }

    /**
     * Checks if pagination Link header indicates next page is available.
     */
    @TestVisible
    private static Boolean hasNextPage(HttpResponse response) {
        if (response == null) {
            return false;
        }
        String linkHeader = response.getHeader('Link');
        return String.isNotBlank(linkHeader) && linkHeader.contains('rel="next"');
    }

    /**
     * Extracts next page URL from HTTP Link Header.
     */
    @TestVisible
    private static String extractNextPage(HttpResponse response) {
        if (response == null) {
            return null;
        }
        String linkHeader = response.getHeader('Link');
        if (String.isBlank(linkHeader)) {
            return null;
        }
        List<String> parts = linkHeader.split(',');
        for (String part : parts) {
            if (part.contains('rel="next"')) {
                Integer startIdx = part.indexOf('<');
                Integer endIdx = part.indexOf('>');
                if (startIdx != -1 && endIdx != -1 && startIdx < endIdx) {
                    return part.substring(startIdx + 1, endIdx);
                }
            }
        }
        return null;
    }

    /**
     * Resolves Credentials record utilizing existing environment controller architecture.
     */
    @TestVisible
    private static MetadataAuthenticationService.OAuthTokenResponse getCredential(GitHubRecordService.GitHubRecordData requestData) {
        MetadataAuthenticationService.OAuthTokenResponse auth = null;
        try {
            List<String> envObjects = new List<String>{ 'Deployment_Environment__c' };
            String envObjectApi = firstExistingObject(envObjects);
            
            if (String.isNotBlank(envObjectApi)) {
                String statusField = fieldExists(envObjectApi, 'Status__c') ? 'Status__c' : '';
                String query = 'SELECT Id FROM ' + envObjectApi;
                if (String.isNotBlank(statusField)) {
                    query += ' WHERE ' + statusField + ' = \'Active\'';
                }
                query += ' LIMIT 1';
                
                List<SObject> envs = Database.query(query);
                if (!envs.isEmpty()) {
                    Id envId = envs[0].Id;
                    
                    DeploymentCredentialController.CredentialWrapper wrapper = 
                        DeploymentCredentialController.getCredentialByEnvironment(envId);
                    
                    if (wrapper != null && String.isNotBlank(wrapper.credentialId)) {
                        Id credId = (Id) wrapper.credentialId;
                        auth = MetadataAuthenticationService.generateAccessToken(credId);
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Error resolving credential via controller: ' + ex.getMessage());
        }
        
        // Fallback query if no active environment config resolved
        if (auth == null) {
            try {
                List<String> credObjects = new List<String>{ 'Credentials__c' };
                String credObjectApi = firstExistingObject(credObjects);
                if (String.isNotBlank(credObjectApi)) {
                    List<SObject> fallbackCreds = Database.query('SELECT Id FROM ' + credObjectApi + ' LIMIT 1');
                    if (!fallbackCreds.isEmpty()) {
                        auth = MetadataAuthenticationService.generateAccessToken(fallbackCreds[0].Id);
                    }
                }
            } catch (Exception ex) {
                System.debug('Fallback credential resolution failed: ' + ex.getMessage());
            }
        }
        return auth;
    }

    /**
     * Resolves first existing object dynamically.
     */
    private static String firstExistingObject(List<String> candidateObjects) {
        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        for (String objectApi : candidateObjects) {
            if (describeMap.containsKey(objectApi)) {
                return objectApi;
            }
        }
        return null;
    }

    /**
     * Resolves first existing field dynamically.
     */
    private static String firstExistingField(String objectApi, List<String> candidateFields) {
        if (String.isBlank(objectApi) || candidateFields == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApi).getDescribe().fields.getMap();
        for (String fieldApi : candidateFields) {
            if (String.isNotBlank(fieldApi) && fieldMap.containsKey(fieldApi)) {
                return fieldApi;
            }
        }
        return null;
    }

    /**
     * Dynamic field check.
     */
    private static Boolean fieldExists(String objectApi, String fieldApi) {
        return String.isNotBlank(firstExistingField(objectApi, new List<String>{ fieldApi }));
    }
}