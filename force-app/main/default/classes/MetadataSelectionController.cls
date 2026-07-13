public with sharing class MetadataSelectionController {

    public class DropdownOption {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public DropdownOption(
            String label,
            String value
        ){
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DropdownOption> getProjects(){

        List<DropdownOption> results =
            new List<DropdownOption>();

        for(Project__c project : [

            SELECT Id,
                   Name

            FROM Project__c

            ORDER BY Name

        ]){

            results.add(

                new DropdownOption(

                    project.Name,

                    project.Id
                )
            );
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<DropdownOption> getUserStories(){

        List<DropdownOption> results =
            new List<DropdownOption>();

        for(User_Story__c story : [

            SELECT Id,
                   Name

            FROM User_Story__c

            ORDER BY Name

        ]){

            results.add(

                new DropdownOption(

                    story.Name,

                    story.Id
                )
            );
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<DropdownOption> getReleases(){

        List<DropdownOption> results =
            new List<DropdownOption>();

        for(Release__c release : [
            SELECT Id,
                   Name,
                   Release_Name__c
            FROM Release__c
            ORDER BY Release_Name__c
        ]){
            String label = String.isNotBlank(release.Release_Name__c) ? release.Release_Name__c : release.Name;
            results.add(
                new DropdownOption(
                    label,
                    release.Id
                )
            );
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<DropdownOption> getUserStoriesForRelease(Id releaseId){
        List<DropdownOption> results = new List<DropdownOption>();
        if(releaseId == null) {
            return results;
        }
        
        List<Release__c> releases = [SELECT Project__c FROM Release__c WHERE Id = :releaseId LIMIT 1];
        if (releases.isEmpty() || releases[0].Project__c == null) {
            return results;
        }
        Id projectId = releases[0].Project__c;
        
        for(User_Story__c story : [
            SELECT Id, Name, Story_Number__c, Title__c
            FROM User_Story__c
            WHERE Project__c = :projectId
            ORDER BY Story_Number__c
        ]){
            String label = (String.isNotBlank(story.Story_Number__c) ? story.Story_Number__c + ': ' : '') + 
                           (String.isNotBlank(story.Title__c) ? story.Title__c : story.Name);
            results.add(new DropdownOption(label, story.Id));
        }
        return results;
    }

    public class BranchVerifyResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> matchingBranches;
        @AuraEnabled public String autoSelectedBranch;
    }

    @AuraEnabled
    public static BranchVerifyResult scanAndVerifyBranch(Id userStoryId, List<String> filePaths) {
        BranchVerifyResult result = new BranchVerifyResult();
        result.success = false;
        result.matchingBranches = new List<String>();

        try {
            if (userStoryId == null) {
                result.message = 'User Story ID is required.';
                return result;
            }
            if (filePaths == null || filePaths.isEmpty()) {
                result.message = 'No selected files found for verification.';
                return result;
            }

            User_Story__c story = [
                SELECT Id, Source_Environment__c, Feature_Branch__c,
                       Project__r.Git_Repository__r.Repository_Name__c,
                       Project__r.Git_Repository__r.Repository_Owner__c,
                       Project__r.Git_Repository__r.Default_Branch__c,
                       Project__r.Git_Repository__r.GitHub_URL__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];

            Git_Repository__c repo = story.Project__r.Git_Repository__r;
            if (repo == null) {
                result.message = 'Git Repository is not configured for this Project.';
                return result;
            }

            String owner = repo.Repository_Owner__c;
            String repoName = repo.Repository_Name__c;
            String defaultBranch = String.isNotBlank(repo.Default_Branch__c) ? repo.Default_Branch__c : 'main';

            List<Credentials__c> creds = [
                SELECT Access_Token__c, Instance_URL__c
                FROM Credentials__c
                WHERE Deployment_Environment__c = :story.Source_Environment__c
                LIMIT 1
            ];
            if (creds.isEmpty()) {
                creds = [
                    SELECT Access_Token__c, Instance_URL__c
                    FROM Credentials__c
                    WHERE Instance_URL__c LIKE '%github.com%'
                    LIMIT 1
                ];
            }
            if (creds.isEmpty()) {
                creds = [
                    SELECT Access_Token__c, Instance_URL__c
                    FROM Credentials__c
                    LIMIT 1
                ];
            }
            if (creds.isEmpty() || String.isBlank(creds[0].Access_Token__c)) {
                result.message = 'Authentication Failure: No active GitHub credentials found.';
                return result;
            }

            String token = creds[0].Access_Token__c;
            String baseUrl = String.isNotBlank(creds[0].Instance_URL__c) && creds[0].Instance_URL__c.contains('github.com') ? creds[0].Instance_URL__c : 'https://api.github.com';

            String endpoint = baseUrl + '/repos/' + owner + '/' + repoName + '/branches';
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(60000);
            req.setHeader('Accept', 'application/vnd.github+json');
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('User-Agent', 'Salesforce-Release-Management');

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                result.message = 'GitHub branches fetch failed (Status ' + res.getStatusCode() + '): ' + res.getBody();
                return result;
            }

            List<Object> branchList = (List<Object>) JSON.deserializeUntyped(res.getBody());
            List<String> activeBranches = new List<String>();
            for (Object obj : branchList) {
                Map<String, Object> branchInfo = (Map<String, Object>) obj;
                String name = (String) branchInfo.get('name');
                if (name != defaultBranch) {
                    activeBranches.add(name);
                }
            }

            for (String branch : activeBranches) {
                Boolean matchesAll = false;
                
                // If the branch name matches the User Story's feature branch, it's an automatic match!
                if (String.isNotBlank(story.Feature_Branch__c) && branch.toLowerCase() == story.Feature_Branch__c.toLowerCase()) {
                    matchesAll = true;
                } else {
                    String compEndpoint = baseUrl + '/repos/' + owner + '/' + repoName + '/compare/' + defaultBranch + '...' + branch;
                    HttpRequest compReq = new HttpRequest();
                    compReq.setEndpoint(compEndpoint);
                    compReq.setMethod('GET');
                    compReq.setTimeout(60000);
                    compReq.setHeader('Accept', 'application/vnd.github+json');
                    compReq.setHeader('Authorization', 'Bearer ' + token);
                    compReq.setHeader('User-Agent', 'Salesforce-Release-Management');

                    HttpResponse compRes = new Http().send(compReq);
                    if (compRes.getStatusCode() == 200) {
                        Map<String, Object> compData = (Map<String, Object>) JSON.deserializeUntyped(compRes.getBody());
                        List<Object> files = (List<Object>) compData.get('files');
                        Set<String> changedPaths = new Set<String>();
                        if (files != null) {
                            for (Object fileObj : files) {
                                Map<String, Object> fileInfo = (Map<String, Object>) fileObj;
                                String filename = (String) fileInfo.get('filename');
                                if (String.isNotBlank(filename)) {
                                    changedPaths.add(filename.toLowerCase().trim());
                                }
                            }
                        }

                        // Lenient check: match if at least one selected file is modified in the branch compared to main
                        for (String path : filePaths) {
                            String strippedPath = stripExtension(path);
                            for (String changed : changedPaths) {
                                if (changed.contains(strippedPath)) {
                                    matchesAll = true;
                                    break;
                                }
                            }
                            if (matchesAll) {
                                break;
                            }
                        }
                    }
                }

                if (matchesAll) {
                    result.matchingBranches.add(branch);
                }
            }

            if (result.matchingBranches.isEmpty()) {
                result.message = 'No developer branch found on GitHub containing modifications to all selected metadata files.';
            } else {
                result.success = true;
                if (result.matchingBranches.size() == 1) {
                    result.autoSelectedBranch = result.matchingBranches[0];
                    result.message = 'Developer branch successfully auto-identified: ' + result.autoSelectedBranch;
                } else {
                    result.message = 'Multiple matching developer branches found. Please select one.';
                }
            }

        } catch (Exception ex) {
            result.message = 'Execution error: ' + ex.getMessage();
        }

        return result;
    }

    private static String stripExtension(String path) {
        if (String.isBlank(path)) {
            return '';
        }
        String p = path.toLowerCase().trim();
        if (p.endsWith('.cls')) {
            p = p.substring(0, p.length() - 4);
        } else if (p.endsWith('.trigger')) {
            p = p.substring(0, p.length() - 8);
        } else if (p.endsWith('.page')) {
            p = p.substring(0, p.length() - 5);
        } else if (p.endsWith('.component')) {
            p = p.substring(0, p.length() - 10);
        } else if (p.endsWith('.js')) {
            p = p.substring(0, p.length() - 3);
        } else if (p.endsWith('.cmp')) {
            p = p.substring(0, p.length() - 4);
        } else if (p.endsWith('.object-meta.xml')) {
            p = p.substring(0, p.length() - 16);
        } else if (p.endsWith('.field-meta.xml')) {
            p = p.substring(0, p.length() - 15);
        }
        return p;
    }

    @AuraEnabled
    public static PRStatusResult checkPRStatusAndDeploy(Id userStoryId, String prNumber, String prUrl, String branchName) {
        PRStatusResult res = new PRStatusResult();
        res.isMerged = false;
        res.status = 'Pending';
        res.logs = new List<Deployment_Log__c>();
        
        try {
            List<Deployment_Request__c> reqs = [
                SELECT Id, Status__c
                FROM Deployment_Request__c
                WHERE User_Story__c = :userStoryId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (reqs.isEmpty()) {
                res.message = 'No active Deployment Request found.';
                return res;
            }
            Deployment_Request__c dreq = reqs[0];
            res.requestId = dreq.Id;
            res.status = dreq.Status__c;
            
            res.logs = [
                SELECT Id, Log_Type__c, Message__c, Timestamp__c
                FROM Deployment_Log__c
                WHERE Deployment_Request__c = :dreq.Id
                ORDER BY Timestamp__c ASC
                LIMIT 100
            ];
            
            if (dreq.Status__c == 'Completed' || dreq.Status__c == 'Failed') {
                res.isMerged = true;
                return res;
            }
            
            // Check credentials to retrieve active token
            Credentials__c cred = null;
            List<Credentials__c> activeCreds = [
                SELECT Access_Token__c, Instance_URL__c
                FROM Credentials__c
                WHERE Instance_URL__c LIKE '%github.com%'
                LIMIT 1
            ];
            if (activeCreds.isEmpty()) {
                activeCreds = [
                    SELECT Access_Token__c, Instance_URL__c
                    FROM Credentials__c
                    LIMIT 1
                ];
            }
            if (!activeCreds.isEmpty()) {
                cred = activeCreds[0];
            } else {
                res.message = 'No active Credentials found to communicate with GitHub.';
                return res;
            }
            
            String token = cred.Access_Token__c;
            
            User_Story__c story = [
                SELECT Id, Project__c, Project__r.Git_Repository__c,
                       Project__r.Git_Repository__r.Repository_Name__c,
                       Project__r.Git_Repository__r.Repository_Owner__c
                FROM User_Story__c
                WHERE Id = :userStoryId
                LIMIT 1
            ];
            
            String owner = story.Project__r.Git_Repository__r.Repository_Owner__c;
            String repo = story.Project__r.Git_Repository__r.Repository_Name__c;
            
            String endpoint = 'https://api.github.com/repos/' + owner + '/' + repo + '/pulls/' + prNumber;
            
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(60000);
            req.setHeader('Accept', 'application/vnd.github+json');
            req.setHeader('User-Agent', 'Salesforce-Release-Management');
            req.setHeader('Authorization', 'Bearer ' + token);
            
            HttpResponse response = http.send(req);
            if (response.getStatusCode() == 200) {
                Map<String, Object> prMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                Boolean merged = (Boolean) prMap.get('merged');
                String state = (String) prMap.get('state');
                
                if (merged || state == 'closed') {
                    res.isMerged = true;
                    if (merged) {
                        // Merge verified on GitHub. Initialize pipeline deployment!
                        res.status = 'Pending';

                        GitHubRecordService.GitHubRecordData requestData = new GitHubRecordService.GitHubRecordData();
                        requestData.sourceBranch = branchName;
                        requestData.pullRequestNumber = Integer.valueOf(prNumber);
                        requestData.pullRequestUrl = prUrl;
                        if (prMap.containsKey('head') && prMap.get('head') != null) {
                            requestData.sourceSha = (String) ((Map<String, Object>) prMap.get('head')).get('sha');
                        }
                        
                        PipelineRuntimeService.startPipeline(dreq.Id, requestData);
                        res.message = 'PR Merged! Deployment pipeline started successfully.';
                    } else {
                        res.message = 'PR was closed without merging.';
                        dreq.Status__c = 'Failed';
                        update dreq;
                        
                        User_Story__c us = new User_Story__c(Id = userStoryId);
                        us.Build_Status__c = 'Not Started';
                        us.PR_Status__c = 'Failed';
                        update us;
                    }
                } else {
                    res.message = 'PR is still open. Waiting for merge...';
                }
            } else {
                res.message = 'Failed to fetch PR status: ' + response.getStatus();
            }
        } catch(Exception ex) {
            res.message = 'Error: ' + ex.getMessage();
        }
        
        return res;
    }
    
    public class PRStatusResult {
        @AuraEnabled public Boolean isMerged {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public Id requestId {get;set;}
        @AuraEnabled public List<Deployment_Log__c> logs {get;set;}
    }
}