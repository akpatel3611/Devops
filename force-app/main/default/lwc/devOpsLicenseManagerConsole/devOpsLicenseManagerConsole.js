import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLicenseOverview from '@salesforce/apex/DevOpsLicenseManagerController.getLicenseOverview';
import getDevOpsUsers from '@salesforce/apex/DevOpsLicenseManagerController.getDevOpsUsers';
import toggleUserLicenseFlag from '@salesforce/apex/DevOpsLicenseManagerController.toggleUserLicenseFlag';

const DEBUG_PREFIX = '[devOpsLicenseManagerConsole]';

export default class DevOpsLicenseManagerConsole extends LightningElement {
    @track isLoading = true;
    @track searchKey = '';
    @track overview = {
        totalAdminLicenses: 5,
        usedAdminLicenses: 0,
        availableAdminLicenses: 5,
        totalDeveloperLicenses: 15,
        usedDeveloperLicenses: 0,
        availableDeveloperLicenses: 15,
        totalReleaseManagerLicenses: 5,
        usedReleaseManagerLicenses: 0,
        availableReleaseManagerLicenses: 5,
        activeOrgUsersCount: 0
    };
    @track userList = [];

    connectedCallback() {
        console.log(`${DEBUG_PREFIX} [connectedCallback] Initializing Copado-style License Manager Console...`);
        this.loadOverview();
        this.loadUsers();
    }

    loadOverview() {
        getLicenseOverview()
            .then(res => {
                if (res) {
                    this.overview = res;
                    console.log(`${DEBUG_PREFIX} [loadOverview] SUCCESS - Overview:`, res);
                }
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [loadOverview] Error loading overview:`, err);
            });
    }

    loadUsers() {
        this.isLoading = true;
        getDevOpsUsers({ searchKey: this.searchKey })
            .then(users => {
                this.userList = users || [];
                console.log(`${DEBUG_PREFIX} [loadUsers] Loaded ${this.userList.length} user entitlements.`);
                this.isLoading = false;
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [loadUsers] Error loading users:`, err);
                this.isLoading = false;
            });
    }

    get adminProgressStyle() {
        const pct = this.overview.totalAdminLicenses > 0 
            ? Math.round((this.overview.usedAdminLicenses / this.overview.totalAdminLicenses) * 100)
            : 0;
        return `width: ${Math.min(100, pct)}%;`;
    }

    get devProgressStyle() {
        const pct = this.overview.totalDeveloperLicenses > 0 
            ? Math.round((this.overview.usedDeveloperLicenses / this.overview.totalDeveloperLicenses) * 100)
            : 0;
        return `width: ${Math.min(100, pct)}%;`;
    }

    get rmProgressStyle() {
        const pct = this.overview.totalReleaseManagerLicenses > 0 
            ? Math.round((this.overview.usedReleaseManagerLicenses / this.overview.totalReleaseManagerLicenses) * 100)
            : 0;
        return `width: ${Math.min(100, pct)}%;`;
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.loadUsers();
    }

    handleRefreshAll() {
        this.loadOverview();
        this.loadUsers();
    }

    handleCheckboxToggle(event) {
        const userId = event.target.dataset.id;
        const type = event.target.dataset.type;
        const isChecked = event.target.checked;

        console.log(`${DEBUG_PREFIX} [handleCheckboxToggle] userId:`, userId, 'type:', type, 'isChecked:', isChecked);

        toggleUserLicenseFlag({
            userId: userId,
            licenseType: type,
            isEnabled: isChecked
        })
            .then(res => {
                if (res && res.success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Entitlement Updated',
                            message: res.message,
                            variant: 'success'
                        })
                    );
                    this.loadOverview();
                } else {
                    event.target.checked = !isChecked;
                }
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [handleCheckboxToggle] Error:`, err);
                event.target.checked = !isChecked;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Update Error',
                        message: err.body ? err.body.message : err.message,
                        variant: 'error'
                    })
                );
            });
    }
}
