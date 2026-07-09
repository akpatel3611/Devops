global class BatchApexPractise implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, WhatId, Subject, CreatedDate, CreatedBy.Profile.Name, 
                   Status, CallDurationInSeconds, CompletedDateTime 
            FROM Task
            WHERE WhatId != null
            AND What.Type = 'Account'
            AND Status = 'Completed'
            AND CreatedBy.Profile.Name !='System Administrator'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Task> taskList) {
        Map<Id, Account> accToUpdateMap = new Map<Id, Account>();

        for(Task t : taskList) {
    // Step 2: Skip tasks if comletedDateTime != CreatedDate
    if (t.CompletedDateTime != t.CreatedDate) {
        System.debug('Skipping Task because CompletedDateTime != CreatedDate :' + t.Id);
        continue;
    }
    
    if (!String.isEmpty(t.Subject) && t.Subject.contains('Email')) {
        System.debug('Email activity found. Task Id: ' + t.Id);
        if (t.WhatId != null) {
            if (!accToUpdateMap.containsKey(t.WhatId)) {
                accToUpdateMap.put(t.WhatId, new Account(
                    Id = t.WhatId,
                    Last_Sales_Activity__c = t.CreatedDate 
                ));
            } else {
                System.debug('Updated Email Activity for Account Id: ');
                accToUpdateMap.get(t.WhatId).Last_Sales_Activity__c = t.CreatedDate;
                
            }
        }
    }
    else if (t.CallDurationInSeconds != null) {
        System.debug('Call activity found. Task Id:');
        if (t.WhatId != null) {
            if (!accToUpdateMap.containsKey(t.WhatId)) {
                accToUpdateMap.put(t.WhatId, new Account(
                    Id = t.WhatId,
                    Last_Call__c = t.CreatedDate,
                    Last_Sales_Activity__c = t.CreatedDate
                ));
                System.debug('Created Call Activity for Account Id: ');
            } else {
                System.debug('Updated Call Activity for Account Id: ');
                Account acc = accToUpdateMap.get(t.WhatId);
                acc.Last_Call__c = t.CreatedDate;
                acc.Last_Sales_Activity__c = t.CreatedDate;
                acc.Last_Sales_Activity__c = System.now();
                
            }
        }
    }
}

        // Step 5: Final update
        if(!accToUpdateMap.isEmpty()) {
            update accToUpdateMap.values();
        } else {
            System.debug('No Accounts to update');
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch Job Finished Successfully');
    }
}