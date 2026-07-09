public with sharing class DemoSObjects {
    public void demoMethod() {
      List<Account> accList = new List<Account>();
      Set<Id> accIds = new Set<Id>();
      accList = [SELECT Id , Name FROM Account LIMIT 2];
      Map<Id, Account> idToAccountMap = new Map<Id, Account>(accList);
    //   accList = [SELECT Id , Name FROM Account LIMIT 2];
        // System.debug('Account List: ' + accList);
        // if (!accList.isEmpty()) {
            for (Account acc : accList) {
                accIds.add(acc.Id);
        //   }
        }
            if (!accIds.isEmpty()) {
               for (Id i : accIds) 
               {
                   if (idToAccountMap.containsKey(i))
                    {
                        System.debug('map vale =>' + idToAccountMap.get(i));
                     }
                     System.debug('i =' + i);
               }
            }
            






















            // SObject obj;
            // obj = new Account(Name = 'test' , Phone = '1234567');
            // // acc.Name= 'raj';
            // // acc.Phone = '123456';
            // Account acc = (Account)obj;
            // System.debug('acc = '+ acc );

            // obj = new House__c( Name = 'test', Address__c = '1234567890');
            // // h.Name = 'test';
            // // h.Address__c = '1234567890';
            // House__c h = (House__c)obj;
            // System.debug('h = '+ h );
    }
}