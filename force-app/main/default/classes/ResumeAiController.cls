public with sharing class ResumeAiController {
    
    @AuraEnabled
    public static Id processResumeFile(Id contentVersionId, String masterPrompt) {
        try {
            // Harmless comment to trigger git difference for end-to-end testing
            // 1. Upload ki hui file ka version data (blob) nikalna
            ContentVersion cv = [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            
            // 2. File ko Base64 String me convert karna taaki API ke through bhej sakein
            String base64Data = EncodingUtil.base64Encode(cv.VersionData);
            
            // 3. HTTP Request tayar karna
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            // AAPKA NGROK URL YAHAN HAI (Sath me /process-resume endpoint)
            request.setEndpoint('https://sulphonic-vicki-unsignificantly.ngrok-free.dev/process-resume'); 
            
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(120000); // AI processing me time lagta hai, isliye 2 min ka timeout
            
            // 4. JSON Body banana jisme File aur Prompt dono honge
            Map<String, String> bodyMap = new Map<String, String>();
            bodyMap.put('base64_file', base64Data);
            bodyMap.put('master_prompt', masterPrompt);
            request.setBody(JSON.serialize(bodyMap));
            
            // 5. Python API ko hit karna
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                // 6. Python se wapas aayi modified Base64 file ko nikalna
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String modifiedBase64 = (String) respMap.get('modified_base64');
                
                // 7. Nayi file banakar Salesforce Files me save karna
                ContentVersion newCv = new ContentVersion();
                newCv.Title = cv.Title + ' - Updated by AI';
                newCv.PathOnClient = cv.Title + '_Updated.' + cv.FileExtension;
                newCv.VersionData = EncodingUtil.base64Decode(modifiedBase64); // Wapas Blob me convert
                insert newCv;
                
                return newCv.Id; // LWC ko nayi file ki ID de rahe hain
            } else {
                throw new AuraHandledException('Python Server Error: ' + response.getBody());
            }
        } catch(Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
public with sharing class ResumeAiController {
    
    @AuraEnabled
    public static Id processResumeFile(Id contentVersionId, String masterPrompt) {
        try {
            // Harmless comment to trigger git difference for end-to-end testing
            // 1. Upload ki hui file ka version data (blob) nikalna
            ContentVersion cv = [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1];
            
            // 2. File ko Base64 String me convert karna taaki API ke through bhej sakein
            String base64Data = EncodingUtil.base64Encode(cv.VersionData);
            
            // 3. HTTP Request tayar karna
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            // AAPKA NGROK URL YAHAN HAI (Sath me /process-resume endpoint)
            request.setEndpoint('https://sulphonic-vicki-unsignificantly.ngrok-free.dev/process-resume'); 
            
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(120000); // AI processing me time lagta hai, isliye 2 min ka timeout
            
            // 4. JSON Body banana jisme File aur Prompt dono honge
            Map<String, String> bodyMap = new Map<String, String>();
            bodyMap.put('base64_file', base64Data);
            bodyMap.put('master_prompt', masterPrompt);
            request.setBody(JSON.serialize(bodyMap));
            
            // 5. Python API ko hit karna
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                // 6. Python se wapas aayi modified Base64 file ko nikalna
                Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String modifiedBase64 = (String) respMap.get('modified_base64');
                
                // 7. Nayi file banakar Salesforce Files me save karna
                ContentVersion newCv = new ContentVersion();
                newCv.Title = cv.Title + ' - Updated by AI';
                newCv.PathOnClient = cv.Title + '_Updated.' + cv.FileExtension;
                newCv.VersionData = EncodingUtil.base64Decode(modifiedBase64); // Wapas Blob me convert
                insert newCv;
                
                return newCv.Id; // LWC ko nayi file ki ID de rahe hain
            } else {
                throw new AuraHandledException('Python Server Error: ' + response.getBody());
            }
        } catch(Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}