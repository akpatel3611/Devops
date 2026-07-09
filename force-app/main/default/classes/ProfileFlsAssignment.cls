public class ProfileFlsAssignment {
    @AuraEnabled public String profileMetadataName { get; set; }
    @AuraEnabled public String profileLabel { get; set; }
    @AuraEnabled public Boolean readAll { get; set; }
    @AuraEnabled public Boolean editAll { get; set; }
}