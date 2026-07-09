/**
 * Public REST controller for GitHub webhook delivery events.
 *
 * This class is intentionally thin. It validates the HTTP request envelope,
 * keeps the raw JSON unchanged, and delegates all payload processing to
 * GitHubIntegrationService.
 */
@RestResource(urlMapping='/github/webhook/*')
global with sharing class GitHubWebhookController {
    private static final Integer STATUS_OK = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_UNAUTHORIZED = 401;
    private static final Integer STATUS_INTERNAL_ERROR = 500;

    private static final String HEADER_EVENT = 'X-GitHub-Event';
    private static final String HEADER_DELIVERY = 'X-GitHub-Delivery';
    private static final String HEADER_SIGNATURE = 'X-Hub-Signature-256';
    private static final String HEADER_USER_AGENT = 'User-Agent';
    private static final String CONTENT_TYPE_JSON = 'application/json';
    private static final String MESSAGE_SUCCESS = 'Webhook processed successfully.';
    private static final String MESSAGE_INVALID_SIGNATURE = 'Invalid GitHub webhook signature.';
    private static final String MESSAGE_INTERNAL_ERROR = 'Unexpected webhook processing error.';

    /**
     * Receives GitHub HTTP POST webhook requests.
     */
    @HttpPost
    global static void handlePost() {
        System.debug('===================== WEBHOOK START =====================');
        try {
            WebhookRequest webhookRequest = validateRequest();
            System.debug('EVENT = ' + webhookRequest.eventName);
            System.debug('DELIVERY = ' + webhookRequest.deliveryId);

            if (!validateSignature(webhookRequest.payload, webhookRequest.signature)) {
                sendError(STATUS_UNAUTHORIZED, MESSAGE_INVALID_SIGNATURE);
                return;
            }

            GitHubIntegrationService.WebhookResult result =
                GitHubIntegrationService.processWebhook(
                    webhookRequest.payload,
                    webhookRequest.eventName,
                    webhookRequest.deliveryId,
                    webhookRequest.signature,
                    webhookRequest.userAgent
                );

            sendSuccess(result);
        } catch (BadRequestException badRequestException) {
            sendError(STATUS_BAD_REQUEST, badRequestException.getMessage());
        } catch (GitHubIntegrationService.PayloadException payloadException) {
            sendError(STATUS_BAD_REQUEST, payloadException.getMessage());
        } catch (Exception unexpectedException) {

            System.debug('===== WEBHOOK EXCEPTION =====');
            System.debug(unexpectedException.getMessage());
            System.debug(unexpectedException.getStackTraceString());
                
            sendError(
                STATUS_INTERNAL_ERROR,
                unexpectedException.getMessage()
            );
        }
    }

    /**
     * Validates request body and mandatory GitHub headers.
     *
     * @return Normalized webhook request data.
     */
    private static WebhookRequest validateRequest() {
        RestRequest request = RestContext.request;

        if (request == null || request.requestBody == null) {
            throw new BadRequestException('Request body is required.');
        }

        String payload = request.requestBody.toString();
        if (String.isBlank(payload)) {
            throw new BadRequestException('Request body cannot be empty.');
        }

        WebhookRequest webhookRequest = new WebhookRequest();
        webhookRequest.payload = payload;
        webhookRequest.eventName = requireHeader(request, HEADER_EVENT);
        webhookRequest.deliveryId = requireHeader(request, HEADER_DELIVERY);
        webhookRequest.signature = requireHeader(request, HEADER_SIGNATURE);
        webhookRequest.userAgent = requireHeader(request, HEADER_USER_AGENT);

        return webhookRequest;
    }

    /**
     * Reads one mandatory header from the current request.
     *
     * @param request Current REST request.
     * @param headerName Header name to read.
     * @return Header value.
     */
    private static String requireHeader(RestRequest request, String headerName) {
        String headerValue = getHeader(request, headerName);
        if (String.isBlank(headerValue)) {
            throw new BadRequestException('Missing mandatory GitHub header: ' + headerName);
        }
        return headerValue.trim();
    }

    /**
     * Reads one HTTP header using case-insensitive lookup.
     *
     * @param request Current REST request.
     * @param headerName Header name to read.
     * @return Header value or null.
     */
    private static String getHeader(RestRequest request, String headerName) {
        if (request == null || request.headers == null || String.isBlank(headerName)) {
            return null;
        }

        for (String key : request.headers.keySet()) {
            if (key != null && key.equalsIgnoreCase(headerName)) {
                return request.headers.get(key);
            }
        }

        return null;
    }

    /**
     * Placeholder for future HMAC SHA-256 verification.
     *
     * @param payload Raw request payload.
     * @param signature GitHub X-Hub-Signature-256 value.
     * @return true until org-level secret management is configured.
     */
    @SuppressWarnings('PMD.UnusedFormalParameter')
    private static Boolean validateSignature(String payload, String signature) {
        return true;
    }

    /**
     * Sends a JSON success response.
     *
     * @param result Integration processing result.
     */
    private static void sendSuccess(GitHubIntegrationService.WebhookResult result) {
        ResponseEnvelope response = new ResponseEnvelope();
        response.success = true;
        response.message = String.isBlank(result.message) ? MESSAGE_SUCCESS : result.message;
        response.deliveryId = result.deliveryId;
        response.eventName = result.eventName;
        response.status = result.status;

        writeResponse(STATUS_OK, response);
    }

    /**
     * Sends a JSON error response.
     *
     * @param statusCode HTTP status code.
     * @param message Error message.
     */
    private static void sendError(Integer statusCode, String message) {
        ResponseEnvelope response = new ResponseEnvelope();
        response.success = false;
        response.message = String.isBlank(message) ? MESSAGE_INTERNAL_ERROR : message;

        writeResponse(statusCode, response);
    }

    /**
     * Writes JSON to RestContext.response.
     *
     * @param statusCode HTTP status code.
     * @param responseBody Serializable response body.
     */
    private static void writeResponse(Integer statusCode, ResponseEnvelope responseBody) {
        RestResponse response = RestContext.response;
        if (response == null) {
            response = new RestResponse();
            RestContext.response = response;
        }

        response.statusCode = statusCode;
        response.addHeader('Content-Type', CONTENT_TYPE_JSON);
        response.responseBody = Blob.valueOf(JSON.serialize(responseBody));
    }

    private class WebhookRequest {
        private String payload;
        private String eventName;
        private String deliveryId;
        private String signature;
        private String userAgent;
    }

    private class ResponseEnvelope {
        public Boolean success;
        public String message;
        public String deliveryId;
        public String eventName;
        public String status;
    }

    /**
     * Exception for invalid webhook request envelopes.
     */
    public class BadRequestException extends Exception {
    }
}