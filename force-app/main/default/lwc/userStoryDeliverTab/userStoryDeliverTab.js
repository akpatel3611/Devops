import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPromotions from '@salesforce/apex/UserStoryWorkspaceController.getPromotions';
import getPromotionActionContext from '@salesforce/apex/UserStoryWorkspaceController.getPromotionActionContext';

const DEBUG_PREFIX = '[userStoryDeliverTab]';
const POLLING_INTERVAL_MS = 3000;
const MAX_POLLING_DURATION_MS = 300000;

export default class UserStoryDeliverTab extends NavigationMixin(LightningElement) {
    @api recordId;
    @track showPushingSpinner = false;
    @track _promotions = [];
    @track isPromoteAvailable = false;
    @track currentEnvName = '';
    @track targetEnvName = '';
    @track promoteButtonLabel = 'Deploy to Next Stage';
    @track isAtUatStaging = false;
    @track showPromoteModal = false;

    _wiredPromotionsResult;
    _pollingInterval;
    _pollingStartedAt;

    @wire(getPromotionActionContext, { userStoryId: '$recordId' })
    wiredActionContext({ error, data }) {
        console.log(`${DEBUG_PREFIX} [wiredActionContext] recordId: ${this.recordId}`);
        if (data) {
            this.isPromoteAvailable = data.isPromoteAvailable;
            this.currentEnvName = data.currentEnvironment || '';
            this.targetEnvName = data.targetEnvironment || '';
            this.promoteButtonLabel = data.buttonLabel || 'Deploy to Next Stage';
            this.isAtUatStaging = !data.isPromoteAvailable && (this.currentEnvName === 'UAT' || this.currentEnvName.includes('UAT'));
            console.log(`${DEBUG_PREFIX} [wiredActionContext] SUCCESS:`, data);
        } else if (error) {
            console.error(`${DEBUG_PREFIX} [wiredActionContext] ERROR:`, error);
        }
    }

    handleOpenPromoteModal() {
        console.log(`${DEBUG_PREFIX} [handleOpenPromoteModal] Opening promotion modal for US: ${this.recordId}`);
        this.showPromoteModal = true;
    }

    handleClosePromoteModal() {
        console.log(`${DEBUG_PREFIX} [handleClosePromoteModal] Closing promotion modal.`);
        this.showPromoteModal = false;
    }

    @wire(getPromotions, { userStoryId: '$recordId' })
    wiredPromotions(result) {
        this._wiredPromotionsResult = result;
        const { data, error } = result;
        console.debug(`${DEBUG_PREFIX} getPromotions wire response`, {
            recordId: this.recordId,
            hasData: !!data,
            hasError: !!error
        });
        if (data) {
            this._promotions = data;
            console.debug(`${DEBUG_PREFIX} promotions loaded`, {
                recordId: this.recordId,
                count: data.length,
                statuses: data.map(p => p.Status__c)
            });
            this.checkActivePromotions();
        } else if (error) {
            console.error(`${DEBUG_PREFIX} Error fetching promotions for deliver tab`, this.normalizeError(error), error);
            this.stopPolling();
            this.showPushingSpinner = false;
        }
    }

    get promotionsCount() {
        return this._promotions ? this._promotions.length : 0;
    }

    get hasPromotions() {
        return this._promotions && this._promotions.length > 0;
    }

    get promotionsList() {
        if (!this._promotions) {return [];}

        return this._promotions.map(p => {

            const status = p.Status__c || '';

            let statusBadgeClass = 'status-badge';

            switch (status) {
                case 'Completed':
                    statusBadgeClass += ' status-badge--success';
                    break;

                case 'Failed':
                case 'Cancelled':
                    statusBadgeClass += ' status-badge--error';
                    break;

                case 'Draft':
                    statusBadgeClass += ' status-badge--draft';
                    break;

                case 'Ready':
                case 'Executing':
                case 'Waiting For Approval':
                case 'In Progress':
                    statusBadgeClass += ' status-badge--executing';
                    break;

                default:
                    break;
            }

            return {
                id: p.Id,
                promotedUserStory: '',
                promotionName: p.Name,
                status: status,
                statusBadge: true,
                statusBadgeClass: statusBadgeClass,
                isBackPromotion: false,
                release: p.Release__r ? p.Release__r.Name : '',
                sourceEnv: p.Source_Environment__r ? p.Source_Environment__r.Name__c : '',
                targetEnv: p.Target_Environment__r ? p.Target_Environment__r.Name__c : ''
            };

        });
    }

    checkActivePromotions() {

        const activeStatuses = [
            'Executing',
            'In Progress'
        ];

        const terminalStatuses = [
            'Completed',
            'Failed',
            'Cancelled'
        ];

        let hasActivePromotion = false;
        let hasTerminalPromotion = false;
        let terminalPromo = null;

        if (this._promotions && this._promotions.length > 0) {
            // Only evaluate the most recent promotion to prevent infinite spinners from old stuck promotions
            const mostRecentPromo = this._promotions[0];
            hasActivePromotion = activeStatuses.includes(mostRecentPromo.Status__c);
            hasTerminalPromotion = terminalStatuses.includes(mostRecentPromo.Status__c);
            if (hasTerminalPromotion) {
                terminalPromo = mostRecentPromo;
            }
        }

        // Update spinner state based on active vs terminal promotions
        let shouldShowSpinner = false;
        if (hasActivePromotion) {
            shouldShowSpinner = true;
        } else if (hasTerminalPromotion) {
            shouldShowSpinner = false;
        } else {
            shouldShowSpinner = false;
        }

        // Only update spinner and start/stop polling if state changed
        const spinnerChanged = this.showPushingSpinner !== shouldShowSpinner;

        if (spinnerChanged) {
            this.showPushingSpinner = shouldShowSpinner;

            if (shouldShowSpinner) {
                this.startPolling();
            } else {
                this.stopPolling();

                // Show notification for terminal promotion completion
                if (hasTerminalPromotion && terminalPromo) {
                    const statusMessage = terminalPromo.Status__c === 'Completed'
                        ? 'Promotion completed successfully.'
                        : 'Promotion ' + terminalPromo.Status__c.toLowerCase() + '.';

                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Promotion Update',
                            message: statusMessage,
                            variant: terminalPromo.Status__c === 'Completed' ? 'success' : 'warning'
                        })
                    );
                }

                this.dispatchEvent(
                    new CustomEvent('workspacechange', {
                        bubbles: true,
                        composed: true
                    })
                );
            }
        } else {
            // State didn't change, but ensure polling is correct
            if (hasActivePromotion && !this._pollingInterval) {
                this.startPolling();
            } else if (!hasActivePromotion && this._pollingInterval) {
                this.stopPolling();
            }
        }

    }

    startPolling() {

        if (this._pollingInterval) {
            return;
        }

        this._pollingStartedAt = Date.now();

        this._pollingInterval = setInterval(async () => {

            if (Date.now() - this._pollingStartedAt > MAX_POLLING_DURATION_MS) {
                console.warn(`${DEBUG_PREFIX} Polling timeout reached. Stopping.`);
                this.stopPolling();
                this.showPushingSpinner = false;
                return;
            }

            try {

                await refreshApex(this._wiredPromotionsResult);

                this.checkActivePromotions();

            } catch (error) {

                console.error(`${DEBUG_PREFIX} Polling refreshApex failed`, error);

            }

        }, POLLING_INTERVAL_MS);

    }

    stopPolling() {

        if (!this._pollingInterval) {
            return;
        }

        clearInterval(this._pollingInterval);

        this._pollingInterval = null;
        this._pollingStartedAt = null;

    }

    connectedCallback() {
        this.showPushingSpinner = false;
        this.stopPolling();
        
        // Force refresh to remove any stale state immediately
        if (this._wiredPromotionsResult) {
            refreshApex(this._wiredPromotionsResult)
                .then(() => {
                    this.checkActivePromotions();
                })
                .catch(error => {
                    console.error(`${DEBUG_PREFIX} connectedCallback Refresh failed`, error);
                });
        }
    }

    disconnectedCallback() {
        this.showPushingSpinner = false;
        this.stopPolling();
    }

    handleRefresh() {

        refreshApex(this._wiredPromotionsResult)
            .then(() => {

                this.checkActivePromotions();

            })
            .catch(error => {

                console.error(`${DEBUG_PREFIX} Refresh failed`, error);

            });

    }

    handleNewPromotion() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Promotion__c',
                actionName: 'new'
            }
        });
    }

    handleNavigateToPromotion(event) {
        event.preventDefault();
        const promoId = event.currentTarget.dataset.id;
        console.debug(`${DEBUG_PREFIX} navigate to promotion`, { recordId: this.recordId, promoId });
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: promoId,
                actionName: 'view'
            }
        });
    }

    handleViewAll(event) {
        event.preventDefault();
        console.debug(`${DEBUG_PREFIX} navigate to all promotions`, { recordId: this.recordId });
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                relationshipApiName: 'Promotions__r',
                actionName: 'view'
            }
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