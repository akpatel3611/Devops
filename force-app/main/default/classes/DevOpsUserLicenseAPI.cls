@RestResource(urlMapping='/DevOpsUserLicense/*')
global with sharing class DevOpsUserLicenseAPI {

    global class TelemetryPayload {
        global String organizationId;
        global String organizationName;
        global String timestamp;
        global DevOpsGlobalAPI.LicenseInfo licenseMetrics;
        global List<DevOpsGlobalAPI.UserLicenseDetail> assignedUserLicenses;
    }

    /**
     * HTTP GET Endpoint: Returns active subscriber user license entitlements for backend telemetry sync.
     * Endpoint URL: /services/apexrest/DevOpsUserLicense/
     */
    @HttpGet
    global static TelemetryPayload getSubscriberUserLicenses() {
        System.debug(LoggingLevel.INFO, '[DevOpsUserLicenseAPI.getSubscriberUserLicenses] REST GET Request received.');
        TelemetryPayload payload = new TelemetryPayload();
        
        try {
            payload.organizationId = UserInfo.getOrganizationId();
            payload.organizationName = UserInfo.getOrganizationName();
            payload.timestamp = System.now().format('yyyy-MM-dd HH:mm:ss');

            DevOpsGlobalAPI globalApi = new DevOpsGlobalAPI();
            payload.licenseMetrics = globalApi.getLicenseInformation();
            payload.assignedUserLicenses = globalApi.listUserLicenses(null);

            System.debug(LoggingLevel.INFO, '[DevOpsUserLicenseAPI.getSubscriberUserLicenses] Payload generated successfully.');
            return payload;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DevOpsUserLicenseAPI.getSubscriberUserLicenses] Exception: ' + ex.getMessage());
            payload.organizationId = UserInfo.getOrganizationId();
            payload.timestamp = System.now().format('yyyy-MM-dd HH:mm:ss');
            return payload;
        }
    }
}
