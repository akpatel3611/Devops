public with sharing class AsyncProcessFlowInvoker {

    /*
    =========================================
    FLOW INPUT CLASS
    =========================================
    */

    public class FlowInput {

        @InvocableVariable(required=true)
        public Id recordId;
    }

    /*
    =========================================
    FLOW INVOCABLE METHOD
    =========================================
    */

    @InvocableMethod(
        label='Start Async Process'
        description='Starts Async Background Process'
    )

    public static void startAsyncProcess(

        List<FlowInput> inputList
    ) {

        for (FlowInput input : inputList) {

            if (input.recordId != null) {

                System.enqueueJob(

                    new AsyncProcessQueueable(
                        input.recordId
                    )
                );
            }
        }
    }
}