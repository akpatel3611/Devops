public with sharing class PipelineMetadataProcessor {

    // ==========================================
    // ARCHITECTURAL CONSTANTS
    // ==========================================
    public static final String STATUS_SCANNING = 'Scanning';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_VALIDATING = 'Validating';
    public static final String STATUS_DEPLOYING = 'Deploying';

    // ==========================================
    // DTO WRAPPERS
    // ==========================================
    
    public class ProcessorMetadataComponent {
        @AuraEnabled public String componentName {get;set;}
        @AuraEnabled public String apiName {get;set;}
        @AuraEnabled public String metadataType {get;set;}
        @AuraEnabled public String packageXmlType {get;set;}
        @AuraEnabled public String filePath {get;set;}
        @AuraEnabled public String folder {get;set;}
        @AuraEnabled public String extension {get;set;}
        @AuraEnabled public Boolean deployable {get;set;}
        @AuraEnabled public Boolean deleted {get;set;}
        @AuraEnabled public Boolean changed {get;set;}
        @AuraEnabled public Boolean supported {get;set;}
        @AuraEnabled public String status {get;set;}
    }

    public class ProcessorMetadataResult {
        @AuraEnabled public Integer totalFiles {get;set;}
        @AuraEnabled public Integer supportedFiles {get;set;}
        @AuraEnabled public Integer unsupportedFiles {get;set;}
        @AuraEnabled public Integer deployableFiles {get;set;}
        @AuraEnabled public Integer metadataCount {get;set;}
        @AuraEnabled public List<ProcessorMetadataComponent> metadataComponents {get;set;}
    }

    public class PipelineProcessorResult {
        @AuraEnabled public Boolean success {get;set;}
        @AuraEnabled public String message {get;set;}
        @AuraEnabled public ProcessorMetadataResult metadataResult {get;set;}
        @AuraEnabled public Integer metadataCount {get;set;}
        @AuraEnabled public Integer deployableCount {get;set;}
        @AuraEnabled public Integer unsupportedCount {get;set;}
        @AuraEnabled public Id pipelineId {get;set;}
        @AuraEnabled public Id deploymentRequestId {get;set;}
        @AuraEnabled public Id userStoryId {get;set;}
        @AuraEnabled public Datetime scanStartTime {get;set;}
        @AuraEnabled public Datetime scanEndTime {get;set;}
        @AuraEnabled public Long processingDuration {get;set;}
        @AuraEnabled public List<String> warnings {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
        
        // Runtime platform status fields
        @AuraEnabled public String pipelineStatus {get;set;}
        @AuraEnabled public String validationStatus {get;set;}
        @AuraEnabled public String deploymentStatus {get;set;}
        @AuraEnabled public String buildStatus {get;set;}
        @AuraEnabled public String scanStatus {get;set;}
        
        // Automation engines control flags
        @AuraEnabled public Boolean readyForValidation {get;set;}
        @AuraEnabled public Boolean readyForDeployment {get;set;}
        @AuraEnabled public Boolean hasErrors {get;set;}
        @AuraEnabled public Boolean hasWarnings {get;set;}
        @AuraEnabled public String processorVersion {get;set;}
    }

    // ==========================================
    // PUBLIC MAIN ENTRY POINT
    // ==========================================
    
    /**
     * Executes the orchestration pipeline: scans metadata, invokes persistence updates, and returns a processor result.
     */
    public static PipelineProcessorResult process(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        List<MetadataScannerService.ChangedFile> files, 
        String scanSource
    ) {
        Datetime startTime = System.now();
        System.debug('PipelineMetadataProcessor execution started on: ' + startTime);
        
        // Track errors and warnings internally via Set to avoid duplicates
        Set<String> warningSet = new Set<String>();
        Set<String> errorSet = new Set<String>();
        
        try {
            // Step 1: Input Validation
            if (!validateInput(files, errorSet)) {
                PipelineProcessorResult earlyResult = buildEarlyResult(pipelineId, deploymentRequestId, userStoryId, startTime, errorSet, warningSet);
                System.debug('Early exit - no files to process');
                return earlyResult;
            }
            
            // Step 2: Call Metadata Scanner Service
            MetadataScannerService.MetadataScannerResult scannerResult = scanMetadata(files, scanSource);
            
            // Persist User Story Metadata components list before statistics update (Single Responsibility Principle)
            if (userStoryId != null && scannerResult != null && scannerResult.metadataComponents != null) {
                UserStoryMetadataService.persistMetadata(userStoryId, scannerResult.metadataComponents);
            }

            ProcessorMetadataResult convertedResult = convertScannerResult(scannerResult, warningSet, errorSet);
            
            // Analyze scanner success/errors
            Boolean hasProcessingErrors = !errorSet.isEmpty();
            String targetScanStatus = hasProcessingErrors ? STATUS_FAILED : STATUS_COMPLETED;
            
            // Step 3, 4, 5: Persist runtime updates using separate runtime updater service (No direct DML)
            updateRuntimeObjects(pipelineId, deploymentRequestId, userStoryId, convertedResult, targetScanStatus, errorSet);
            
            // Step 6: Build Success Result
            PipelineProcessorResult successResult = buildSuccessResult(
                pipelineId, 
                deploymentRequestId, 
                userStoryId, 
                startTime, 
                convertedResult, 
                targetScanStatus, 
                warningSet, 
                errorSet
            );
            System.debug('PipelineMetadataProcessor completed successfully on: ' + System.now());
            return successResult;
            
        } catch (Exception e) {
            System.debug('Exception encountered during PipelineMetadataProcessor execution: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString());
            errorSet.add('Processor System Error: ' + e.getMessage());
            return buildFailureResult(pipelineId, deploymentRequestId, userStoryId, startTime, warningSet, errorSet);
        }
    }

    // ==========================================
    // PRIVATE IMPLEMENTATION HELPERS
    // ==========================================
    
    private static Boolean validateInput(List<MetadataScannerService.ChangedFile> files, Set<String> errors) {
        if (files == null || files.isEmpty()) {
            return false;
        }
        return true;
    }

    private static MetadataScannerService.MetadataScannerResult scanMetadata(List<MetadataScannerService.ChangedFile> files, String scanSource) {
        return MetadataScannerService.discoverMetadata(files, scanSource);
    }

    private static void updateRuntimeObjects(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        ProcessorMetadataResult scanResult, 
        String targetScanStatus,
        Set<String> errors
    ) {
        try {
            Integer metadataCount = scanResult.metadataCount != null ? scanResult.metadataCount : 0;
            Integer deployableCount = scanResult.deployableFiles != null ? scanResult.deployableFiles : 0;
            Integer unsupportedCount = scanResult.unsupportedFiles != null ? scanResult.unsupportedFiles : 0;
            
            PipelineRuntimeUpdaterService.updateMetadataStats(
                pipelineId,
                deploymentRequestId,
                userStoryId,
                metadataCount,
                deployableCount,
                unsupportedCount,
                targetScanStatus
            );
        } catch (Exception e) {
            System.debug('Database persistence failed: ' + e.getMessage());
            errors.add('Database persistence error: ' + e.getMessage());
        }
    }

    private static ProcessorMetadataResult convertScannerResult(
        MetadataScannerService.MetadataScannerResult scannerResult, 
        Set<String> warnings, 
        Set<String> errors
    ) {
        ProcessorMetadataResult result = new ProcessorMetadataResult();
        if (scannerResult == null) {
            result.totalFiles = 0;
            result.supportedFiles = 0;
            result.unsupportedFiles = 0;
            result.deployableFiles = 0;
            result.metadataCount = 0;
            result.metadataComponents = new List<ProcessorMetadataComponent>();
            return result;
        }
        
        result.totalFiles = scannerResult.totalFiles;
        result.supportedFiles = scannerResult.supportedFiles;
        result.unsupportedFiles = scannerResult.unsupportedFiles;
        result.deployableFiles = scannerResult.deployableFiles;
        result.metadataCount = scannerResult.metadataCount;
        
        // Map warnings and errors
        if (scannerResult.warnings != null) {
            warnings.addAll(scannerResult.warnings);
        }
        if (scannerResult.errors != null) {
            errors.addAll(scannerResult.errors);
        }
        
        result.metadataComponents = convertMetadataComponents(scannerResult.metadataComponents);
        return result;
    }

    private static List<ProcessorMetadataComponent> convertMetadataComponents(List<MetadataScannerService.MetadataComponent> scannerComps) {
        List<ProcessorMetadataComponent> comps = new List<ProcessorMetadataComponent>();
        if (scannerComps == null) {
            return comps;
        }
        
        for (MetadataScannerService.MetadataComponent scanComp : scannerComps) {
            if (scanComp == null) {
                continue;
            }
            ProcessorMetadataComponent comp = new ProcessorMetadataComponent();
            comp.componentName = scanComp.componentName;
            comp.apiName = scanComp.apiName;
            comp.metadataType = scanComp.metadataType;
            comp.packageXmlType = scanComp.packageXmlType;
            comp.filePath = scanComp.filePath;
            comp.folder = scanComp.folder;
            comp.extension = scanComp.extension;
            comp.deployable = scanComp.deployable;
            comp.deleted = scanComp.deleted;
            comp.changed = scanComp.changed;
            comp.supported = scanComp.supported;
            comp.status = scanComp.status;
            comps.add(comp);
        }
        return comps;
    }

    private static PipelineProcessorResult buildEarlyResult(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        Datetime startTime, 
        Set<String> errors, 
        Set<String> warnings
    ) {
        PipelineProcessorResult result = new PipelineProcessorResult();
        result.success = true;
        result.message = 'No changed files found to process.';
        result.pipelineId = pipelineId;
        result.deploymentRequestId = deploymentRequestId;
        result.userStoryId = userStoryId;
        result.scanStartTime = startTime;
        result.scanEndTime = System.now();
        result.processingDuration = result.scanEndTime.getTime() - startTime.getTime();
        
        result.metadataCount = 0;
        result.deployableCount = 0;
        result.unsupportedCount = 0;
        
        result.pipelineStatus = STATUS_COMPLETED;
        result.validationStatus = STATUS_PENDING;
        result.deploymentStatus = STATUS_PENDING;
        result.buildStatus = STATUS_COMPLETED;
        result.scanStatus = STATUS_COMPLETED;
        
        result.readyForValidation = false;
        result.readyForDeployment = false;
        result.hasErrors = false;
        result.hasWarnings = false;
        result.processorVersion = '1.0.0';
        
        result.errors = new List<String>(errors);
        result.warnings = new List<String>(warnings);
        return result;
    }

    private static PipelineProcessorResult buildSuccessResult(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        Datetime startTime, 
        ProcessorMetadataResult convertedResult, 
        String targetScanStatus,
        Set<String> warnings, 
        Set<String> errors
    ) {
        PipelineProcessorResult result = new PipelineProcessorResult();
        result.metadataResult = convertedResult;
        result.pipelineId = pipelineId;
        result.deploymentRequestId = deploymentRequestId;
        result.userStoryId = userStoryId;
        result.scanStartTime = startTime;
        result.scanEndTime = System.now();
        result.processingDuration = result.scanEndTime.getTime() - startTime.getTime();
        
        result.metadataCount = convertedResult.metadataCount != null ? convertedResult.metadataCount : 0;
        result.deployableCount = convertedResult.deployableFiles != null ? convertedResult.deployableFiles : 0;
        result.unsupportedCount = convertedResult.unsupportedFiles != null ? convertedResult.unsupportedFiles : 0;
        
        result.hasErrors = !errors.isEmpty();
        result.hasWarnings = !warnings.isEmpty();
        
        result.success = !result.hasErrors;
        result.message = result.success ? 'Metadata processing completed successfully.' : 'Metadata processing completed with compilation errors.';
        
        result.pipelineStatus = result.success ? STATUS_COMPLETED : STATUS_FAILED;
        result.validationStatus = STATUS_PENDING;
        result.deploymentStatus = STATUS_PENDING;
        result.buildStatus = result.success ? STATUS_COMPLETED : STATUS_FAILED;
        result.scanStatus = targetScanStatus;
        
        result.readyForValidation = result.success && result.deployableCount > 0;
        result.readyForDeployment = false; // Deployment engine triggers later
        result.processorVersion = '1.0.0';
        
        result.errors = new List<String>(errors);
        result.warnings = new List<String>(warnings);
        return result;
    }

    private static PipelineProcessorResult buildFailureResult(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        Datetime startTime, 
        Set<String> warnings, 
        Set<String> errors
    ) {
        PipelineProcessorResult result = new PipelineProcessorResult();
        result.success = false;
        result.message = 'System failure encountered during metadata processing.';
        result.pipelineId = pipelineId;
        result.deploymentRequestId = deploymentRequestId;
        result.userStoryId = userStoryId;
        result.scanStartTime = startTime;
        result.scanEndTime = System.now();
        result.processingDuration = result.scanEndTime.getTime() - startTime.getTime();
        
        result.metadataCount = 0;
        result.deployableCount = 0;
        result.unsupportedCount = 0;
        
        result.pipelineStatus = STATUS_FAILED;
        result.validationStatus = STATUS_PENDING;
        result.deploymentStatus = STATUS_PENDING;
        result.buildStatus = STATUS_FAILED;
        result.scanStatus = STATUS_FAILED;
        
        result.readyForValidation = false;
        result.readyForDeployment = false;
        result.hasErrors = true;
        result.hasWarnings = !warnings.isEmpty();
        result.processorVersion = '1.0.0';
        
        result.errors = new List<String>(errors);
        result.warnings = new List<String>(warnings);
        return result;
    }
}