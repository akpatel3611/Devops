public with sharing class DeploymentValidationService {

    @AuraEnabled
    public static String getMessage() {
        System.debug('DeploymentValidationService.getMessage called');
        return 'Deployment Success';
    }
}