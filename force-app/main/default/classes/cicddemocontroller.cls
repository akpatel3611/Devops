public with sharing class cicddemocontroller {
    @auraEnabled(cacheable=false)
    public static void CICDDemoController() {
            System.debug('cicddemocontroller constructor called');
    }
}