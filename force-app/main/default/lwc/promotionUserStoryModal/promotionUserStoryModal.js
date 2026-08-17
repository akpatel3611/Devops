import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReadyUserStories from '@salesforce/apex/PromotionPageController.getReadyUserStories';
import addUserStoriesToPromotion from '@salesforce/apex/PromotionPageController.addUserStoriesToPromotion';

export default class PromotionUserStoryModal extends LightningElement {
    @api promotionId;
    @api pipelineId;
    @api sourceEnvironmentId;

    @track allStories = [];
    @track filteredStories = [];
    @track isLoading = true;
    @track searchTerm = '';
    @track isSaving = false;

    connectedCallback() {
        this.loadStories();
    }

    async loadStories() {
        this.isLoading = true;
        try {
            const stories = await getReadyUserStories({
                pipelineId: this.pipelineId,
                sourceEnvironmentId: this.sourceEnvironmentId
            });
            this.allStories = stories.map(s => ({
                ...s,
                selected: false,
                rowClass: 'story-row'
            }));
            this.filteredStories = [...this.allStories];
        } catch (error) {
            console.error('Error loading stories:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Loading Stories',
                message: error.body ? error.body.message : 'Could not load user stories',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // -------------------------
    // Computed Properties
    // -------------------------
    get hasFilteredStories() {
        return this.filteredStories && this.filteredStories.length > 0;
    }

    get filteredCount() {
        return this.filteredStories ? this.filteredStories.length : 0;
    }

    get selectedCount() {
        return this.filteredStories.filter(s => s.selected).length;
    }

    get hasSelection() {
        return this.selectedCount > 0;
    }

    get isSaveDisabled() {
        return this.isSaving || !this.hasSelection;
    }

    get allSelected() {
        return this.filteredStories.length > 0 &&
               this.filteredStories.every(s => s.selected);
    }

    // -------------------------
    // Event Handlers
    // -------------------------
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.applyFilter();
    }

    applyFilter() {
        const term = this.searchTerm.toLowerCase().trim();
        if (!term) {
            this.filteredStories = this.allStories.map(s => ({ ...s }));
        } else {
            this.filteredStories = this.allStories
                .filter(s =>
                    (s.name && s.name.toLowerCase().includes(term)) ||
                    (s.title && s.title.toLowerCase().includes(term)) ||
                    (s.developer && s.developer.toLowerCase().includes(term))
                )
                .map(s => ({ ...s }));
        }
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.filteredStories = this.filteredStories.map(s => ({
            ...s,
            selected: checked,
            rowClass: checked ? 'story-row story-selected' : 'story-row'
        }));
        // Sync back to all stories
        const selectedIds = new Set(this.filteredStories.filter(s => s.selected).map(s => s.id));
        this.allStories = this.allStories.map(s => ({
            ...s,
            selected: selectedIds.has(s.id),
            rowClass: selectedIds.has(s.id) ? 'story-row story-selected' : 'story-row'
        }));
    }

    handleCheckboxChange(event) {
        const storyId = event.target.dataset.id;
        const checked = event.target.checked;
        this.updateStorySelection(storyId, checked);
    }

    handleRowClick(event) {
        const storyId = event.currentTarget.dataset.id;
        const story = this.filteredStories.find(s => s.id === storyId);
        if (story) {
            this.updateStorySelection(storyId, !story.selected);
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    updateStorySelection(storyId, selected) {
        this.filteredStories = this.filteredStories.map(s => {
            if (s.id === storyId) {
                return { ...s, selected, rowClass: selected ? 'story-row story-selected' : 'story-row' };
            }
            return s;
        });
        // Sync back to allStories
        this.allStories = this.allStories.map(s => {
            if (s.id === storyId) {
                return { ...s, selected, rowClass: selected ? 'story-row story-selected' : 'story-row' };
            }
            return s;
        });
    }

    async handleSave() {
        const selectedIds = this.filteredStories.filter(s => s.selected).map(s => s.id);
        if (!selectedIds.length) return;

        this.isSaving = true;
        try {
            const result = await addUserStoriesToPromotion({
                promotionId: this.promotionId,
                userStoryIds: selectedIds
            });

            if (result.success) {
                this.dispatchEvent(new CustomEvent('save', {
                    detail: { message: result.message, count: selectedIds.length }
                }));
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Failed to Add Stories',
                    message: result.message,
                    variant: 'error'
                }));
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body ? error.body.message : 'Failed to add user stories',
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}