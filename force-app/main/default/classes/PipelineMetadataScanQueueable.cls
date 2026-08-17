/**
 * Queueable orchestrator class responsible for fetching changed files from GitHub
 * and running the metadata processor asynchronously within a fresh transaction boundary.
 */
public with sharing class PipelineMetadataScanQueueable implements Queueable, Database.AllowsCallouts {

    public class PipelineMetadataScanQueueableException extends Exception {}

    private Id pipelineId;
    private Id deploymentRequestId;
    private Id userStoryId;
    private String requestDataJson;

    /**
     * Constructor accepting context identifiers and serialized request DTO.
     */
    public PipelineMetadataScanQueueable(
        Id pipelineId, 
        Id deploymentRequestId, 
        Id userStoryId, 
        String requestDataJson
    ) {
        this.pipelineId = pipelineId;
        this.deploymentRequestId = deploymentRequestId;
        this.userStoryId = userStoryId;
        this.requestDataJson = requestDataJson;
    }

    /**
     * Executes the asynchronous metadata scanning phase.
     */
    public void execute(QueueableContext context) {
        Id jobId = (context != null) ? context.getJobId() : null;
        System.debug(LoggingLevel.INFO, '[PipelineMetadataScanQueueable.execute] START - JobId: ' + jobId + ' | pipelineId: ' + pipelineId + ' | deploymentRequestId: ' + deploymentRequestId + ' | userStoryId: ' + userStoryId);
        try {
            if (String.isBlank(requestDataJson)) {
                System.debug(LoggingLevel.ERROR, '[PipelineMetadataScanQueueable.execute] Request data payload is missing.');
                throw new PipelineMetadataScanQueueableException('Request data payload is missing.');
            }
            
            GitHubRecordService.GitHubRecordData requestData;
            try {
                requestData = (GitHubRecordService.GitHubRecordData) JSON.deserialize(
                    requestDataJson,
                    GitHubRecordService.GitHubRecordData.class
                );
                System.debug(LoggingLevel.DEBUG, '[PipelineMetadataScanQueueable.execute] Deserialized PR payload - PR: ' + requestData.pullRequestNumber + ' | Repo: ' + requestData.repositoryName);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, '[PipelineMetadataScanQueueable.execute] Failed to deserialize payload: ' + ex.getMessage());
                throw new PipelineMetadataScanQueueableException('Failed to deserialize request data: ' + ex.getMessage());
            }

            // Step 1: Fetch changed files from GitHub REST API (Callout)
            System.debug(LoggingLevel.FINE, '[PipelineMetadataScanQueueable.execute] Fetching changed files from GitHub via GitHubPullRequestFilesService...');
            List<MetadataScannerService.ChangedFile> files = 
                GitHubPullRequestFilesService.fetchChangedFiles(requestData);
            System.debug(LoggingLevel.DEBUG, '[PipelineMetadataScanQueueable.execute] Fetched ' + (files != null ? files.size() : 0) + ' changed files from GitHub.');

            // Step 2: Trigger metadata scanning and classification processor
            System.debug(LoggingLevel.FINE, '[PipelineMetadataScanQueueable.execute] Triggering PipelineMetadataProcessor.process...');
            PipelineMetadataProcessor.PipelineProcessorResult result = 
                PipelineMetadataProcessor.process(
                    pipelineId,
                    deploymentRequestId,
                    userStoryId,
                    files,
                    'GitHub'
                );
            System.debug(LoggingLevel.INFO, '[PipelineMetadataScanQueueable.execute] SUCCESS - JobId: ' + jobId + ' completed processing.');

            if (result != null && !result.success) {
                String errorMsg = (result.errors != null && !result.errors.isEmpty()) 
                    ? String.join(result.errors, '; ') 
                    : 'Processor completed with errors.';
                throw new PipelineMetadataScanQueueableException(errorMsg);
            }

            // Step 3: Trigger the actual Salesforce deployment for this request
            if (this.deploymentRequestId != null) {
                DeploymentRuntimeService.startDeployment(this.deploymentRequestId, 'Deploy');
            }

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Exception in PipelineMetadataScanQueueable: ' + ex.getMessage());
            updatePipelineToFailed(pipelineId);
            throw ex;
        }
    }

    /**
     * Helper to update the pipeline status to Failed by delegating exclusively to PipelineRuntimeUpdaterService.
     * No direct DML operations are performed.
     */
    private void updatePipelineToFailed(Id pipeId) {
        try {
            PipelineRuntimeUpdaterService.updateMetadataStats(
                pipeId,
                deploymentRequestId,
                userStoryId,
                0,
                0,
                0,
                'Failed'
            );
        } catch (Exception updateEx) {
            System.debug(LoggingLevel.ERROR, 'Failed to delegate pipeline status update: ' + updateEx.getMessage());
        }
    }
}