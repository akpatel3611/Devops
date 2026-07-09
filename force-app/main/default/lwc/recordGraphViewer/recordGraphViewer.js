import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedObjects from '@salesforce/apex/SchemaExplorerService.getRelatedObjects';
import getRelatedRecordCounts from '@salesforce/apex/DynamicRecordService.getRelatedRecordCounts';
import getRelatedRecords from '@salesforce/apex/DynamicRecordService.getRelatedRecords';
import searchRecords from '@salesforce/apex/DynamicRecordService.searchRecords';

export default class RecordGraphViewer extends NavigationMixin(LightningElement) {

    selectedObjectApi = null;
    selectedRecordId = null;
    relatedObjectSearchKey = '';
    recordSelected = false;
    leftPanelOpen = false;
    canvasVisible = false;
    rightPanelVisible = false;

    /* ================= PANEL STATE ================= */
    rightPanelMode = 'LIST'; // 'LIST' or 'DETAIL'
    rightPanelRecords = [];
    selectedPanelRecordId = null;
    selectedPanelObjectApi = null;

    // To show which object's list/details is open
    rightPanelTitle = 'Related Records';
    // Tracks list object (useful as fallback)
    rightPanelListObjectApi = null;

    canvasWidth = 1200; // default safe width
    canvasNodes = [];
    canvasLinks = [];
    activeCanvasNode = null;

    centerNodeName = null;
    parentNodeName = null;

    searchResults = [];
    showSearchResults = false;
    searchTimeout;

    allRelatedObjects = [];
    filteredRelatedObjects = [];
    selectedRelatedObjects = [];

    /* ================= DRAG VARS ================= */
    canvasScale = 1;
    draggingElement = null;
    dragOffsetX = 0;
    dragOffsetY = 0;
    canvasRect;
    isDragging = false;

    isDraggingCanvas = false;
    canvasDragStartX = 0;
    canvasDragStartY = 0;
    canvasStartPositions = [];

    objectOptions = [
        { label: 'Account', value: 'Account' },
        { label: 'Contact', value: 'Contact' },
        { label: 'Opportunity', value: 'Opportunity' },
        { label: 'Case', value: 'Case' },
        { label: 'Lead', value: 'Lead' },
        { label: 'Task', value: 'Task' }
    ];

    /* ================= GETTERS (IMPORTANT FIX) ================= */
    get isRightPanelList() {
        return this.rightPanelMode === 'LIST';
    }

    get isRightPanelDetail() {
        return this.rightPanelMode === 'DETAIL';
    }

    get hasRightPanelRecords() {
        return this.rightPanelRecords && this.rightPanelRecords.length > 0;
    }

    get hasSearchResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    getIconName(obj) {
    return 'standard:' + obj.toLowerCase();
}

    /* ================= OBJECT CHANGE ================= */
    handleObjectChange(event) {
        this.selectedObjectApi = event.detail.value;
        this.resetUI();
    }

    /* ================= RECORD SEARCH ================= */
    handleRecordSearch(event) {
        const value = event.target.value;
        clearTimeout(this.searchTimeout);

        if (!value || value.length < 2 || !this.selectedObjectApi) {
            this.showSearchResults = false;
            this.searchResults = [];
            return;
        }

        this.searchTimeout = setTimeout(() => {
            searchRecords({
                objectApiName: this.selectedObjectApi,
                searchKey: value
            }).then(result => {
                this.searchResults = result || [];
                this.showSearchResults = true;
            });
        }, 300);
    }

    handleRecordSelect(event) {
        this.selectedRecordId = event.currentTarget.dataset.id;
        this.recordSelected = true;

        // IMPORTANT RESET
        this.canvasVisible = false;
        this.rightPanelVisible = false;
        this.rightPanelMode = 'LIST';

        this.showSearchResults = false;
    }

    /* ================= LEFT PANEL ================= */
    toggleLeftPanel() {
    if (!this.recordSelected && !this.canvasVisible && this.canvasNodes.length === 0) {
        return;
    }

    this.leftPanelOpen = !this.leftPanelOpen;

    requestAnimationFrame(() => {
        this.rebuildTreeLayout();
    });

    if (this.leftPanelOpen && this.allRelatedObjects.length === 0) {
        getRelatedObjects({ objectApiName: this.selectedObjectApi })
            .then(result => {
                this.allRelatedObjects = (result || []).map(o => ({
                    label: o.objectLabel,
                    value: o.objectApiName
                }));
                this.filteredRelatedObjects = this.allRelatedObjects.slice(0, 20);
            });
    }
}


    handleRelatedObjectSearch(event) {
    this.relatedObjectSearchKey = event.target.value;

    const key = this.relatedObjectSearchKey.toLowerCase();
    this.filteredRelatedObjects =
        this.allRelatedObjects.filter(o =>
            o.label.toLowerCase().includes(key)
        );
    }

        selectRelatedObject(event) {
            const value = event.currentTarget.dataset.value;

            const exists = this.selectedRelatedObjects.some(o => o.apiName === value);

            if (!exists) {
                this.selectedRelatedObjects = [
                    ...this.selectedRelatedObjects,
                    {
                        apiName: value,
                        icon: 'standard:' + value.toLowerCase()
                    }
                ];
            }
        
            this.filteredRelatedObjects = this.allRelatedObjects.slice(0, 20);
            this.relatedObjectSearchKey = '';
        
            requestAnimationFrame(() => {
                const input = this.template.querySelector('[data-id="relatedSearch"]');
                if (input) input.focus();
            });
        
            // ✅ FIX: canvas loaded check
            requestAnimationFrame(() => {
                if (this.canvasVisible) {
                    this.focusNodeOnCanvas(value);
                }
            });
        }


        removeSelectedObject(event) {
            const value = event.currentTarget.dataset.value;
            this.selectedRelatedObjects =
                this.selectedRelatedObjects.filter(o => o.apiName !== value);
        }


    /* ================= HIERARCHY ACTIONS ================= */

    // View button: only selected objects
        showSelectedHierarchy() {
        if (!this.selectedRecordId) return;

        if (!this.selectedRelatedObjects || this.selectedRelatedObjects.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Objects Selected',
                    message: 'Please select at least one related object.',
                    variant: 'warning'
                })
            );
            return;
        }

        // ✅ FIX: object array → string array
        const objectApis = this.selectedRelatedObjects.map(o => o.apiName);
        this.loadHierarchy(objectApis);
    }


    // SView button: all related objects
    showStandardHierarchy() {
        
        if (!this.selectedRecordId) return;
        
        const allObjects = this.allRelatedObjects.map(o => o.value);
        
        if (!allObjects || allObjects.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Related Objects',
                    message: 'No related objects available.',
                    variant: 'info'
                })
            );
            return;
        }
        console.log("button clicked");
        this.loadHierarchy(allObjects);
    }

    /* ========= COMMON HIERARCHY LOADER ========= */
    loadHierarchy(objectList) {
        if (!objectList || objectList.length === 0) return;

        getRelatedRecordCounts({
            parentObject: this.selectedObjectApi,
            parentRecordId: this.selectedRecordId,
            relatedObjects: objectList
        }).then(result => {
            this.buildCanvasNodes(result || [], objectList);
            this.buildLinks();

            this.canvasVisible = true;
            this.recordSelected = false;

            requestAnimationFrame(() => {
                this.rebuildTreeLayout();
            });
            });
        }

    /* ================= CANVAS (OLD SHOWCANVAS KE JAGAH) ================= */
    showCanvas() {
        // Optional: keep View button working same as selected hierarchy
        this.showSelectedHierarchy();
    }


    zoomIn() {
    this.canvasScale = Math.min(this.canvasScale + 0.1, 2);
    this.applyCanvasTransform();
    }

    zoomOut() {
    this.canvasScale = Math.max(this.canvasScale - 0.1, 0.5);
    this.applyCanvasTransform();
    }

    applyCanvasTransform() {
    const canvas = this.template.querySelector('.canvas-area');
    if (canvas) {
        canvas.style.transform = `scale(${this.canvasScale})`;
        canvas.style.transformOrigin = '0 0';
    }
    }


    focusNodeOnCanvas(objectApi) {
    const node = this.canvasNodes.find(n => n.objectApiName === objectApi);
    if (!node) return;

    const canvas = this.template.querySelector('.canvas-area');
    if (!canvas) return;

    const centerX = canvas.offsetWidth / 2;
    const centerY = canvas.offsetHeight / 2;

    const nodeCenterX = node.x + 60; // half of 120
    const nodeCenterY = node.y + 30; // half of 60

    const dx = centerX - nodeCenterX;
    const dy = centerY - nodeCenterY;

    this.canvasNodes.forEach(n => {
        n.x += dx;
        n.y += dy;
    });

    this.renderedCallback();
    this.buildLinks();
}


    rebuildTreeLayout() {
    if (!this.canvasVisible) return;

    const canvas = this.template.querySelector('.canvas-area');
    if (!canvas) return;

    this.canvasWidth = canvas.offsetWidth;

    const relatedObjects = this.canvasNodes
        .filter(n => n.type === 'RELATED')
        .map(n => n.objectApiName);

    if (relatedObjects.length > 0) {
        const counts = this.canvasNodes
            .filter(n => n.type === 'RELATED')
            .map(n => ({
            objectApiName: n.objectApiName,
            totalCount: n.count
        }));

        this.buildCanvasNodes(counts, relatedObjects);

        this.buildLinks();
    }
}


    buildCanvasNodes(counts, objectList) {
    let nodes = [];
    c
    const startX = 100;
    const startY = 130;
    const gapX = 150;
    const nodeSize = 70;

    const availableWidth = this.canvasWidth || 1200;
    const totalNodes = objectList.length;

    // CENTER X
    const centerX = Math.floor(availableWidth / 2) - (nodeSize / 2);

    // CENTER NODE
    nodes.push({
        name: 'Current',
        label: this.selectedObjectApi,
        objectApiName: this.selectedObjectApi,
        icon: 'standard:' + this.selectedObjectApi.toLowerCase(),
        x: centerX,
        y: startY,
        count: '',
        type: 'CENTER'
    });

    // PARENT NODE
    if (this.selectedObjectApi !== 'Account') {
        nodes.push({
            name: 'Parent',
            label: 'Account',
            objectApiName: 'Account',
            icon: 'standard:account',
            x: centerX,
            y: startY - 140,
            count: '',
            type: 'PARENT'
        });
    }

    // 👉 SINGLE ROW ONLY (NO WRAP)
    const totalWidth = (totalNodes - 1) * gapX;
    const baseX = centerX - (totalWidth / 2);

    objectList.forEach((objApi, index) => {
        const rec = counts.find(c => c.objectApiName === objApi);
        const totalCount = rec ? rec.totalCount : 0;

        nodes.push({
            name: objApi,
            label: objApi,
            objectApiName: objApi,
            icon: 'standard:' + objApi.toLowerCase(),
            x: baseX + (index * gapX),
            y: startY + 170,
            count: totalCount,
            type: 'RELATED'
        });
    });

    this.canvasNodes = nodes;
}


    buildLinks() {
    const links = [];

    const center = this.canvasNodes.find(n => n.type === 'CENTER');
    const parent = this.canvasNodes.find(n => n.type === 'PARENT');

    const midX = (a, b) => (a + b) / 2;

    if (parent && center) {
        const x1 = parent.x + 60;
        const y1 = parent.y + 60;
        const x2 = center.x + 60;
        const y2 = center.y;

        const midY = midX(y1, y2);

        links.push({
            id: 'parent-center',
            d: `M ${x1} ${y1}
                V ${midY}
                H ${x2}
                V ${y2}`
        });
    }

    if (center) {
        this.canvasNodes
            .filter(n => n.type === 'RELATED')
            .forEach(child => {
                const x1 = center.x + 60;
                const y1 = center.y + 60;
                const x2 = child.x + 60;
                const y2 = child.y;

                const midY = midX(y1, y2);

                links.push({
                    id: center.name + '-' + child.name,
                    d: `M ${x1} ${y1}
                        V ${midY}
                        H ${x2}
                        V ${y2}`
                });
            });
    }

    this.canvasLinks = links;
}


    renderedCallback() {
    if (!this.canvasVisible) return;

    const canvas = this.template.querySelector('.canvas-area');
    if (canvas) {
        this.canvasWidth = canvas.offsetWidth;
    }

    const nodes = this.template.querySelectorAll('.canvas-node');
    nodes.forEach(el => {
        const node = this.canvasNodes.find(n => n.name === el.dataset.name);
        if (node) {
            el.style.left = node.x + 'px';
            el.style.top = node.y + 'px';
        }
    });
}

    /* ================= DRAG SINGLE NODE ================= */
    startDrag(event) {
        event.stopPropagation();
        this.draggingElement = event.currentTarget;
        this.isDragging = false;

        const rect = this.draggingElement.getBoundingClientRect();
        this.dragOffsetX = event.clientX - rect.left;
        this.dragOffsetY = event.clientY - rect.top;

        this.canvasRect = this.template.querySelector('.canvas-area').getBoundingClientRect();
        document.addEventListener('mousemove', this.dragMove);
        document.addEventListener('mouseup', this.stopDrag);
    }

    dragMove = (event) => {
        if (!this.draggingElement) return;
        this.isDragging = true;

        let x = event.clientX - this.canvasRect.left - this.dragOffsetX;
        let y = event.clientY - this.canvasRect.top - this.dragOffsetY;

        this.draggingElement.style.left = x + 'px';
        this.draggingElement.style.top = y + 'px';

        const name = this.draggingElement.dataset.name;
        const node = this.canvasNodes.find(n => n.name === name);
        if (node) {
            node.x = x;
            node.y = y;
        }
        this.buildLinks();
    };

    stopDrag = () => {
        document.removeEventListener('mousemove', this.dragMove);
        document.removeEventListener('mouseup', this.stopDrag);
        this.draggingElement = null;
    };

    /* ================= DRAG FULL CANVAS ================= */
    startCanvasDrag(event) {
        if (event.target.closest('.canvas-node')) return;
        this.isDraggingCanvas = true;
        this.isDragging = false;
        this.canvasDragStartX = event.clientX;
        this.canvasDragStartY = event.clientY;

        this.canvasStartPositions = this.canvasNodes.map(n => ({
            name: n.name, x: n.x, y: n.y
        }));
        document.addEventListener('mousemove', this.canvasDragMove);
        document.addEventListener('mouseup', this.stopCanvasDrag);
    }

    canvasDragMove = (event) => {
        if (!this.isDraggingCanvas) return;
        this.isDragging = true;
        const dx = event.clientX - this.canvasDragStartX;
        const dy = event.clientY - this.canvasDragStartY;

        this.canvasNodes.forEach(node => {
            const start = this.canvasStartPositions.find(p => p.name === node.name);
            if (start) {
                node.x = start.x + dx;
                node.y = start.y + dy;
            }
        });

        const els = this.template.querySelectorAll('.canvas-node');
        els.forEach(el => {
            const node = this.canvasNodes.find(n => n.name === el.dataset.name);
            if (node) {
                el.style.left = node.x + 'px';
                el.style.top = node.y + 'px';
            }
        });

        this.buildLinks();
    };

    stopCanvasDrag = () => {
        this.isDraggingCanvas = false;
        document.removeEventListener('mousemove', this.canvasDragMove);
        document.removeEventListener('mouseup', this.stopCanvasDrag);
    };

    /* ================= NODE CLICK ================= */
    handleCanvasClick(event) {
        if (this.isDragging) return;

        if (this.activeCanvasNode === event.currentTarget.dataset.name) {
            this.rightPanelVisible = false;
            this.activeCanvasNode = null;
            return;
        }

        const nodeName = event.currentTarget.dataset.name;
        const node = this.canvasNodes.find(n => n.name === nodeName);
        if (!node) return;

        this.activeCanvasNode = nodeName;

        const fetchAndShow = (relatedObjApi, title) => {
            getRelatedRecords({
                parentObject: this.selectedObjectApi,
                relatedObject: relatedObjApi,
                parentRecordId: this.selectedRecordId
            }).then(result => {
                this.rightPanelRecords = result || [];
                this.rightPanelVisible = true;

                requestAnimationFrame(() => {
                    this.rebuildTreeLayout();
                });

                this.rightPanelTitle = title;
                this.rightPanelListObjectApi = relatedObjApi;

                if (this.rightPanelRecords.length === 1 && (node.type === 'CENTER' || node.type === 'PARENT')) {
                    this.selectedPanelRecordId = this.rightPanelRecords[0].recordId;
                    this.selectedPanelObjectApi = this.rightPanelRecords[0].objectApiName || relatedObjApi;
                    this.rightPanelMode = 'DETAIL';
                } else {
                    this.selectedPanelRecordId = null;
                    this.selectedPanelObjectApi = null;
                    this.rightPanelMode = 'LIST';
                }
            });
        };

        // Node count 0 => toast + return
        if (node.type === 'RELATED') {
            if (!node.count || node.count === 0) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'No Records',
                        message: 'No ' + node.objectApiName + ' records found for this record.',
                        variant: 'info'
                    })
                );
                return;
            }
        }

        if (node.type === 'CENTER') {
            fetchAndShow(this.selectedObjectApi, this.selectedObjectApi + ' (Current Record)');
        } else if (node.type === 'PARENT') {
            fetchAndShow('Account', 'Account (Parent Record)');
        } else {
            if (!node.count || node.count === 0) return;
            fetchAndShow(node.objectApiName, node.objectApiName + ' (Related Records)');
        }
    }

    /* ================= PANEL ACTIONS ================= */
    handlePanelRecordClick(event) {
        const recId = event.currentTarget.dataset.id;
        const objApiFromRow = event.currentTarget.dataset.object;

        const finalObjApi = objApiFromRow || this.rightPanelListObjectApi;
        if (!recId || !finalObjApi) return;

        this.selectedPanelRecordId = recId;
        this.selectedPanelObjectApi = finalObjApi;
        this.rightPanelMode = 'DETAIL';
    }

    handleBack() {
        this.rightPanelMode = 'LIST';
        this.selectedPanelRecordId = null;
        this.selectedPanelObjectApi = null;
    }

    handleView() {
    if (this.selectedPanelRecordId && this.selectedPanelObjectApi) {

        // Generate URL for the record page, then open it in a new tab
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedPanelRecordId,
                objectApiName: this.selectedPanelObjectApi,
                actionName: 'view'
            }
        }).then(url => {
            // New browser tab / window
            window.open(url, '_blank');
        });

    }
}


    resetRightPanelState() {
        this.rightPanelMode = 'LIST';
        this.rightPanelRecords = [];
        this.selectedPanelRecordId = null;
        this.selectedPanelObjectApi = null;
        this.rightPanelTitle = 'Related Records';
        this.rightPanelListObjectApi = null;
    }

    openStandardList() {
        if (!this.selectedObjectApi) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.selectedObjectApi,
                actionName: 'list'
            },
            state: { filterName: 'Recent' }
        });
    }

    resetUI() {
        this.recordSelected = false;
        this.leftPanelOpen = false;
        this.canvasVisible = false;
        this.rightPanelVisible = false;
        this.searchResults = [];
        this.showSearchResults = false;
        this.allRelatedObjects = [];
        this.filteredRelatedObjects = [];
        this.selectedRelatedObjects = [];
        this.canvasNodes = [];
        this.canvasLinks = [];
        this.rightPanelRecords = [];
        this.rightPanelMode = 'LIST';
    }
}