public with sharing class EnvironmentController {

    public class EnvironmentOption {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public EnvironmentOption(String label,String value){
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<EnvironmentOption> getEnvironments(){

        List<EnvironmentOption> options = new List<EnvironmentOption>();

        List<Deployment_Environment__c> envList = [
            SELECT Id,
                   Name,
                   Environment_Type__c,
                   Status__c
            FROM Deployment_Environment__c
            WHERE Status__c = 'Active'
            ORDER BY Name
        ];

        for(Deployment_Environment__c env : envList){

            options.add(
                new EnvironmentOption(
                    env.Name,
                    env.Id
                )
            );
        }

        return options;
    }
}