import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLicenseOverview from '@salesforce/apex/DevOpsLicenseManagerController.getLicenseOverview';
import getDevOpsUsers from '@salesforce/apex/DevOpsLicenseManagerController.getDevOpsUsers';
import toggleUserLicense from '@salesforce/apex/DevOpsLicenseManagerController.toggleUserLicense';

const DEBUG_PREFIX = '[devOpsLicenseManagerConsole]';

export default class DevOpsLicenseManagerConsole extends LightningElement {
    @track isLoading = true;
    @track searchKey = '';
    @track overview = {
        totalAllocatedLicenses: 25,
        usedLicensesCount: 0,
        availableLicensesCount: 25,
        activeUsersCount: 0
    };
    @track userList = [];

    connectedCallback() {
        console.log(`${DEBUG_PREFIX} [connectedCallback] Initializing DevOps License Manager Console...`);
        this.loadOverview();
        this.loadUsers();
    }

    loadOverview() {
        console.log(`${DEBUG_PREFIX} [loadOverview] Loading license allocation overview...`);
        getLicenseOverview()
            .then(res => {
                if (res) {
                    this.overview = res;
                    console.log(`${DEBUG_PREFIX} [loadOverview] SUCCESS - Overview:`, res);
                }
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [loadOverview] Error loading license overview:`, err);
            });
    }

    loadUsers() {
        console.log(`${DEBUG_PREFIX} [loadUsers] Loading users with searchKey:`, this.searchKey);
        this.isLoading = true;
        getDevOpsUsers({ searchKey: this.searchKey })
            .then(users => {
                this.userList = users || [];
                console.log(`${DEBUG_PREFIX} [loadUsers] SUCCESS - Loaded ${this.userList.length} users.`);
                this.isLoading = false;
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [loadUsers] Error loading users:`, err);
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'User Load Error',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.loadUsers();
    }

    handleRefreshAll() {
        this.loadOverview();
        this.loadUsers();
    }

    handleToggleUserLicense(event) {
        const userId = event.target.dataset.id;
        const userName = event.target.dataset.name;
        const isChecked = event.target.checked;

        console.log(`${DEBUG_PREFIX} [handleToggleUserLicense] START - userId:`, userId, 'userName:', userName, 'isChecked:', isChecked);

        toggleUserLicense({
            userId: userId,
            isLicensed: isChecked,
            licenseTier: isChecked ? 'DevOps Admin' : 'Standard Developer'
        })
            .then(res => {
                if (res && res.success) {
                    console.log(`${DEBUG_PREFIX} [handleToggleUserLicense] SUCCESS -`, res.message);
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'License Updated',
                            message: res.message,
                            variant: 'success'
                        })
                    );
                    this.loadOverview();
                } else {
                    console.warn(`${DEBUG_PREFIX} [handleToggleUserLicense] Warning:`, res ? res.message : 'Unknown response');
                    event.target.checked = !isChecked; // revert switch
                }
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [handleToggleUserLicense] Error toggling license:`, err);
                event.target.checked = !isChecked; // revert switch
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'License Update Failed',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }
}
