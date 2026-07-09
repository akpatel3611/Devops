public with sharing class DeploymentValidationController {

    public class ValidationResult {

        @AuraEnabled
        public String checkName;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String message;

        public ValidationResult(
            String checkName,
            String status,
            String message
        ){
            this.checkName = checkName;
            this.status = status;
            this.message = message;
        }
    }

    @AuraEnabled
    public static List<ValidationResult> validateDeployment(

        Id sourceEnvironmentId,
        Id targetEnvironmentId,
        String metadataType,
        List<String> componentNames
    ){

        List<ValidationResult> results =
            new List<ValidationResult>();

        if(sourceEnvironmentId == null){

            results.add(
                new ValidationResult(
                    'Source Environment',
                    'FAIL',
                    'Source Environment not selected'
                )
            );

            return results;
        }

        results.add(
            new ValidationResult(
                'Source Environment',
                'PASS',
                'Selected'
            )
        );

        if(targetEnvironmentId == null){

            results.add(
                new ValidationResult(
                    'Target Environment',
                    'FAIL',
                    'Target Environment not selected'
                )
            );

            return results;
        }

        results.add(
            new ValidationResult(
                'Target Environment',
                'PASS',
                'Selected'
            )
        );

        if(sourceEnvironmentId == targetEnvironmentId){

            results.add(
                new ValidationResult(
                    'Environment Validation',
                    'FAIL',
                    'Source and Target cannot be same'
                )
            );

            return results;
        }

        results.add(
            new ValidationResult(
                'Environment Validation',
                'PASS',
                'Different Environments'
            )
        );

        if(String.isBlank(metadataType)){

            results.add(
                new ValidationResult(
                    'Metadata Type',
                    'FAIL',
                    'Metadata Type not selected'
                )
            );

            return results;
        }

        results.add(
            new ValidationResult(
                'Metadata Type',
                'PASS',
                metadataType
            )
        );

        if(
            componentNames == null ||
            componentNames.isEmpty()
        ){

            results.add(
                new ValidationResult(
                    'Metadata Selection',
                    'FAIL',
                    'No Metadata Selected'
                )
            );

            return results;
        }

        results.add(
            new ValidationResult(
                'Metadata Selection',
                'PASS',
                String.valueOf(
                    componentNames.size()
                ) + ' Components Selected'
            )
        );

        try{

            DeploymentCredentialController.CredentialWrapper sourceCredential =

                DeploymentCredentialController.getCredentialByEnvironment(
                    sourceEnvironmentId
                );

            results.add(
                new ValidationResult(
                    'Source Credential',
                    'PASS',
                    sourceCredential.credentialName
                )
            );

            DeploymentCredentialController.CredentialWrapper targetCredential =

                DeploymentCredentialController.getCredentialByEnvironment(
                    targetEnvironmentId
                );

            results.add(
                new ValidationResult(
                    'Target Credential',
                    'PASS',
                    targetCredential.credentialName
                )
            );

            MetadataAuthenticationService.generateAccessToken(
                sourceCredential.credentialId
            );

            results.add(
                new ValidationResult(
                    'Source OAuth',
                    'PASS',
                    'Token Generated'
                )
            );

            MetadataAuthenticationService.generateAccessToken(
                targetCredential.credentialId
            );

            results.add(
                new ValidationResult(
                    'Target OAuth',
                    'PASS',
                    'Token Generated'
                )
            );
        }
        catch(Exception ex){

            results.add(
                new ValidationResult(
                    'OAuth Validation',
                    'FAIL',
                    ex.getMessage()
                )
            );
        }

        return results;
    }
}