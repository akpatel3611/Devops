/**
 * Service layer that interprets GitHub webhook payloads and delegates database
 * work to GitHubRecordService.
 */
public with sharing class GitHubIntegrationService {
    private static final String EVENT_PULL_REQUEST = 'pull_request';
    private static final String EVENT_PULL_REQUEST_REVIEW = 'pull_request_review';
    private static final String EVENT_PUSH = 'push';
    private static final String EVENT_PING = 'ping';

    private static final String ACTION_OPENED = 'opened';
    private static final String ACTION_SYNCHRONIZE = 'synchronize';
    private static final String ACTION_REOPENED = 'reopened';
    private static final String ACTION_CLOSED = 'closed';
    private static final String ACTION_EDITED = 'edited';

    private static final String STATUS_PROCESSED = 'processed';
    private static final String STATUS_IGNORED = 'ignored';

    private static final Set<String> SUPPORTED_EVENTS = new Set<String>{
        EVENT_PULL_REQUEST,
        EVENT_PULL_REQUEST_REVIEW,
        EVENT_PUSH,
        EVENT_PING
    };

    private static final Set<String> SUPPORTED_PULL_REQUEST_ACTIONS = new Set<String>{
        ACTION_OPENED,
        ACTION_SYNCHRONIZE,
        ACTION_REOPENED,
        ACTION_CLOSED,
        ACTION_EDITED
    };

    /**
     * Processes one GitHub webhook payload.
     *
     * @param rawJson Raw JSON request body.
     * @param eventName X-GitHub-Event value.
     * @param deliveryId X-GitHub-Delivery value.
     * @param signature X-Hub-Signature-256 value.
     * @param userAgent User-Agent value.
     * @return Webhook processing result.
     */
    public static WebhookResult processWebhook(
        String rawJson,
        String eventName,
        String deliveryId,
        String signature,
        String userAgent
    ) {
        validateEnvelope(rawJson, eventName, deliveryId);

        String normalizedEvent = eventName.trim().toLowerCase();
        WebhookResult result = new WebhookResult();
        result.deliveryId = deliveryId;
        result.eventName = normalizedEvent;
        result.status = STATUS_IGNORED;
        result.message = 'GitHub event ignored.';

        if (!SUPPORTED_EVENTS.contains(normalizedEvent)) {
            return result;
        }

        WebhookPayload payload = parsePayload(rawJson);
        if (normalizedEvent == EVENT_PULL_REQUEST) {
            return processPullRequest(payload, normalizedEvent, deliveryId, signature, userAgent);
        }

        if (normalizedEvent == EVENT_PUSH || normalizedEvent == EVENT_PING) {
            GitHubRecordService.RecordResult recordResult =
                GitHubRecordService.processRepositoryEvent(
                    buildRecordData(payload, normalizedEvent, deliveryId, signature, userAgent)
                );
            result.status = recordResult.status;
            result.message = recordResult.message;
            return result;
        }

        return result;
    }

    /**
     * Validates basic input passed from the controller.
     */
    private static void validateEnvelope(String rawJson, String eventName, String deliveryId) {
        if (String.isBlank(rawJson)) {
            throw new PayloadException('GitHub payload is required.');
        }
        if (String.isBlank(eventName)) {
            throw new PayloadException('GitHub event type is required.');
        }
        if (String.isBlank(deliveryId)) {
            throw new PayloadException('GitHub delivery id is required.');
        }
    }

    /**
     * Deserializes raw JSON into strongly typed GitHub wrapper classes.
     */
    private static WebhookPayload parsePayload(String rawJson) {
        try {
            return (WebhookPayload) JSON.deserialize(normalizeReservedJsonKeys(rawJson), WebhookPayload.class);
        } catch (Exception parseException) {
            throw new PayloadException('GitHub payload JSON is invalid.');
        }
    }

    /**
     * Normalizes GitHub keys that collide with Apex reserved identifiers.
     */
    private static String normalizeReservedJsonKeys(String rawJson) {
        return rawJson.replace('"number"', '"numberValue"');
    }

    /**
     * Processes supported pull request webhook actions.
     */
    private static WebhookResult processPullRequest(
        WebhookPayload payload,
        String eventName,
        String deliveryId,
        String signature,
        String userAgent
    ) {
        WebhookResult result = new WebhookResult();
        result.deliveryId = deliveryId;
        result.eventName = eventName;

        validatePullRequestPayload(payload);

        String action = payload.action == null ? null : payload.action.trim().toLowerCase();
        if (!SUPPORTED_PULL_REQUEST_ACTIONS.contains(action)) {
            result.status = STATUS_IGNORED;
            result.message = 'Pull request action ignored.';
            return result;
        }

        GitHubRecordService.RecordResult recordResult =
            GitHubRecordService.processPullRequest(
                buildRecordData(payload, eventName, deliveryId, signature, userAgent)
            );
        result.status = recordResult.status;
        result.message = recordResult.message;

        return result;
    }

    /**
     * Validates required pull request payload sections.
     */
    private static void validatePullRequestPayload(WebhookPayload payload) {
        if (payload == null) {
            throw new PayloadException('GitHub payload cannot be empty.');
        }
        if (payload.repository == null) {
            throw new PayloadException('GitHub repository payload is required.');
        }
        if (payload.pull_request == null) {
            throw new PayloadException('GitHub pull request payload is required.');
        }
        if (String.isBlank(payload.action)) {
            throw new PayloadException('GitHub pull request action is required.');
        }
    }

    /**
     * Maps GitHub wrappers into record-service data transfer object.
     */
    private static GitHubRecordService.GitHubRecordData buildRecordData(
        WebhookPayload payload,
        String eventName,
        String deliveryId,
        String signature,
        String userAgent
    ) {
        GitHubRecordService.GitHubRecordData data = new GitHubRecordService.GitHubRecordData();
        data.eventName = eventName;
        data.deliveryId = deliveryId;
        data.signature = signature;
        data.userAgent = userAgent;

        if (payload == null) {
            return data;
        }

        data.action = payload.action;
        mapRepository(payload.repository, data);
        mapPullRequest(payload.pull_request, data);
        mapSender(payload.sender, data);

        if (data.changedFiles == null) {
            data.changedFiles = new List<GitHubIntegrationService.GitHubChangedFile>();
        }

        return data;
    }

    /**
     * Maps repository fields.
     */
    private static void mapRepository(Repository repository, GitHubRecordService.GitHubRecordData data) {
        if (repository == null) {
            return;
        }

        data.repositoryGitHubId = repository.id == null ? null : String.valueOf(repository.id);
        data.repositoryName = repository.name;
        data.repositoryFullName = repository.full_name;
        data.repositoryUrl = firstNonBlank(repository.html_url, repository.clone_url);
        data.repositoryDefaultBranch = repository.default_branch;
        data.repositoryOwner = repository.owner == null ? null : repository.owner.login;
    }

    /**
     * Maps pull request fields.
     */
    private static void mapPullRequest(PullRequest pullRequest, GitHubRecordService.GitHubRecordData data) {
        if (pullRequest == null) {
            return;
        }

        data.pullRequestNumber = pullRequest.numberValue;
        data.pullRequestTitle = pullRequest.title;
        data.pullRequestDescription = pullRequest.body;
        data.pullRequestUrl = pullRequest.html_url;
        data.pullRequestState = pullRequest.state;
        data.pullRequestAuthor = pullRequest.user == null ? null : pullRequest.user.login;
        data.sourceBranch = pullRequest.head == null ? null : pullRequest.head.ref;
        data.sourceSha = pullRequest.head == null ? null : pullRequest.head.sha;
        data.targetBranch = pullRequest.base == null ? null : pullRequest.base.ref;
        data.targetSha = pullRequest.base == null ? null : pullRequest.base.sha;
        data.createdAt = pullRequest.created_at;
        data.updatedAt = pullRequest.updated_at;
        data.closedAt = pullRequest.closed_at;
        data.mergedAt = pullRequest.merged_at;
        data.isMerged = pullRequest.merged;
    }

    /**
     * Maps sender fields.
     */
    private static void mapSender(User sender, GitHubRecordService.GitHubRecordData data) {
        if (sender == null || String.isNotBlank(data.pullRequestAuthor)) {
            return;
        }

        data.pullRequestAuthor = sender.login;
    }

    /**
     * Returns the first non-blank string.
     */
    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : secondValue;
    }

    /**
     * Integration result returned to the REST controller.
     */
    public class WebhookResult {
        public String deliveryId;
        public String eventName;
        public String status;
        public String message;
    }

    /**
     * Root GitHub webhook payload wrapper.
     */
    public class WebhookPayload {
        public String action;
        public Repository repository;
        public PullRequest pull_request;
        public User sender;
        public String ref;
        public String before;
        public String after;
        public String zen;
    }

    /**
     * GitHub repository wrapper.
     */
    public class Repository {
        public Long id;
        public String name;
        public String full_name;
        public String html_url;
        public String clone_url;
        public String default_branch;
        public User owner;
    }

    /**
     * GitHub pull request wrapper.
     */
    public class PullRequest {
        public Integer numberValue;
        public String title;
        public String body;
        public String state;
        public String html_url;
        public User user;
        public Head head;
        public Base base;
        public Boolean merged;
        public String created_at;
        public String updated_at;
        public String closed_at;
        public String merged_at;
    }

    /**
     * GitHub user wrapper.
     */
    public class User {
        public Long id;
        public String login;
        public String html_url;
        public String type;
    }

    /**
     * Pull request branch wrapper.
     */
    public virtual class Branch {
        public String ref;
        public String sha;
        public String label;
        public Repository repo;
        public User user;
    }

    /**
     * Pull request source branch wrapper.
     */
    public class Head extends Branch {
    }

    /**
     * Pull request target branch wrapper.
     */
    public class Base extends Branch {
    }

    /**
     * Wrapper class for representing changed files in a GitHub Pull Request.
     */
    public class GitHubChangedFile {
        public String filename;
        public String status;
        public Integer additions;
        public Integer deletions;
        public Integer changes;
        public String previous_filename;
        public String sha;
        public String blob_url;
        public String raw_url;
        public String contents_url;
        public String patch;
    }

    /**
     * Exception for invalid GitHub payload data.
     */
    public class PayloadException extends Exception {
    }
}