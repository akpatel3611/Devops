public with sharing class DeploymentValidationService {

    @AuraEnabled
    public static String getMessage() {
        System.debug(LoggingLevel.INFO, '[DeploymentValidationService.getMessage] START');
        try {
            String msg = 'Deployment Success';
            System.debug(LoggingLevel.INFO, '[DeploymentValidationService.getMessage] SUCCESS - Message: ' + msg);
            return msg;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[DeploymentValidationService.getMessage] Exception: ' + ex.getMessage());
            throw new AuraHandledException(ex.getMessage());
        }
    }
}