public with sharing class OpportunityController {
    
    @AuraEnabled
    public static String saveOpportunityRecord(String opportunityData) {
        try {
            // Input validation
            if (String.isBlank(opportunityData)) {
                throw new AuraHandledException('Opportunity data is required');
            }
            
            // Parse the JSON data
            Map<String, Object> oppData;
            try {
                oppData = (Map<String, Object>) JSON.deserializeUntyped(opportunityData);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid JSON format: ' + e.getMessage());
            }
            
            // Validate required fields
            if (!oppData.containsKey('Name') || String.isBlank((String) oppData.get('Name'))) {
                throw new AuraHandledException('Opportunity Name is required');
            }
            
            if (!oppData.containsKey('CloseDate') || String.isBlank((String) oppData.get('CloseDate'))) {
                throw new AuraHandledException('Close Date is required');
            }
            
            if (!oppData.containsKey('StageName') || String.isBlank((String) oppData.get('StageName'))) {
                throw new AuraHandledException('Stage Name is required');
            }
            
            // Create new Opportunity record
            Opportunity newOpp = new Opportunity();
            newOpp.Name = (String) oppData.get('Name');
            
            // Handle Amount field with simplified type casting
            Object amountObj = oppData.get('Amount');
            if (amountObj != null) {
                try {
                    newOpp.Amount = Decimal.valueOf(String.valueOf(amountObj));
                } catch (Exception e) {
                    // If amount is invalid, set to 0
                    newOpp.Amount = 0;
                }
            }
            
            // Handle Close Date with validation
            try {
                newOpp.CloseDate = Date.valueOf((String) oppData.get('CloseDate'));
            } catch (Exception e) {
                throw new AuraHandledException('Invalid Close Date format. Please use YYYY-MM-DD');
            }
            
            newOpp.StageName = (String) oppData.get('StageName');
            newOpp.Type = (String) oppData.get('Type');
            
            // Insert the record
            insert newOpp;
            
            return newOpp.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating opportunity: ' + e.getMessage());
        }
    }
}