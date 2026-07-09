@isTest
public class OppProcessorTest {
  @isTest
    private static void TestBatchClass(){
       List<Opportunity> oppList= new List<Opportunity>();
        for(Integer i=0; i<200 ; i++){
            oppList.add(new Opportunity (Name ='Test'+ i, StageName = 'Prospecting', CloseDate=System.today()));
        }
        insert oppList;
        Test.StartTest();
        oppProcessor oppProcess = new oppProcessor();
        Id batchId= Database.executeBatch(oppProcess, 200);
        Test.stopTest();
    }
}