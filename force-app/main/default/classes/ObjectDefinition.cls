public class ObjectDefinition {
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String pluralLabel { get; set; }
    @AuraEnabled public String apiName { get; set; }
    @AuraEnabled public String nameFieldLabel { get; set; }
    @AuraEnabled public String nameFieldType { get; set; } // Text or AutoNumber
    @AuraEnabled public String theme { get; set; } // Motif string e.g. "Custom67: Gear"
}