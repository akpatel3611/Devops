import { LightningElement, wire, track } from 'lwc';
import getLatestTask from '@salesforce/apex/TaskKanBanController.getLatestTask';
import updateTask from '@salesforce/apex/TaskKanBanController.updateTask';
import getFilteredTasks from '@salesforce/apex/TaskKanBanController.getFilteredTasks';
import { refreshApex } from '@salesforce/apex';

export default class TaskStatusChangerDrager extends LightningElement {
    @track task = [];
    wiredResult;

    // Filters
    statusFilter = '';
    priorityFilter = '';
    dueDate = null;

    // Picklist options
    statusOptions = [
        { label: 'All', value: '' },
        { label: 'Not Started', value: 'Not Started' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'Deferred', value: 'Deferred' },
        { label: 'Completed', value: 'Completed'}
    ];

    priorityOptions = [
        { label: 'All', value: '' },
        { label: 'High', value: 'High' },
        { label: 'Normal', value: 'Normal' },
        { label: 'Low', value: 'Low' }
    ];

    Status = [
        { name: 'All', label: 'Task Record' },
        { name: 'Not Started', label: 'Not Started' },
        { name: 'In Progress', label: 'In Progress' },
        { name: 'Deferred', label: 'Deferred' },
        { name: 'Completed', label: 'Completed' }
    ];

    @wire(getLatestTask)
    wiredOpps(result) {
        this.wiredResult = result;
        if (result.data) {
            this.task = result.data.filter(r => r.Subject && r.Status);
        } else if (result.error) {
            console.error('Error fetching tasks:', result.error);
        }
    }

    get column() {
        return this.Status.map(s => {
            let records = [];
            if (s.name === 'All') {
                records = this.task || [];
            } else {
                records = (this.task || []).filter(r => r.Status === s.name);
            }
            return { ...s, records };
        });
    }

    // Drag & Drop
    handleDrag(event) {
        const taskId = event.currentTarget.dataset.id;
        if (taskId) {
            event.dataTransfer.setData('TaskId', taskId);
        }
    }

    allowDrop(event) {
        event.preventDefault();
    }

    async handleDrop(event) {
        event.preventDefault();
        const TaskId = event.dataTransfer.getData('TaskId');
        const newStatus = event.currentTarget.dataset.stage;

        if (newStatus && TaskId && newStatus !== 'All') {
            try {
                await updateTask({ TaskId, newStatus });
                if (this.statusFilter || this.priorityFilter || this.dueDate)
                {
                    this.applyFilters();
                } 
                else 
                {
                await refreshApex(this.wiredResult);
                }
            } catch (error) {
                console.error('Error updating task:', error);
            }
        }
    }

    // Filter Handlers
    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
        this.applyFilters();
    }

    handlePriorityChange(event) {
        this.priorityFilter = event.detail.value;
        this.applyFilters();
    }

    handleDateChange(event) {
        this.dueDate = event.target.value;
        this.applyFilters();
    }

    applyFilters() {
        getFilteredTasks({
            status: this.statusFilter,
            priority: this.priorityFilter,
            dueDate: this.dueDate
        })
        .then(result => {
            this.task = result;
        })
        .catch(error => {
            console.error(error);
        });
    }
}