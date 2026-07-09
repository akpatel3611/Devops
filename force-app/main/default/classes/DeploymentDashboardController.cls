public without sharing class DeploymentDashboardController {

    public class ActivityEvent implements Comparable {
        @AuraEnabled public String type {get;set;}
        @AuraEnabled public String title {get;set;}
        @AuraEnabled public String description {get;set;}
        @AuraEnabled public Datetime eventDate {get;set;}
        @AuraEnabled public String user {get;set;}
        @AuraEnabled public String badgeColor {get;set;}
        @AuraEnabled public String iconName {get;set;}
        
        public ActivityEvent(String type, String title, String description, Datetime eventDate, String user, String badgeColor, String iconName) {
            this.type = type;
            this.title = title;
            this.description = description;
            this.eventDate = eventDate;
            this.user = user;
            this.badgeColor = badgeColor;
            this.iconName = iconName;
        }
        
        public Integer compareTo(Object compareTo) {
            ActivityEvent other = (ActivityEvent)compareTo;
            if (this.eventDate == null && other.eventDate == null) return 0;
            if (this.eventDate == null) return 1;
            if (other.eventDate == null) return -1;
            if (this.eventDate == other.eventDate) return 0;
            return this.eventDate > other.eventDate ? -1 : 1;
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLivePipeline(Id projectId) {
        Map<String, Object> result = new Map<String, Object>();
        
        List<Pipeline__c> pipelines;
        if (projectId != null) {
            pipelines = [SELECT Id, Name, Current_Stage__c, Pipeline_Runtime_Status__c, Current_Branch__c 
                         FROM Pipeline__c 
                         WHERE Project__c = :projectId 
                         ORDER BY LastModifiedDate DESC LIMIT 1];
        } else {
            pipelines = [SELECT Id, Name, Current_Stage__c, Pipeline_Runtime_Status__c, Current_Branch__c 
                         FROM Pipeline__c 
                         ORDER BY LastModifiedDate DESC LIMIT 1];
        }
        
        if (pipelines.isEmpty()) {
            return result;
        }
        
        Pipeline__c pipe = pipelines[0];
        result.put('pipeline', pipe);
        
        List<Stage__c> stages = [SELECT Id, Name, Stage_Order__c, Stage_Type__c, Status__c 
                                 FROM Stage__c 
                                 WHERE Pipeline__c = :pipe.Id 
                                 ORDER BY Stage_Order__c ASC];
        result.put('stages', stages);
        
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Deployment_Request__c> getLiveDeployments(Id projectId) {
        if (projectId != null) {
            return [SELECT Id, Name, Deployment_Number__c, Deployment_Status__c, 
                           Source_Environment__r.Name__c, Target_Environment__r.Name__c, 
                           Triggered_By__c, Started_On__c, Completed_On__c
                    FROM Deployment_Request__c 
                    WHERE Pipeline__r.Project__c = :projectId
                    ORDER BY Started_On__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        } else {
            return [SELECT Id, Name, Deployment_Number__c, Deployment_Status__c, 
                           Source_Environment__r.Name__c, Target_Environment__r.Name__c, 
                           Triggered_By__c, Started_On__c, Completed_On__c
                    FROM Deployment_Request__c 
                    ORDER BY Started_On__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Promotion__c> getLivePromotions(Id projectId) {
        if (projectId != null) {
            return [SELECT Id, Name, Promotion_Name__c, Status__c, 
                           Source_Environment__r.Name__c, Target_Environment__r.Name__c, 
                           Triggered_By__c, Promotion_Date__c
                    FROM Promotion__c 
                    WHERE Pipeline__r.Project__c = :projectId
                    ORDER BY Promotion_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        } else {
            return [SELECT Id, Name, Promotion_Name__c, Status__c, 
                           Source_Environment__r.Name__c, Target_Environment__r.Name__c, 
                           Triggered_By__c, Promotion_Date__c
                    FROM Promotion__c 
                    ORDER BY Promotion_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Release__c> getLiveReleases(Id projectId) {
        if (projectId != null) {
            return [SELECT Id, Name, Release_Name__c, Version__c, Status__c, Release_Date__c, Release_Type__c
                    FROM Release__c 
                    WHERE Project__c = :projectId
                    ORDER BY Release_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        } else {
            return [SELECT Id, Name, Release_Name__c, Version__c, Status__c, Release_Date__c, Release_Type__c
                    FROM Release__c 
                    ORDER BY Release_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT 10];
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStats(Id projectId) {
        Map<String, Object> stats = new Map<String, Object>();
        
        // 1. Repository
        String repoName = 'N/A';
        Id repoId = null;
        if (projectId != null) {
            List<Project__c> projects = [SELECT Git_Repository__c, Git_Repository__r.Repository_Name__c FROM Project__c WHERE Id = :projectId LIMIT 1];
            if (!projects.isEmpty() && projects[0].Git_Repository__r != null) {
                repoName = projects[0].Git_Repository__r.Repository_Name__c;
                repoId = projects[0].Git_Repository__c;
            }
        }
        if (repoName == 'N/A') {
            List<Git_Repository__c> repos = [SELECT Id, Repository_Name__c FROM Git_Repository__c ORDER BY LastModifiedDate DESC LIMIT 1];
            if (!repos.isEmpty()) {
                repoName = repos[0].Repository_Name__c;
                repoId = repos[0].Id;
            }
        }
        stats.put('repository', repoName);
        stats.put('repositoryId', repoId);
        
        // 2. Current Release
        String releaseVersion = 'N/A';
        String releaseStatus = 'N/A';
        List<Release__c> releases;
        if (projectId != null) {
            releases = [SELECT Version__c, Status__c FROM Release__c WHERE Project__c = :projectId ORDER BY Release_Date__c DESC, CreatedDate DESC LIMIT 1];
        } else {
            releases = [SELECT Version__c, Status__c FROM Release__c ORDER BY Release_Date__c DESC, CreatedDate DESC LIMIT 1];
        }
        if (!releases.isEmpty()) {
            releaseVersion = releases[0].Version__c;
            releaseStatus = releases[0].Status__c;
        }
        stats.put('currentReleaseVersion', releaseVersion);
        stats.put('currentReleaseStatus', releaseStatus);
        
        // 3. Pipeline Status
        String pipelineStatus = 'All Green';
        String lastRunText = 'No runs';
        List<Pipeline__c> pipelines;
        if (projectId != null) {
            pipelines = [SELECT Pipeline_Runtime_Status__c, LastModifiedDate FROM Pipeline__c WHERE Project__c = :projectId ORDER BY LastModifiedDate DESC LIMIT 1];
        } else {
            pipelines = [SELECT Pipeline_Runtime_Status__c, LastModifiedDate FROM Pipeline__c ORDER BY LastModifiedDate DESC LIMIT 1];
        }
        if (!pipelines.isEmpty()) {
            if (pipelines[0].Pipeline_Runtime_Status__c != null) {
                pipelineStatus = pipelines[0].Pipeline_Runtime_Status__c;
            }
            lastRunText = 'Last run: ' + pipelines[0].LastModifiedDate.format();
        }
        stats.put('pipelineStatus', pipelineStatus);
        stats.put('lastRunText', lastRunText);
        
        // 4. Open PR Count
        Integer openPrCount;
        if (repoId != null) {
            openPrCount = [SELECT count() FROM Git_Snapshot__c WHERE Repository__c = :repoId AND Pull_Request_Number__c != null];
        } else {
            openPrCount = [SELECT count() FROM Git_Snapshot__c WHERE Pull_Request_Number__c != null];
        }
        stats.put('openPrCount', openPrCount);
        
        // 5. Open Deployment Count
        Integer openDeploymentCount;
        if (projectId != null) {
            openDeploymentCount = [SELECT count() FROM Deployment_Request__c WHERE Pipeline__r.Project__c = :projectId AND (Deployment_Status__c = 'Running' OR Deployment_Status__c = 'Not Started')];
        } else {
            openDeploymentCount = [SELECT count() FROM Deployment_Request__c WHERE Deployment_Status__c = 'Running' OR Deployment_Status__c = 'Not Started'];
        }
        stats.put('openDeploymentCount', openDeploymentCount);
        
        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<ActivityEvent> getActivityFeed(Id projectId) {
        List<ActivityEvent> events = new List<ActivityEvent>();
        
        Id repoId = null;
        if (projectId != null) {
            List<Project__c> projects = [SELECT Git_Repository__c FROM Project__c WHERE Id = :projectId LIMIT 1];
            if (!projects.isEmpty()) {
                repoId = projects[0].Git_Repository__c;
            }
        }

        // 1. Query PRs (snapshots)
        List<Git_Snapshot__c> prs;
        if (repoId != null) {
            prs = [SELECT Id, Name, Commit_Message__c, Branch_Name__c, Commit_Author__c, Commit_Date__c, Pull_Request_Number__c 
                   FROM Git_Snapshot__c 
                   WHERE Repository__c = :repoId AND Pull_Request_Number__c != null
                   ORDER BY Commit_Date__c DESC LIMIT 5];
        } else {
            prs = [SELECT Id, Name, Commit_Message__c, Branch_Name__c, Commit_Author__c, Commit_Date__c, Pull_Request_Number__c 
                   FROM Git_Snapshot__c 
                   WHERE Pull_Request_Number__c != null
                   ORDER BY Commit_Date__c DESC LIMIT 5];
        }
        for (Git_Snapshot__c pr : prs) {
            events.add(new ActivityEvent(
                'PR Created',
                'PR Created',
                'New pull request #' + pr.Pull_Request_Number__c + ' created by ' + pr.Commit_Author__c,
                pr.Commit_Date__c,
                pr.Commit_Author__c,
                'badge-purple',
                'utility:merge'
            ));
        }
        
        // 2. Query Deployments
        List<Deployment_Request__c> deps;
        if (projectId != null) {
            deps = [SELECT Id, Name, Deployment_Number__c, Deployment_Status__c, Target_Environment__r.Name__c, Triggered_By__c, Started_On__c 
                    FROM Deployment_Request__c 
                    WHERE Pipeline__r.Project__c = :projectId AND Started_On__c != null
                    ORDER BY Started_On__c DESC LIMIT 5];
        } else {
            deps = [SELECT Id, Name, Deployment_Number__c, Deployment_Status__c, Target_Environment__r.Name__c, Triggered_By__c, Started_On__c 
                    FROM Deployment_Request__c 
                    WHERE Started_On__c != null
                    ORDER BY Started_On__c DESC LIMIT 5];
        }
        for (Deployment_Request__c dep : deps) {
            String status = dep.Deployment_Status__c;
            String depNum = dep.Deployment_Number__c != null ? dep.Deployment_Number__c : dep.Name;
            if (status == 'Failed') {
                events.add(new ActivityEvent(
                    'Deployment Failed',
                    'Deployment Failed',
                    depNum + ' deployment failed in ' + dep.Target_Environment__r.Name__c + ' environment',
                    dep.Started_On__c,
                    dep.Triggered_By__c,
                    'badge-red',
                    'utility:error'
                ));
            } else {
                events.add(new ActivityEvent(
                    'Deployment Started',
                    'Deployment Started',
                    depNum + ' deployment started to ' + dep.Target_Environment__r.Name__c + ' environment',
                    dep.Started_On__c,
                    dep.Triggered_By__c,
                    'badge-blue',
                    'utility:play'
                ));
            }
        }
        
        // 3. Query Promotions
        List<Promotion__c> promos;
        if (projectId != null) {
            promos = [SELECT Id, Name, Promotion_Name__c, Status__c, Source_Environment__r.Name__c, Target_Environment__r.Name__c, Triggered_By__c, Promotion_Date__c 
                      FROM Promotion__c 
                      WHERE Pipeline__r.Project__c = :projectId AND Status__c = 'Approved' AND Promotion_Date__c != null
                      ORDER BY Promotion_Date__c DESC LIMIT 5];
        } else {
            promos = [SELECT Id, Name, Promotion_Name__c, Status__c, Source_Environment__r.Name__c, Target_Environment__r.Name__c, Triggered_By__c, Promotion_Date__c 
                      FROM Promotion__c 
                      WHERE Status__c = 'Approved' AND Promotion_Date__c != null
                      ORDER BY Promotion_Date__c DESC LIMIT 5];
        }
        for (Promotion__c promo : promos) {
            String promoNum = promo.Promotion_Name__c != null ? promo.Promotion_Name__c : promo.Name;
            events.add(new ActivityEvent(
                'Promotion Approved',
                'Promotion Approved',
                promoNum + ' approved ' + promo.Source_Environment__r.Name__c + ' ➔ ' + promo.Target_Environment__r.Name__c,
                promo.Promotion_Date__c,
                promo.Triggered_By__c,
                'badge-green',
                'utility:like'
            ));
        }
        
        // 4. Query Releases
        List<Release__c> rels;
        if (projectId != null) {
            rels = [SELECT Id, Name, Release_Name__c, Version__c, Status__c, Release_Date__c 
                    FROM Release__c 
                    WHERE Project__c = :projectId AND Status__c = 'Completed' AND Release_Date__c != null
                    ORDER BY Release_Date__c DESC LIMIT 5];
        } else {
            rels = [SELECT Id, Name, Release_Name__c, Version__c, Status__c, Release_Date__c 
                    FROM Release__c 
                    WHERE Status__c = 'Completed' AND Release_Date__c != null
                    ORDER BY Release_Date__c DESC LIMIT 5];
        }
        for (Release__c rel : rels) {
            String relNum = rel.Release_Name__c != null ? rel.Release_Name__c : rel.Name;
            events.add(new ActivityEvent(
                'Release Completed',
                'Release Completed',
                relNum + ' (' + rel.Version__c + ') released to Production',
                rel.Release_Date__c,
                'System',
                'badge-teal',
                'utility:package'
            ));
        }
        
        events.sort();
        
        List<ActivityEvent> finalEvents = new List<ActivityEvent>();
        for (Integer i = 0; i < Math.min(events.size(), 10); i++) {
            finalEvents.add(events[i]);
        }
        return finalEvents;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRecordsForObject(String objectApiName) {
        List<Map<String, String>> recordsList = new List<Map<String, String>>();
        if (String.isBlank(objectApiName)) {
            return recordsList;
        }
        try {
            String fields = 'Id, Name';
            if (objectApiName == 'Credentials__c') {
                fields += ', Deployment_Environment__r.Name, Instance_URL__c';
            } else if (objectApiName == 'Deployment_Environment__c') {
                fields += ', Environment_Type__c, Org_URL__c, Status__c';
            } else if (objectApiName == 'Pipeline__c') {
                fields += ', Project__r.Name, Current_Branch__c, Target_Environment__r.Name, Pipeline_Runtime_Status__c';
            } else if (objectApiName == 'User_Story__c') {
                fields += ', Title__c, Story_Status__c';
            } else if (objectApiName == 'Release__c') {
                fields += ', Version__c, Status__c';
            } else if (objectApiName == 'Promotion__c') {
                fields += ', Source_Environment__r.Name, Target_Environment__r.Name, Status__c';
            } else if (objectApiName == 'Deployment_Request__c') {
                fields += ', Source_Environment__r.Name, Target_Environment__r.Name, Deployment_Status__c';
            } else if (objectApiName == 'Git_Snapshot__c') {
                fields += ', Branch_Name__c, Commit_Author__c';
            } else if (objectApiName == 'Git_Repository__c') {
                fields += ', Repository_Name__c, Default_Branch__c';
            } else if (objectApiName == 'System_Property__c') {
                fields += ', Property_Key__c, Property_Value__c';
            } else if (objectApiName == 'Stage__c') {
                fields += ', Stage_Order__c, Status__c';
            }

            String queryStr = 'SELECT ' + fields + ' FROM ' + String.escapeSingleQuotes(objectApiName) + ' ORDER BY CreatedDate DESC LIMIT 50';
            List<SObject> sobjs = Database.query(queryStr);
            for (SObject sobj : sobjs) {
                Map<String, String> rec = new Map<String, String>();
                rec.put('Id', (String)sobj.get('Id'));
                
                Object nameVal = sobj.get('Name');
                rec.put('Name', nameVal != null ? String.valueOf(nameVal) : String.valueOf(sobj.get('Id')));
                
                if (objectApiName == 'Credentials__c') {
                    rec.put('col1', sobj.getSObject('Deployment_Environment__r') != null ? String.valueOf(sobj.getSObject('Deployment_Environment__r').get('Name')) : 'N/A');
                    rec.put('col2', String.valueOf(sobj.get('Instance_URL__c')));
                } else if (objectApiName == 'Deployment_Environment__c') {
                    rec.put('col1', String.valueOf(sobj.get('Environment_Type__c')));
                    rec.put('col2', String.valueOf(sobj.get('Org_URL__c')));
                    rec.put('col3', String.valueOf(sobj.get('Status__c')));
                } else if (objectApiName == 'Pipeline__c') {
                    rec.put('col1', sobj.getSObject('Project__r') != null ? String.valueOf(sobj.getSObject('Project__r').get('Name')) : 'N/A');
                    rec.put('col2', String.valueOf(sobj.get('Current_Branch__c')));
                    rec.put('col3', sobj.getSObject('Target_Environment__r') != null ? String.valueOf(sobj.getSObject('Target_Environment__r').get('Name')) : 'N/A');
                    rec.put('col4', String.valueOf(sobj.get('Pipeline_Runtime_Status__c')));
                } else if (objectApiName == 'User_Story__c') {
                    rec.put('col1', String.valueOf(sobj.get('Title__c')));
                    rec.put('col2', String.valueOf(sobj.get('Story_Status__c')));
                } else if (objectApiName == 'Release__c') {
                    rec.put('col1', String.valueOf(sobj.get('Version__c')));
                    rec.put('col2', String.valueOf(sobj.get('Status__c')));
                } else if (objectApiName == 'Promotion__c') {
                    rec.put('col1', sobj.getSObject('Source_Environment__r') != null ? String.valueOf(sobj.getSObject('Source_Environment__r').get('Name')) : 'N/A');
                    rec.put('col2', sobj.getSObject('Target_Environment__r') != null ? String.valueOf(sobj.getSObject('Target_Environment__r').get('Name')) : 'N/A');
                    rec.put('col3', String.valueOf(sobj.get('Status__c')));
                } else if (objectApiName == 'Deployment_Request__c') {
                    rec.put('col1', sobj.getSObject('Source_Environment__r') != null ? String.valueOf(sobj.getSObject('Source_Environment__r').get('Name')) : 'N/A');
                    rec.put('col2', sobj.getSObject('Target_Environment__r') != null ? String.valueOf(sobj.getSObject('Target_Environment__r').get('Name')) : 'N/A');
                    rec.put('col3', String.valueOf(sobj.get('Deployment_Status__c')));
                } else if (objectApiName == 'Git_Snapshot__c') {
                    rec.put('col1', String.valueOf(sobj.get('Branch_Name__c')));
                    rec.put('col2', String.valueOf(sobj.get('Commit_Author__c')));
                } else if (objectApiName == 'Git_Repository__c') {
                    rec.put('col1', String.valueOf(sobj.get('Repository_Name__c')));
                    rec.put('col2', String.valueOf(sobj.get('Default_Branch__c')));
                } else if (objectApiName == 'System_Property__c') {
                    rec.put('col1', String.valueOf(sobj.get('Property_Key__c')));
                    rec.put('col2', String.valueOf(sobj.get('Property_Value__c')));
                } else if (objectApiName == 'Stage__c') {
                    rec.put('col1', String.valueOf(sobj.get('Stage_Order__c')));
                    rec.put('col2', String.valueOf(sobj.get('Status__c')));
                }
                recordsList.add(rec);
            }
        } catch (Exception e) {
            System.debug('Error querying dynamic object: ' + e.getMessage());
            throw new AuraHandledException('Error querying ' + objectApiName + ': ' + e.getMessage());
        }
        return recordsList;
    }
}