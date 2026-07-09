public class FieldDefinition {
    @AuraEnabled public String rowKey { get; set; }
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String apiName { get; set; }
    @AuraEnabled public String dataType { get; set; }
    @AuraEnabled public Integer length { get; set; }
    @AuraEnabled public Boolean isRequired { get; set; }
    @AuraEnabled public String relatedObject { get; set; }
    @AuraEnabled public String displayFormat { get; set; }
    @AuraEnabled public Integer startingNumber { get; set; }
    @AuraEnabled public String formula { get; set; }
    @AuraEnabled public String formulaType { get; set; }
    @AuraEnabled public String picklistValues { get; set; }
    @AuraEnabled public Integer visibleLines { get; set; }
    @AuraEnabled public Integer scale { get; set; }
}