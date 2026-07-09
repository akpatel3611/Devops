global class BatchClassPractise implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, WhatId, Subject, CreatedDate, CreatedBy.Profile.Name, 
                   Status, CallDurationInSeconds, ActivityDate, CompletedDateTime
            FROM Task
            WHERE WhatId != null
            AND What.Type = 'Account'
            AND Status = 'Completed'
            AND CreatedBy.Profile.Name != 'System Administrator'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Task> taskList) {
        Map<Id, Account> accToUpdateMap = new Map<Id, Account>();

        for(Task t : taskList) {
            // Only process if CompletedDateTime == CreatedDate (already filtered in query)
            if (t.CompletedDateTime!= t.CreatedDate) {
                System.debug('Skipped: cmpleteDateTime!= createdDate');
                continue;
            }
            if(String.isNotBlank(t.Subject) && t.Subject.containsIgnoreCase('Email')) {
                // Email Activity: update only Last_Sales_Activity__c
                if(t.WhatId != null) {
                    if(!accToUpdateMap.containsKey(t.WhatId)) {
                        accToUpdateMap.put(t.WhatId, new Account(
                            Id = t.WhatId,
                            Last_Sales_Activity__c = t.CreatedDate
                        ));
                    } else {
                        accToUpdateMap.get(t.WhatId).Last_Sales_Activity__c = t.CreatedDate;
                    }
                }
            }
            else if(t.CallDurationInSeconds != null) {
                // Call Activity: update both Last_Call__c and Last_Sales_Activity__c
                if(t.WhatId != null) {
                    if(!accToUpdateMap.containsKey(t.WhatId)) {
                        accToUpdateMap.put(t.WhatId, new Account(
                            Id = t.WhatId,
                            Last_Call__c = t.CreatedDate,
                            Last_Sales_Activity__c = t.CreatedDate
                        ));
                    } else {
                        Account acc = accToUpdateMap.get(t.WhatId);
                        acc.Last_Call__c = t.CreatedDate;
                        acc.Last_Sales_Activity__c = t.CreatedDate;
                    }
                }
            }
        }

        if(!accToUpdateMap.isEmpty()) {
            update accToUpdateMap.values();
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch Job Finished Successfully');
    }
}