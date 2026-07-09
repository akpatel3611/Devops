@IsTest
private class DeploymentValidationServiceTest {

    @IsTest
    static void testGetMessage() {

        Test.startTest();

        String result =
            DeploymentValidationService.getMessage();

        Test.stopTest();

        System.assertEquals(
            'Deployment Success',
            result
        );
    }
}