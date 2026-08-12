public with sharing class cicddemocontroller {
    @auraEnabled(cacheable=false)
    public static void CICDDemoController() {
            System.debug('cicddemocontroller constructor called');
            system.debug('deployment testing');
            System.debug('UserStory2_Dev_Conflicting_Code_Line6 test 1');
            System.debug('Merge Conflict check 1');
    }
}