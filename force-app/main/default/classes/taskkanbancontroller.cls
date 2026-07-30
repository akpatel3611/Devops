public with sharing class TaskKanBanController {
    @AuraEnabled(cacheable=true)
    public static List<Task> getLatestTask(){
        return [
            SELECT Id,Subject, Status, Priority , CreatedDate
            FROM Task
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }
    @AuraEnabled
    public static void updateTask(Id TaskId, String newStatus) {
        Task task = [SELECT Id, Status FROM Task WHERE Id = :TaskId LIMIT 1];
        task.Status = newStatus;
        update task;
    }
    @AuraEnabled(cacheable=true)
public static List<Task> getFilteredTasks(String status, String priority, Date dueDate) {
    String query = 'SELECT Id, Subject, Status, Priority, ActivityDate FROM Task WHERE Id != null';

    if(String.isNotBlank(status)) {
        query += ' AND Status = :status';
    }
    if(String.isNotBlank(priority)) {
        query += ' AND Priority = :priority';
    }
    if(dueDate != null) {
        query += ' AND ActivityDate = :dueDate';
    }

    return Database.query(query);
}


}