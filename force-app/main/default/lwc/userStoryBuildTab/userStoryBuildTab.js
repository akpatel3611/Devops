import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CURRENT_USER_ID from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import getSelectedMetadata from '@salesforce/apex/UserStoryWorkspaceController.getSelectedMetadata';
import getBuildTabGitDetails from '@salesforce/apex/UserStoryWorkspaceController.getBuildTabGitDetails';

const DEBUG_PREFIX = '[userStoryBuildTab]';

export default class UserStoryBuildTab extends LightningElement {
    @api recordId;

    @track gitBranchName = '';
    @track gitBranchUrl = '';

    @track userName = 'Ankit Patel';

    @wire(getRecord, { recordId: CURRENT_USER_ID, fields: [USER_NAME_FIELD] })
    wiredUser({ error, data }) {
        if (data) {
            this.userName = getFieldValue(data, USER_NAME_FIELD);
            if (this.rawMetadata && this.rawMetadata.length > 0) {
                const currentUserId15 = CURRENT_USER_ID ? CURRENT_USER_ID.substring(0, 15) : '';
                const currentUserId18 = CURRENT_USER_ID || '';
                this.rawMetadata = this.rawMetadata.map(item => {
                    let lmName = item.lastModifiedBy;
                    if (lmName === currentUserId15 || lmName === currentUserId18 || lmName === 'Ankit Patel') {
                        lmName = this.userName;
                    }
                    let cbName = item.createdBy;
                    if (cbName === currentUserId15 || cbName === currentUserId18 || cbName === 'Ankit Patel') {
                        cbName = this.userName;
                    }
                    return {
                        ...item,
                        lastModifiedBy: lmName,
                        createdBy: cbName
                    };
                });
                this.buildFilterOptions();
                this.applyFilters();
            }
        }
    }

    @wire(getBuildTabGitDetails, { userStoryId: '$recordId' })
    wiredGitDetails({ error, data }) {
        if (data) {
            this.gitBranchName = data.gitBranchName || '';
            this.gitBranchUrl = data.gitBranchUrl || '';
        } else if (error) {
            console.error(`${DEBUG_PREFIX} Error fetching git branch details`, error);
        }
    }

    // ── Raw & filtered data ──────────────────────────────────────────────────
    @track rawMetadata = [];
    @track filteredMetadata = [];
    @track isLoading = true;

    // ── Section state ────────────────────────────────────────────────────────
    @track isSelectionExpanded = true;

    // ── Pagination ───────────────────────────────────────────────────────────
    @track currentPage = 1;
    @track rowsPerPage = 50;

    // ── Deployment tasks ─────────────────────────────────────────────────────
    @track deploymentTasksCount = 0;
    @track tasksList = [];

    // ── Filters ──────────────────────────────────────────────────────────────
    @track filterName = '';
    @track filterType = '';
    @track filterUser = '';
    @track filterLastModifiedDate = '';
    @track filterCreatedBy = '';
    @track filterCreatedDate = '';

    // ── Combobox option arrays (include default blank option) ─────────────────
    @track typeOptions = [{ label: '-- Select Filter --', value: '' }];
    @track userOptions = [{ label: '-- Select Filter --', value: '' }];
    @track createdByOptions = [{ label: '-- Select Filter --', value: '' }];

    wiredMetadataResult;

    // ── Wire ─────────────────────────────────────────────────────────────────
    @wire(getSelectedMetadata, { userStoryId: '$recordId' })
    wiredMetadata(result) {
        this.wiredMetadataResult = result;
        this.isLoading = true;
        console.debug(`${DEBUG_PREFIX} getSelectedMetadata wire response`, {
            recordId: this.recordId,
            hasData: !!result.data,
            hasError: !!result.error
        });
        if (result.data) {
            const currentUserId15 = CURRENT_USER_ID ? CURRENT_USER_ID.substring(0, 15) : '';
            const currentUserId18 = CURRENT_USER_ID || '';
            this.rawMetadata = result.data.map(item => {
                const action = item.Action__c;
                
                let lmName = item.LastModifiedById || 'Ankit Patel';
                if (lmName === currentUserId15 || lmName === currentUserId18) {
                    lmName = this.userName || 'Ankit Patel';
                } else if (lmName.startsWith('005')) {
                    lmName = 'Ankit Patel';
                }

                let cbName = item.CreatedById || 'Ankit Patel';
                if (cbName === currentUserId15 || cbName === currentUserId18) {
                    cbName = this.userName || 'Ankit Patel';
                } else if (cbName.startsWith('005')) {
                    cbName = 'Ankit Patel';
                }

                return {
                    ...item,
                    selected: item.Selected__c,
                    gitUpsert: action === 'Add' || action === 'Commit Files',
                    gitDeletion: action === 'Delete' || action === 'Destructive Changes',
                    testOnly: action === 'Test Only',
                    retrieveOnly: action === 'Retrieve Only',
                    lastModifiedBy: lmName,
                    lastModifiedDate: item.LastModifiedDate ? item.LastModifiedDate.split('T')[0] : '',
                    createdBy: cbName,
                    createdDate: item.CreatedDate ? item.CreatedDate.split('T')[0] : ''
                };
            });
            this.buildFilterOptions();
            this.applyFilters();
            console.debug(`${DEBUG_PREFIX} build metadata loaded`, {
                recordId: this.recordId,
                rawCount: this.rawMetadata.length,
                filteredCount: this.filteredMetadata.length,
                metadataTypes: this.metadataTypesInSelection
            });
            this.isLoading = false;
        } else if (result.error) {
            console.error(`${DEBUG_PREFIX} Error loading build metadata`, this.normalizeError(result.error), result.error);
            this.isLoading = false;
        }
    }

    // ── Computed: User Story Selection section ───────────────────────────────
    get metadataTypesInSelection() {
        if (!this.rawMetadata || this.rawMetadata.length === 0) return '';
        const types = new Set(
            this.rawMetadata
                .filter(item => item.Metadata_Type__c)
                .map(item => item.Metadata_Type__c)
        );
        return Array.from(types).join(';');
    }

    get chevronClass() {
        return this.isSelectionExpanded ? 'chevron chevron-down' : 'chevron chevron-right';
    }

    // ── Computed: Table data ─────────────────────────────────────────────────
    get hasMetadata() {
        return this.filteredMetadata && this.filteredMetadata.length > 0;
    }

    get paginatedMetadata() {
        const start = (this.currentPage - 1) * this.rowsPerPage;
        const end = start + this.rowsPerPage;
        return this.filteredMetadata.slice(start, end);
    }

    // ── Computed: Filter options (strip default blank from iteration) ─────────
    get typeOptionsFiltered() {
        return this.typeOptions.filter(o => o.value !== '');
    }

    get userOptionsFiltered() {
        return this.userOptions.filter(o => o.value !== '');
    }

    get createdByOptionsFiltered() {
        return this.createdByOptions.filter(o => o.value !== '');
    }

    // ── Computed: Pagination ─────────────────────────────────────────────────
    get totalPages() {
        const total = this.filteredMetadata.length;
        if (total === 0) return 1;
        return Math.ceil(total / this.rowsPerPage);
    }

    get paginationLabel() {
        const total = this.filteredMetadata.length;
        if (total === 0) return '0-0 of 0';
        const start = (this.currentPage - 1) * this.rowsPerPage + 1;
        const end = Math.min(this.currentPage * this.rowsPerPage, total);
        return `${start}-${end} of ${total}`;
    }

    get rowsPerPageOptions() {
        const options = [
            { label: '10', value: '10' },
            { label: '25', value: '25' },
            { label: '50', value: '50' },
            { label: '100', value: '100' }
        ];
        return options.map(o => ({
            ...o,
            selected: parseInt(o.value, 10) === this.rowsPerPage
        }));
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    // ── Computed: Deployment Tasks ───────────────────────────────────────────
    get deploymentTasksTitle() {
        return `Deployment Tasks (${this.deploymentTasksCount})`;
    }

    get hasTasks() {
        return this.tasksList && this.tasksList.length > 0;
    }

    // ── Filter option builder ────────────────────────────────────────────────
    buildFilterOptions() {
        const types = new Set();
        const users = new Set();
        const createdBys = new Set();

        this.rawMetadata.forEach(item => {
            if (item.Metadata_Type__c) types.add(item.Metadata_Type__c);
            if (item.lastModifiedBy) users.add(item.lastModifiedBy);
            if (item.createdBy) createdBys.add(item.createdBy);
        });

        this.typeOptions = [
            { label: '-- Select Filter --', value: '' },
            ...Array.from(types).map(t => ({ label: t, value: t }))
        ];
        this.userOptions = [
            { label: '-- Select Filter --', value: '' },
            ...Array.from(users).map(u => ({ label: u, value: u }))
        ];
        this.createdByOptions = [
            { label: '-- Select Filter --', value: '' },
            ...Array.from(createdBys).map(c => ({ label: c, value: c }))
        ];
    }

    // ── Filter handler ───────────────────────────────────────────────────────
    handleFilterChange(event) {
        const name = event.target.name;
        this[name] = event.target.value;
        this.currentPage = 1;
        this.applyFilters();
    }

    applyFilters() {
        let list = this.rawMetadata;

        if (this.filterName) {
            const search = this.filterName.toLowerCase();
            list = list.filter(item =>
                item.Metadata_API_Name__c &&
                item.Metadata_API_Name__c.toLowerCase().includes(search)
            );
        }
        if (this.filterType) {
            list = list.filter(item => item.Metadata_Type__c === this.filterType);
        }
        if (this.filterUser) {
            list = list.filter(item => item.lastModifiedBy === this.filterUser);
        }
        if (this.filterLastModifiedDate) {
            list = list.filter(item => item.lastModifiedDate === this.filterLastModifiedDate);
        }
        if (this.filterCreatedBy) {
            list = list.filter(item => item.createdBy === this.filterCreatedBy);
        }
        if (this.filterCreatedDate) {
            list = list.filter(item => item.createdDate === this.filterCreatedDate);
        }

        this.filteredMetadata = list;
    }

    // ── Refresh / Test Classes ───────────────────────────────────────────────
    handleRefresh() {
        this.isLoading = true;
        console.debug(`${DEBUG_PREFIX} refresh requested`, { recordId: this.recordId });
        refreshApex(this.wiredMetadataResult)
            .then(() => {
                console.debug(`${DEBUG_PREFIX} refresh completed`, { recordId: this.recordId });
                this.isLoading = false;
            })
            .catch(error => {
                console.error(`${DEBUG_PREFIX} refresh failed`, this.normalizeError(error), error);
                this.isLoading = false;
            });
    }

    handleAddTestClasses() {
        // Implement test class addition logic
    }

    // ── Collapsible toggle ───────────────────────────────────────────────────
    handleToggleSelection() {
        this.isSelectionExpanded = !this.isSelectionExpanded;
    }

    // ── Pagination handlers ──────────────────────────────────────────────────
    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage -= 1;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage += 1;
        }
    }

    handleRowsPerPageChange(event) {
        this.rowsPerPage = parseInt(event.target.value, 10);
        this.currentPage = 1;
    }

    handlePageInput(event) {
        const val = parseInt(event.target.value, 10);
        if (!isNaN(val) && val >= 1 && val <= this.totalPages) {
            this.currentPage = val;
        }
    }

    // ── New Deployment Task ──────────────────────────────────────────────────
    handleNewTask() {
        const newTask = {
            Id: String(this.tasksList.length + 1),
            name: 'New Deployment Task',
            type: 'Manual Task',
            status: 'Pending'
        };
        this.tasksList = [...this.tasksList, newTask];
        this.deploymentTasksCount = this.tasksList.length;
        console.debug(`${DEBUG_PREFIX} local deployment task added`, {
            recordId: this.recordId,
            deploymentTasksCount: this.deploymentTasksCount
        });
    }

    normalizeError(error) {
        return {
            message: error?.body?.message || error?.message || 'Unknown error',
            status: error?.status,
            statusText: error?.statusText,
            errorType: error?.body?.errorType || error?.errorType
        };
    }
}