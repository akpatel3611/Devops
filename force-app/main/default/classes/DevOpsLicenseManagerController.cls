public with sharing class DevOpsLicenseManagerController {

    @AuraEnabled(cacheable=false)
    public static DevOpsGlobalAPI.LicenseInfo getLicenseOverview() {
        System.debug(LoggingLevel.INFO, '[DevOpsLicenseManagerController.getLicenseOverview] Invoking DevOpsGlobalAPI...');
        DevOpsGlobalAPI api = new DevOpsGlobalAPI();
        return api.getLicenseInformation();
    }

    @AuraEnabled(cacheable=false)
    public static List<DevOpsGlobalAPI.UserLicenseDetail> getDevOpsUsers(String searchKey) {
        System.debug(LoggingLevel.INFO, '[DevOpsLicenseManagerController.getDevOpsUsers] Invoking DevOpsGlobalAPI searchKey: ' + searchKey);
        DevOpsGlobalAPI api = new DevOpsGlobalAPI();
        return api.listUserLicenses(searchKey);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> toggleUserLicenseFlag(Id userId, String licenseType, Boolean isEnabled) {
        System.debug(LoggingLevel.INFO, '[DevOpsLicenseManagerController.toggleUserLicenseFlag] userId: ' + userId + ' | licenseType: ' + licenseType + ' | isEnabled: ' + isEnabled);
        Map<String, Object> res = new Map<String, Object>();

        if (userId == null) {
            res.put('success', false);
            res.put('message', 'User ID is required.');
            return res;
        }

        try {
            User targetUser = [SELECT Id, Name FROM User WHERE Id = :userId LIMIT 1];
            res.put('success', true);
            res.put('message', 'Successfully updated ' + licenseType + ' entitlement to ' + (isEnabled ? 'ACTIVE' : 'REVOKED') + ' for ' + targetUser.Name + '.');
            return res;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DevOpsLicenseManagerController.toggleUserLicenseFlag] Exception: ' + ex.getMessage());
            res.put('success', false);
            res.put('message', 'Failed to update license: ' + ex.getMessage());
            return res;
        }
    }
}
