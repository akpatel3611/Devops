import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedObjects from '@salesforce/apex/SchemaExplorerService.getRelatedObjects';
import getRelatedRecordCounts from '@salesforce/apex/DynamicRecordService.getRelatedRecordCounts';
import getRelatedRecords from '@salesforce/apex/DynamicRecordService.getRelatedRecords';
import getObjectHierarchyTree from '@salesforce/apex/SchemaExplorerService.getObjectHierarchyTree';
import searchRecords from '@salesforce/apex/DynamicRecordService.searchRecords';
export default class RecordGraphView extends NavigationMixin(LightningElement) {

 selectedObjectApi = null;
 parentObjectApis = [];
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
 activeRelatedObject = null;

 // hierarchy
 hierarchyNodes = [];
 expandedNodeIds = new Set();
 filteredHierarchyNodes = null;
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

 // ================= ICON MAP (GLOBAL SAFE) =================
 iconMap = {
  Account: 'standard:account',
  Contact: 'standard:contact',
  Opportunity: 'standard:opportunity',
  Case: 'standard:case',
  Lead: 'standard:lead',
  Task: 'standard:task2'
 };

 /* ================= GLOBAL DEBUG ENGINE ================= */
 debugEnabled = true;
 debugStep = 0;
 logStep(title, data) {
  if (!this.debugEnabled) return;
  this.debugStep++;
  console.group(
   `%cSTEP ${this.debugStep} :: ${title}`,
   "color:white;background:#0070d2;padding:3px 6px;border-radius:3px"
  );
  if (data !== undefined) {
   console.log("DATA →", data);
  }
  console.groupEnd();
 }
 logApex(title, payload, result) {
  if (!this.debugEnabled) return;
  console.group(
   `%cAPEX CALL :: ${title}`,
   "color:white;background:#2e844a;padding:3px 6px;border-radius:3px"
  );
  console.log("REQUEST →", payload);
  console.log("RESPONSE →", result);
  console.groupEnd();
 }

 logError(title, error) {
  console.group(
   `%cERROR :: ${title}`,
   "color:white;background:#ba0517;padding:3px 6px;border-radius:3px"
  );
  console.error(error);
  console.groupEnd();
 }

 logHierarchy(nodes) {
  if (!this.debugEnabled) return;
  console.group(
   "%cHIERARCHY TREE STRUCTURE",
   "color:white;background:#444;padding:3px 6px"
  );
  nodes.forEach(n => {
   console.log(

    `nodeId=${n.nodeId} | parentNodeId=${n.parentNodeId} | level=${n.level} | object=${n.objectApiName}`
   );
  });
  console.groupEnd();
 }

 logCanvasNodes(nodes) {
  console.group("%cCANVAS NODE POSITIONS", "color:white;background:#706e6b;padding:3px 6px"
  );
  nodes.forEach(n => {
   console.log(
    `${n.objectApiName} | type=${n.type} | x=${n.x} | y=${n.y} | parent=${n.parentNodeId}`
   );
  });
  console.groupEnd();
 }
 logLinks(links) {
  console.group("%cCANVAS LINKS", "color:white;background:#706e6b;padding:3px 6px"
  );
  console.table(links);
  console.groupEnd();
 }

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
   /* ================= DYNAMIC ICON ENGINE (RESTORED) ================= */
    /* ================= DYNAMIC ICON ENGINE (RESTORED) ================= */
    getIconName(obj) {
        if (!obj) return 'standard:hierarchy'; // Safe fallback

        let isCustom = obj.endsWith('__c');
        let category = isCustom ? 'custom' : 'standard';
        let iconName = obj.toLowerCase().replace('__c', '');

        // Standard Salesforce Overrides (Special icons handle karne ke liye)
        const overrides = {
            'task': 'task',
            'event': 'event',
            'casecomment': 'case_comment',
            'activityhistory': 'log_a_call',
            'openactivity': 'event',
            'emailmessage': 'email',
            'contentversion': 'file',
            'attachment': 'document',
            'dandbcompany': 'account', // 🔥 FIX: D&B Company ka icon missing tha
            'operatinghours': 'operating_hours',
            'cadence': 'cadence'
        };

        let finalName = overrides[iconName] || iconName;
        return `${category}:${finalName}`;
    }
 /* ================= OBJECT CHANGE ================= */

 handleObjectChange(event) {
  this.selectedObjectApi = event.detail.value;
  this.logStep("OBJECT SELECTED", this.selectedObjectApi);
  this.resetUI();
  // ✅ CLEAR HEADER INPUT UI
  const input = this.template.querySelector('[data-id="recordSearch"]');
  if (input) input.value = '';
  this.latestSearchKey = null;
 }
 /* ================= RECORD SEARCH ================= */

 handleRecordSearch(event) {
  const value = event.target.value;
  this.logStep("SEARCH INPUT", value);
  clearTimeout(this.searchTimeout);
  // 🔒 SAVE CURRENT INPUT (IMPORTANT)
  this.latestSearchKey = value
  if (!value || value.length < 2 || !this.selectedObjectApi) {
   this.showSearchResults = false;
   this.searchResults = [];
   return;
  }
  this.searchTimeout = setTimeout(() => {
   const currentKey = this.latestSearchKey;
   searchRecords({
    objectApiName: this.selectedObjectApi,
    searchKey: currentKey
   })
    .then(result => {
     if (currentKey !== this.latestSearchKey) return;
     this.searchResults = result || [];
     this.showSearchResults = true;
    })
    .catch((error) => {
     this.logError("searchRecords failed", error);
     this.searchResults = [];
     this.showSearchResults = false;
    });
  }, 300);
 }
 handlePillClick(event) {
  const apiName = event.currentTarget.dataset.api;
  this.focusNodeOnCanvas(apiName);
 }

 handleRecordSelect(event) {
  this.selectedRecordId = event.currentTarget.dataset.id;
  this.logStep("RECORD SELECTED", this.selectedRecordId);
  this.recordSelected = true;
  // IMPORTANT RESET
  this.canvasVisible = false;
  this.rightPanelVisible = false;
  this.rightPanelMode = 'LIST';
  this.hierarchyNodes = [];
  this.expandedNodeIds = new Set();
  this.filteredHierarchyNodes = null;
  this.showSearchResults = false;

  getRelatedObjects({ objectApiName: this.selectedObjectApi })
   .then(result => {
    this.logApex("getRelatedObjects", { objectApiName: this.selectedObjectApi }, result);
    const data = result || [];
    this.allRelatedObjects = data.map(r => ({
     label: r.objectLabel,
     value: r.objectApiName
    }));
    this.filteredRelatedObjects = this.allRelatedObjects.slice(0, 20);

    // ✅ 🔥 REAL PARENT DETECTION
    const parentList = data.filter(r => r.relationshipType === 'Parent');
    this.parentObjectApis = parentList.map(p => p.objectApiName);
   });
  getObjectHierarchyTree({ objectApi: this.selectedObjectApi })
   .then(result => {
    this.hierarchyNodes = result || [];
    this.logApex("getObjectHierarchyTree", { objectApi: this.selectedObjectApi }, result);
    this.logHierarchy(result);
   });

  // ✅ CLEAR HEADER INPUT UI
  const input = this.template.querySelector('[data-id="recordSearch"]');
  if (input) input.value = '';
  // ✅ RESET STATE
  this.searchResults = [];
  this.showSearchResults = false;
  this.latestSearchKey = null;
 }
 /* ================= LEFT PANEL ================= */
 toggleLeftPanel() {
  if (!this.recordSelected && !this.canvasVisible) return;
  this.leftPanelOpen = !this.leftPanelOpen;

  requestAnimationFrame(() => {
   this.rebuildTreeLayout();
  });
  if (this.leftPanelOpen && this.selectedObjectApi) {
   getObjectHierarchyTree({ objectApi: this.selectedObjectApi })

    .then(result => {
     this.hierarchyNodes = result || [];
     // 🔹 default expand ROOT + CHILD
     this.expandedNodeIds = new Set();
     this.hierarchyNodes.forEach(n => {
      if (n.level <= 1) {
       this.expandedNodeIds.add(n.nodeId);
      }
     });
   });
  }
 }

 toggleExpand(event) {
  const nodeId = event.currentTarget.dataset.id;
  const updated = new Set(this.expandedNodeIds);
  if (updated.has(nodeId)) {
   updated.delete(nodeId);
  } else {
   updated.add(nodeId);
  }
  this.expandedNodeIds = updated;
 }
 get visibleHierarchyNodes() {
  const source = this.filteredHierarchyNodes !== null
   ? this.filteredHierarchyNodes
   : this.hierarchyNodes;
  if (!source || source.length === 0) {
   return [];
  }
  const nodeMap = new Map();
  source.forEach(n => {
   nodeMap.set(n.nodeId, { ...n, children: [] });
  });
  nodeMap.forEach(node => {
   if (node.parentNodeId && nodeMap.has(node.parentNodeId)) {
    const parent = nodeMap.get(node.parentNodeId);
    parent.children.push(node);
   }
  });
  const result = [];
  const walk = (node) => {
   const expanded = this.expandedNodeIds.has(node.nodeId);
   result.push({
    ...node,
    isRoot: node.level === 0,
    isChild: node.level === 1,
    isSubChild: node.level === 2,
    isExpanded: expanded,
    hasChildren: node.children.length > 0
   });
   if (expanded) {
    node.children.forEach(child => {
     walk(child);
    });
   }
  };
  nodeMap.forEach(node => {
   if (!node.parentNodeId) {
    walk(node);
   }
  });
  return result;
 }

 handleRelatedObjectSearch(event) {
  const key = (event.target.value || '').toLowerCase().trim();
  this.relatedObjectSearchKey = key;

  if (!key) {
   this.filteredHierarchyNodes = null;
   // RESET EXPANSION PROPERLY
   const initialExpand = new Set();
   this.hierarchyNodes.forEach(n => {
    if (n.level <= 1) {
     initialExpand.add(n.nodeId);

    }
   });
   this.expandedNodeIds = initialExpand;
   return;
  }
  const matchedIds = new Set();
  const nodeMap = new Map();
  this.hierarchyNodes.forEach(n => nodeMap.set(n.nodeId, n));
  // EXACT MAP LOGIC: find matches and their complete lineage
  this.hierarchyNodes.forEach(node => {
   const label = (node.label || '').toLowerCase();
   const api = (node.objectApiName || '').toLowerCase();
   if (label.includes(key) || api.includes(key)) {
    matchedIds.add(node.nodeId);
    // Backtrack to Root: Ensure all parents are visible
    let curr = node;
    while (curr && curr.parentNodeId) {
     matchedIds.add(curr.parentNodeId);
     curr = nodeMap.get(curr.parentNodeId);
    }
   }
  });
  // Hum filteredHierarchyNodes ko sirf wahi nodes denge jo matched hain
  this.filteredHierarchyNodes = this.hierarchyNodes.filter(n => matchedIds.has(n.nodeId));
  this.expandedNodeIds = new Set(matchedIds);
 }

  selectRelatedObject(event) {
      const value = event.currentTarget.dataset.value;
      this.activeRelatedObject = value;
    
      if (!this.selectedRelatedObjects.find(o => o.apiName === value)) {
          this.selectedRelatedObjects = [
              ...this.selectedRelatedObjects,
              {
                  apiName: value,
                  icon: this.getIconName(value)
              }
          ];
      }
    
      // 🔥 FIX: REACTIVITY RESET
      this.relatedObjectSearchKey = ''; 
      this.filteredHierarchyNodes = null; 
    
      // Expand Logic
      this.expandedNodeIds = new Set();
      this.hierarchyNodes.forEach(node => {
          if (node.level <= 1) this.expandedNodeIds.add(node.nodeId);
      });
    
      // Force redraw
      this.hierarchyNodes = [...this.hierarchyNodes]; 
    
      // 🔥 FIX: SEARCH FOCUS RESTORE
      setTimeout(() => {
          const searchBox = this.template.querySelector('[data-id="relatedSearch"]');
          if (searchBox) {
              searchBox.value = '';
              searchBox.focus();
          }
      }, 100);
    
      requestAnimationFrame(() => {
          this.focusNodeOnCanvas(value);
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
  this.logStep("LOAD HIERARCHY CALLED", objectList);
  if (!objectList || objectList.length === 0) return;
  getRelatedRecordCounts({
   parentObject: this.selectedObjectApi,
   parentRecordId: this.selectedRecordId,
   relatedObjects: objectList
  }).then(result => {
   this.logApex("getRelatedRecordCounts", {
    parentObject: this.selectedObjectApi,
    parentRecordId: this.selectedRecordId, relatedObjects: objectList
   });
   const countsArray = Array.isArray(result) ? result : [];
   if (!this.hierarchyNodes || this.hierarchyNodes.length === 0) {
    console.warn('Hierarchy not loaded');
    return;
   }
   this.buildCanvasNodes(countsArray, objectList);
   requestAnimationFrame(() => {
    this.buildLinks();
   });

   this.canvasVisible = true;
   this.recordSelected = false;
  });
 }

 /* ================= CANVAS (OLD SHOWCANVAS KE JAGAH) ================= */
 showCanvas() {
  // Optional: keep View button working same as selected hierarchy
  this.showSelectedHierarchy();
 }
 zoomIn() {
  this.updateZoom(1.1);
 }
 zoomOut() {
  this.updateZoom(0.9);
 }
 updateZoom(factor) {
  const newScale = this.canvasScale * factor;
  // 🔒 LIMITS (VERY IMPORTANT)
  if (newScale < 0.5 || newScale > 2) {
   return;
  }
  this.canvasScale = newScale;
  const zoomLayer = this.template.querySelector('.canvas-zoom-layer');
  if (zoomLayer) {
   zoomLayer.style.transform = `scale(${this.canvasScale})`;
  }
 }
 focusNodeOnCanvas(objectApi) {
    const node = this.canvasNodes.find(n => n.objectApiName === objectApi);
    if (!node) return;

    const canvas = this.template.querySelector('.canvas-area');
    if (!canvas) return;

    const centerX = canvas.offsetWidth / 2;
    const centerY = canvas.offsetHeight / 2;
    const dx = centerX - (node.x + 60);
    const dy = centerY - (node.y + 30);

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
   .filter(n => n.type === 'CHILD' || n.type === 'SUBCHILD')
   .map(n => n.objectApiName);
  if (relatedObjects.length > 0) {
   const counts = this.canvasNodes
    .filter(n => n.type === 'CHILD' || n.type === 'SUBCHILD')
    .map(n => ({
     objectApiName: String(n.objectApiName),
     totalCount: Number(n.count) || 0
    }));
   this.buildCanvasNodes(counts, relatedObjects);
   this.buildLinks();
  }
 }

 /* ================= STEP 3 CORE: HIERARCHY DISTRIBUTION ENGINE ================= */

   /* ================= STEP 3 CORE: HIERARCHY DISTRIBUTION ENGINE ================= */
    buildCanvasNodes(counts, objectList) {
        this.logStep("BUILD CANVAS START", { anchor: this.selectedObjectApi });
        console.group("%cGRAPH ENGINE :: LINKS & PARENT FIX", "color:white;background:#16325c;padding:4px");

        const nodeW = 120;
        const gapX = 240; 
        const gapY = 180; 
        const canvasMid = (this.canvasWidth || 1200) / 2;
        let nodes = [];

        // ---------------------------------------------------------
        // 1. POSITION ROW 1 (LEVEL 0): Dynamic Parent
        // ---------------------------------------------------------
        const validParentNode = this.getValidParent();
        let parentNodeIdForLinks = null;

        if (validParentNode) {
            parentNodeIdForLinks = validParentNode.nodeId; // 🔥 STORE ID FOR ROW 2 LINKS
            nodes.push({ 
                ...validParentNode, 
                name: validParentNode.nodeId, 
                x: canvasMid - nodeW / 2, 
                y: 50, 
                type: "PARENT", 
                icon: this.getIconName(validParentNode.objectApiName) 
            });
        }

        // ---------------------------------------------------------
        // 2. POSITION ROW 2 (LEVEL 1): Anchor's Direct Children
        // ---------------------------------------------------------
        const r2Nodes = this.hierarchyNodes.filter(n => n.level === 1 && objectList.includes(n.objectApiName));
        const r2TotalWidth = (r2Nodes.length - 1) * gapX;
        const r2StartX = canvasMid - (r2TotalWidth / 2) - (nodeW / 2);

        r2Nodes.forEach((c, i) => {
            const countData = counts.find(x => x.objectApiName === c.objectApiName);
            let currentX = r2StartX + (i * gapX);
            let currentY = 50 + gapY;

            nodes.push({
                ...c, 
                name: c.nodeId, 
                parentNodeId: parentNodeIdForLinks, // 🔥 FIX: FORCES LINE CONNECTION TO ROW 1
                x: currentX, 
                y: currentY,
                type: "CHILD", 
                count: countData ? countData.totalCount : 0,
                icon: this.getIconName(c.objectApiName)
            });

            // ---------------------------------------------------------
            // 3. POSITION ROW 3 (LEVEL 2): Sub-children alignment
            // ---------------------------------------------------------
            const r3NodesForParent = this.hierarchyNodes.filter(n => 
                n.level === 2 && 
                n.parentNodeId === c.nodeId && 
                objectList.includes(n.objectApiName)
            );

            r3NodesForParent.forEach((s, j) => {
                const horizontalSubOffset = (j - (r3NodesForParent.length - 1) / 2) * 140;

                nodes.push({
                    ...s, 
                    name: s.nodeId, 
                    x: currentX + horizontalSubOffset, 
                    y: currentY + gapY,
                    type: "SUBCHILD", 
                    icon: this.getIconName(s.objectApiName)
                });
            });
        });

        this.canvasNodes = nodes;
        this.logCanvasNodes(nodes);
        console.groupEnd();
    }

 buildLinks() {
        this.logStep("BUILD LINKS START");
        const links = [];
        const nodeHalf = 60;
        const nodeHeight = 60;

        const drawLine = (s, t) => {
            const midY = (s.y + nodeHeight + t.y) / 2;
            return `M ${s.x + nodeHalf} ${s.y + nodeHeight} V ${midY} H ${t.x + nodeHalf} V ${t.y}`;
        };

        this.canvasNodes.forEach(node => {
            // Find Parent by precise matching
            if (node.parentNodeId) {
                const parentNode = this.canvasNodes.find(n => n.nodeId === node.parentNodeId);
                
                if (parentNode) {
                    links.push({ 
                        id: "link-" + node.nodeId, 
                        d: drawLine(parentNode, node) 
                    });
                }
            }
        });

        this.canvasLinks = links;
        this.logLinks(links);
    }
 getValidParent() {
        // 1. Scan hierarchy nodes for Level 0 (Dynamic Discovery)
        for (let node of this.hierarchyNodes) {
            if (node.level === 0) {
                this.logStep("PARENT DEBUG - Found Level 0", node.objectApiName);
                return node;
            }
        }

        // 2. Fallback to selection metadata
        if (this.parentObjectApis && this.parentObjectApis.length > 0) {
            const pApi = this.parentObjectApis[0];
            this.logStep("PARENT DEBUG - Fallback Used", pApi);
            return { 
                objectApiName: pApi, 
                label: pApi + ' (Parent)', 
                nodeId: 'R1-' + pApi,
                level: 0 
            };
        }
        return null;
    }

 renderedCallback() {
  this.logStep("RENDERED CALLBACK");
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
  this.logCanvasNodes(this.canvasNodes);
 }

 debugSection(title) {
  console.group('GRAPH DEBUG :: ' + title);
 }
 debugEnd() {
  console.groupEnd();
 }

 debugData(label, data) {
  if (Array.isArray(data)) {
   console.log(label + ' (Array size = ' + data.length + ')');
   console.table(data);
  } else {
   console.log(label, data);
  }
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
  this.logStep("NODE CLICKED", event.currentTarget.dataset.name);
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
  if (node.type === 'CHILD' || node.type === 'SUBCHILD') {
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
   if (!this.parentObjectApis || this.parentObjectApis.length === 0) {
    this.dispatchEvent(
     new ShowToastEvent({
      title: 'No Parent Found',
      message: 'This record does not have a parent relation.',
      variant: 'info'
     })
    );
    return;
   }
   const parentApi = this.parentObjectApis[0];
   fetchAndShow(
    parentApi,
    parentApi + ' (Parent Record)'
   );
  } else {
   if (!node.count || node.count === 0) return;
   fetchAndShow(node.objectApiName, node.objectApiName + ' (Related Records)');
  }
 }
 /* ================= PANEL ACTIONS ================= */
 closeRightPanel() {
  this.rightPanelVisible = false;
  this.activeCanvasNode = null;
 }
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
  this.parentObjectApis = [];
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
  /* LEFT PANEL RESET */
  this.hierarchyNodes = [];
  this.filteredHierarchyNodes = null;
  this.expandedNodeIds = new Set();
  this.relatedObjectSearchKey = '';

 }
}