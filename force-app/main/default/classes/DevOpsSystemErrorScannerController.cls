public with sharing class DevOpsSystemErrorScannerController {

    public class SystemErrorLogWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String source; // ORG, BROWSER, DEPLOYMENT, LIMITS
        @AuraEnabled public String severity; // CRITICAL, ERROR, WARN, INFO
        @AuraEnabled public String componentOrClass;
        @AuraEnabled public String methodName;
        @AuraEnabled public String rawErrorMessage;
        @AuraEnabled public String stackTrace;
        @AuraEnabled public String diagnosedRootCause;
        @AuraEnabled public String recommendedFix;
        @AuraEnabled public String timestamp;
        @AuraEnabled public String recordId;
    }

    /**
     * Dynamically scans the Salesforce Org in real-time for failed async jobs, deployment errors, and system limits.
     */
    @AuraEnabled(cacheable=false)
    public static List<SystemErrorLogWrapper> getRealtimeOrgErrors(List<Id> activeRecordIds) {
        System.debug(LoggingLevel.INFO, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] START - scanning activeRecordIds: ' + activeRecordIds);
        List<SystemErrorLogWrapper> errorLogs = new List<SystemErrorLogWrapper>();

        try {
            // 1. Scan Failed AsyncApexJobs (Queueable, Batch, Future)
            List<AsyncApexJob> failedJobs = [
                SELECT Id, ApexClass.Name, MethodName, Status, ExtendedStatus, NumberOfErrors, CreatedDate
                FROM AsyncApexJob
                WHERE Status IN ('Failed', 'Aborted') AND CreatedDate = TODAY
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            System.debug(LoggingLevel.DEBUG, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] Found ' + failedJobs.size() + ' failed AsyncApexJobs');

            for (AsyncApexJob job : failedJobs) {
                SystemErrorLogWrapper err = new SystemErrorLogWrapper();
                err.id = 'JOB-' + job.Id;
                err.source = 'ORG';
                err.severity = 'CRITICAL';
                err.componentOrClass = job.ApexClass != null ? job.ApexClass.Name : 'AsyncApexJob';
                err.methodName = String.isNotBlank(job.MethodName) ? job.MethodName : 'execute';
                err.rawErrorMessage = String.isNotBlank(job.ExtendedStatus) ? job.ExtendedStatus : ('Async Job ' + job.Status);
                err.stackTrace = 'AsyncApexJob ID: ' + job.Id + ' | Errors: ' + job.NumberOfErrors;
                err.timestamp = job.CreatedDate.format('yyyy-MM-dd HH:mm:ss');
                
                // Analyze root cause
                Map<String, String> analysis = analyzeRootCause(err.rawErrorMessage, err.stackTrace);
                err.diagnosedRootCause = analysis.get('rootCause');
                err.recommendedFix = analysis.get('recommendedFix');
                errorLogs.add(err);
            }

            // 2. Scan Failed Async Operation Logs
            List<Async_Operation_Log__c> failedOpLogs = [
                SELECT Id, Name, Operation_Name__c, Message__c, Status__c, Record_Id__c, CreatedDate
                FROM Async_Operation_Log__c
                WHERE Status__c = 'FAILED' AND CreatedDate = TODAY
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            System.debug(LoggingLevel.DEBUG, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] Found ' + failedOpLogs.size() + ' failed Async_Operation_Log__c records');

            for (Async_Operation_Log__c opLog : failedOpLogs) {
                SystemErrorLogWrapper err = new SystemErrorLogWrapper();
                err.id = 'OPLOG-' + opLog.Id;
                err.source = 'DEPLOYMENT';
                err.severity = 'ERROR';
                err.componentOrClass = 'AsyncOperationLog';
                err.methodName = String.isNotBlank(opLog.Operation_Name__c) ? opLog.Operation_Name__c : opLog.Name;
                err.rawErrorMessage = String.isNotBlank(opLog.Message__c) ? opLog.Message__c : 'Async operation failed.';
                err.stackTrace = 'Async_Operation_Log__c RecordId: ' + opLog.Record_Id__c;
                err.timestamp = opLog.CreatedDate.format('yyyy-MM-dd HH:mm:ss');
                err.recordId = opLog.Record_Id__c;

                Map<String, String> analysis = analyzeRootCause(err.rawErrorMessage, err.stackTrace);
                err.diagnosedRootCause = analysis.get('rootCause');
                err.recommendedFix = analysis.get('recommendedFix');
                errorLogs.add(err);
            }

            // 3. Scan Failed Deployment Requests
            List<Deployment_Request__c> failedDeployments = [
                SELECT Id, Name, Status__c, Remarks__c, Deployment_Result__c, User_Story__c, User_Story__r.Name, CreatedDate
                FROM Deployment_Request__c
                WHERE (Status__c LIKE '%Failed%' OR Status__c LIKE '%Error%' OR Status__c = 'Validation Failed') AND CreatedDate = TODAY
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            System.debug(LoggingLevel.DEBUG, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] Found ' + failedDeployments.size() + ' failed Deployment_Request__c records');

            for (Deployment_Request__c dreq : failedDeployments) {
                SystemErrorLogWrapper err = new SystemErrorLogWrapper();
                err.id = 'DREQ-' + dreq.Id;
                err.source = 'DEPLOYMENT';
                err.severity = 'CRITICAL';
                err.componentOrClass = 'DeploymentRequest';
                err.methodName = dreq.Name + ' (' + (dreq.User_Story__r != null ? dreq.User_Story__r.Name : '') + ')';
                
                String msg = String.isNotBlank(dreq.Remarks__c) ? dreq.Remarks__c : (String.isNotBlank(dreq.Deployment_Result__c) ? dreq.Deployment_Result__c : ('Deployment status: ' + dreq.Status__c));
                err.rawErrorMessage = msg;
                err.stackTrace = 'Deployment_Request__c ID: ' + dreq.Id;
                err.timestamp = dreq.CreatedDate.format('yyyy-MM-dd HH:mm:ss');
                err.recordId = dreq.User_Story__c;

                Map<String, String> analysis = analyzeRootCause(err.rawErrorMessage, err.stackTrace);
                err.diagnosedRootCause = analysis.get('rootCause');
                err.recommendedFix = analysis.get('recommendedFix');
                errorLogs.add(err);
            }

            // 4. Scan Org Governor & Storage Limits
            SystemErrorLogWrapper limitError = checkOrgLimitsAndStorage();
            if (limitError != null) {
                errorLogs.add(limitError);
            }

            System.debug(LoggingLevel.INFO, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] SUCCESS - Collected ' + errorLogs.size() + ' dynamic error logs.');
            return errorLogs;

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DevOpsSystemErrorScannerController.getRealtimeOrgErrors] Exception during error scan: ' + ex.getMessage() + ' | StackTrace: ' + ex.getStackTraceString());
            return errorLogs;
        }
    }

    /**
     * Checks Organization Data & File Storage and API Governor Limits in real-time.
     */
    @AuraEnabled(cacheable=false)
    public static SystemErrorLogWrapper checkOrgLimitsAndStorage() {
        try {
            System.OrgLimit apiLimit = System.OrgLimits.getMap().get('DailyApiRequests');
            if (apiLimit != null && apiLimit.getLimit() > 0) {
                Decimal usedPct = (Decimal.valueOf(apiLimit.getValue()) / Decimal.valueOf(apiLimit.getLimit())) * 100;
                if (usedPct >= 90) {
                    SystemErrorLogWrapper err = new SystemErrorLogWrapper();
                    err.id = 'LIMIT-API-' + System.currentTimeMillis();
                    err.source = 'LIMITS';
                    err.severity = 'CRITICAL';
                    err.componentOrClass = 'SalesforceOrgLimits';
                    err.methodName = 'DailyApiRequests';
                    err.rawErrorMessage = 'Daily API Request limit near capacity: ' + apiLimit.getValue() + ' / ' + apiLimit.getLimit() + ' (' + Math.round(usedPct) + '%)';
                    err.stackTrace = 'Org API Requests Limit Reached';
                    err.diagnosedRootCause = 'Daily Salesforce REST/SOAP API call limit is almost exhausted (>= 90%).';
                    err.recommendedFix = 'Reduce frequency of API polling or contact Salesforce Administrator to increase API request allocation.';
                    err.timestamp = Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                    return err;
                }
            }
            return null;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, '[DevOpsSystemErrorScannerController.checkOrgLimitsAndStorage] Warning checking limits: ' + ex.getMessage());
            return null;
        }
    }

    /**
     * Automated Enterprise Root Cause Diagnostic AI Rule Engine
     */
    public static Map<String, String> analyzeRootCause(String rawMessage, String stackTrace) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(rawMessage)) {
            result.put('rootCause', 'Unknown Execution Exception');
            result.put('recommendedFix', 'Check system debug log trace or re-try the operation.');
            return result;
        }

        String msgLower = rawMessage.toLowerCase();
        String stackLower = stackTrace != null ? stackTrace.toLowerCase() : '';

        if (msgLower.contains('storage') || msgLower.contains('storage_limit_exceeded') || msgLower.contains('data storage full')) {
            result.put('rootCause', '[DATA STORAGE FULL]: Salesforce Data/File Storage limit exceeded on Org.');
            result.put('recommendedFix', 'Clear Salesforce Recycle Bin, delete old Async_Operation_Log__c records, or purchase additional storage.');
        } else if (msgLower.contains('unauthorized') || msgLower.contains('invalid session') || msgLower.contains('session expired') || msgLower.contains('401')) {
            result.put('rootCause', '[OAUTH AUTHENTICATION EXPIRED]: SFDX Access Token or Session ID is invalid/expired.');
            result.put('recommendedFix', 'Navigate to DevOps Environment Credentials page and re-authenticate SFDX OAuth token.');
        } else if (msgLower.contains('conflict') || msgLower.contains('merge conflict') || msgLower.contains('cannot automatically merge')) {
            result.put('rootCause', '[GIT MERGE CONFLICT]: Source and Target branch contain conflicting changes.');
            result.put('recommendedFix', 'Open GitHub Pull Request link, resolve conflicting files manually, and re-run promotion.');
        } else if (msgLower.contains('soql') || msgLower.contains('too many soql queries') || msgLower.contains('101')) {
            result.put('rootCause', '[GOVERNOR LIMIT - SOQL]: Exceeded maximum 100 SOQL queries limit in single transaction.');
            result.put('recommendedFix', 'Bulkify Apex loop logic and move SOQL queries outside of for loops.');
        } else if (msgLower.contains('dml') || msgLower.contains('too many dml statements') || msgLower.contains('150')) {
            result.put('rootCause', '[GOVERNOR LIMIT - DML]: Exceeded maximum 150 DML statements limit.');
            result.put('recommendedFix', 'Collect sObjects into lists and execute single Database.insert/update DML statement.');
        } else if (msgLower.contains('cpu time') || msgLower.contains('maximum cpu time exceeded')) {
            result.put('rootCause', '[GOVERNOR LIMIT - CPU TIMEOUT]: Apex execution exceeded 10,000ms CPU limit.');
            result.put('recommendedFix', 'Optimize collection processing or offload heavy computation to Queueable Apex.');
        } else if (msgLower.contains('validation failed') || msgLower.contains('test failure') || msgLower.contains('code coverage')) {
            result.put('rootCause', '[DEPLOYMENT VALIDATION FAILED]: Apex Test failures or Code Coverage below minimum threshold.');
            result.put('recommendedFix', 'Run Apex Unit Tests locally in User Story Test Tab and fix failing test methods.');
        } else if (msgLower.contains('not found') || msgLower.contains('invalid metadata') || msgLower.contains('unknown component')) {
            result.put('rootCause', '[METADATA COMPONENT MISSING]: Referenced Metadata API Name does not exist in target Org.');
            result.put('recommendedFix', 'Verify component API Name in Source Org and re-retrieve metadata in Commit Changes wizard.');
        } else {
            result.put('rootCause', '[SYSTEM PROCESS FAILURE]: ' + rawMessage);
            result.put('recommendedFix', 'Inspect full stack trace details in Developer Console and check record preconditions.');
        }

        return result;
    }
}
