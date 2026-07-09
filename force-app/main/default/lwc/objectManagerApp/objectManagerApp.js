import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import deleteObject from "@salesforce/apex/ObjectManagerController.deleteObject";
import getAllObjects from "@salesforce/apex/ObjectManagerController.getAllObjects";
import searchMetadata from "@salesforce/apex/ObjectManagerController.searchMetadata";

const SECTIONS = [
  { id: "details", label: "Details" },
  { id: "fieldsRelationships", label: "Fields & Relationships" },
  { id: "flows", label: "Flows" },
  { id: "pageLayouts", label: "Page Layouts" },
  { id: "lightningRecordPages", label: "Lightning Record Pages" },
  { id: "buttonsLinksActions", label: "Buttons, Links, and Actions" },
  { id: "compactLayouts", label: "Compact Layouts" },
  { id: "fieldSets", label: "Field Sets" },
  { id: "objectLimits", label: "Object Limits" },
  { id: "recordTypes", label: "Record Types" },
  { id: "validationRules", label: "Validation Rules" },
  { id: "relatedLookupFilters", label: "Related Lookup Filters" },
  { id: "searchLayouts", label: "Search Layouts" },
  { id: "listViewButtonLayout", label: "List View Button Layout" },
  { id: "hierarchyColumns", label: "Hierarchy Columns" },
  { id: "scopingRules", label: "Scoping Rules" }
];

const GLOBAL_SEARCH_DEBOUNCE_MS = 300;

export default class ObjectManagerApp extends LightningElement {
  allObjects = [];

  objectBrowserSearch = "";

  selectedObject;

  selectedObjectLabel = "";

  activeSection = "details";

  globalSearchTerm = "";

  globalSearchResults = [];

  globalSearchError;

  fieldSearchTerm = "";

  isExportModalOpen = false;

  exportModalObjectId;

  isImpactModalOpen = false;

  impactTarget;

  globalSearchTimeout;

  latestGlobalSearchRequest = 0;

  wiredObjectsResult;

  handleDocumentClickBound = this.handleDocumentClick.bind(this);

  connectedCallback() {
    document.addEventListener("click", this.handleDocumentClickBound);
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.handleDocumentClickBound);
    this.clearGlobalSearchTimeout();
  }

  @wire(getAllObjects)
  wiredObjects(response) {
    this.wiredObjectsResult = response;
    const { data, error } = response;

    if (data) {
      this.allObjects = data;
    } else if (error) {
      console.error(error);
    }
  }

  get hasSelectedObject() {
    return Boolean(this.selectedObject);
  }

  get hasObjects() {
    return this.filteredObjectRows.length > 0;
  }

  get objectCountLabel() {
    const count = this.filteredObjectRows.length;
    return `${count} object${count === 1 ? "" : "s"}`;
  }

  get appShellClass() {
    return this.hasSelectedObject
      ? "app-shell app-shell_selected"
      : "app-shell app-shell_browser";
  }

  get hasGlobalSearchResults() {
    return this.normalizedGlobalSearchResults.length > 0;
  }

  get normalizedGlobalSearchResults() {
    return this.globalSearchResults.map((result) => {
      const matchedObject = this.allObjects.find(
        (objectInfo) =>
          objectInfo.apiName === result.objectApiName ||
          objectInfo.apiName === result.objectName ||
          objectInfo.label === result.objectLabel ||
          objectInfo.label === result.objectName
      );

      const objectApiName =
        matchedObject?.apiName || result.objectApiName || result.objectName;

      const objectLabel =
        matchedObject?.label || result.objectLabel || result.objectName;

      return {
        ...result,
        objectApiName,
        objectLabel,
        key: `${objectApiName}-${result.fieldName}`
      };
    });
  }

  get showGlobalSearchDropdown() {
    return this.globalSearchTerm.trim().length >= 2 && this.isGlobalSearchOpen;
  }

  get filteredObjectRows() {
    const searchKey = this.objectBrowserSearch.trim().toLowerCase();

    return this.allObjects
      .filter((objectInfo) => {
        if (!searchKey) {
          return true;
        }

        return (
          objectInfo.label.toLowerCase().includes(searchKey) ||
          objectInfo.apiName.toLowerCase().includes(searchKey) ||
          objectInfo.typeLabel.toLowerCase().includes(searchKey)
        );
      })
      .map((objectInfo) => ({
        ...objectInfo,
        key: objectInfo.apiName,
        deleteDisabled: !objectInfo.isCustom
      }));
  }

  get computedSections() {
    return this.sections.map((section) => ({
      ...section,
      itemClass:
        section.id === this.activeSection
          ? "section-item section-item_active"
          : "section-item"
    }));
  }

  get activeSectionLabel() {
    return this.sections.find((section) => section.id === this.activeSection)
      ?.label;
  }

  get isDetailsSection() {
    return this.activeSection === "details";
  }

  get isFieldsSection() {
    return this.activeSection === "fieldsRelationships";
  }

  get isRecordTypesSection() {
    return this.activeSection === "recordTypes";
  }

  get isPlaceholderSection() {
    return (
      this.hasSelectedObject &&
      !this.isDetailsSection &&
      !this.isFieldsSection &&
      !this.isRecordTypesSection
    );
  }

  get isGlobalSearchOpen() {
    return (
      this.globalSearchTerm.trim().length >= 2 &&
      (this.hasGlobalSearchResults || Boolean(this.globalSearchError))
    );
  }

  sections = SECTIONS;

  handleCreate() {
    window.open("/lightning/setup/ObjectManager/new", "_blank");
  }

  handleSectionClick(event) {
    this.activeSection = event.currentTarget.dataset.sectionId;
  }

  handleObjectSelect(event) {
    this.selectedObject = event.detail;
    this.selectedObjectLabel = this.getObjectLabel(this.selectedObject);
    this.fieldSearchTerm = "";
  }

  handleBrowseSearch(event) {
    this.objectBrowserSearch = event.target.value;
  }

  handleObjectRowSelect(event) {
    this.selectedObject = event.currentTarget.dataset.objectName;
    this.selectedObjectLabel =
      event.currentTarget.dataset.objectLabel ||
      this.getObjectLabel(this.selectedObject);
    this.fieldSearchTerm = "";
  }

  handleBackToObjects() {
    this.selectedObject = undefined;
    this.selectedObjectLabel = "";
    this.activeSection = "details";
    this.fieldSearchTerm = "";
  }

  handleObjectAction(event) {
    event.stopPropagation();

    const action = event.detail.value;
    const objectApiName = event.currentTarget.dataset.objectId;
    const objectLabel = event.currentTarget.dataset.objectLabel;

    if (action === "export") {
      this.openObjectExport(objectApiName);
      return;
    }

    if (action === "delete") {
      this.openObjectDelete(objectApiName, objectLabel);
    }
  }

  handleCloseExportModal() {
    this.isExportModalOpen = false;
    this.exportModalObjectId = undefined;
  }

  openObjectExport(objectApiName) {
    this.exportModalObjectId = objectApiName;
    this.isExportModalOpen = true;
  }

  openObjectDelete(objectApiName, objectLabel) {
    const objectInfo = (this.allObjects || []).find(
      (objectItem) => objectItem.apiName === objectApiName
    );

    this.impactTarget = {
      type: "object",
      id: objectApiName,
      name: objectLabel || objectInfo?.label || objectApiName,
      apiName: objectApiName
    };
    this.isImpactModalOpen = true;
  }

  handleCloseImpactModal() {
    this.isImpactModalOpen = false;
    this.impactTarget = undefined;
  }

  async handleConfirmObjectDelete() {
    const objectApiName = this.impactTarget?.apiName;

    if (!objectApiName) {
      return;
    }

    try {
      await deleteObject({
        objectName: objectApiName
      });

      await refreshApex(this.wiredObjectsResult);

      if (this.selectedObject === objectApiName) {
        this.handleBackToObjects();
      }

      this.showToast(
        "Object deleted",
        `${objectApiName} was deleted successfully.`,
        "success"
      );
      this.handleCloseImpactModal();
    } catch (error) {
      console.error(error);
      this.showToast("Delete failed", this.reduceError(error), "error");
    }
  }

  handleGlobalSearchInput(event) {
    event.stopPropagation();
    this.globalSearchTerm = event.target.value;
    this.globalSearchError = undefined;
    this.clearGlobalSearchTimeout();

    if (this.globalSearchTerm.trim().length < 2) {
      this.cancelPendingGlobalSearch();
      this.globalSearchResults = [];
      return;
    }

    const searchTerm = this.globalSearchTerm.trim();
    const requestId = ++this.latestGlobalSearchRequest;

    // Debounce server calls so global search doesn't hit Apex on every keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.globalSearchTimeout = window.setTimeout(() => {
      searchMetadata({ keyword: searchTerm })
        .then((results) => {
          if (
            requestId !== this.latestGlobalSearchRequest ||
            searchTerm !== this.globalSearchTerm.trim()
          ) {
            return;
          }

          this.globalSearchResults = results;
          this.globalSearchError = undefined;
        })
        .catch((error) => {
          if (requestId !== this.latestGlobalSearchRequest) {
            return;
          }

          this.globalSearchResults = [];
          this.globalSearchError = "Unable to load search results.";
          console.error(error);
        });
    }, GLOBAL_SEARCH_DEBOUNCE_MS);
  }

  handleSearchResultSelect(event) {
    event.stopPropagation();
    this.selectedObject = event.currentTarget.dataset.objectApiName;
    this.selectedObjectLabel =
      event.currentTarget.dataset.objectLabel ||
      this.getObjectLabel(this.selectedObject);
    this.activeSection = "fieldsRelationships";
    this.fieldSearchTerm = event.currentTarget.dataset.fieldName;
    this.globalSearchTerm = "";
    this.globalSearchResults = [];
    this.cancelPendingGlobalSearch();
  }

  getObjectLabel(objectApiName) {
    return (
      this.allObjects.find((objectInfo) => objectInfo.apiName === objectApiName)
        ?.label || objectApiName
    );
  }

  handleDocumentClick(event) {
    const clickPath = event.composedPath();

    if (!clickPath.includes(this.template.host)) {
      this.globalSearchTerm = "";
      this.globalSearchResults = [];
      this.globalSearchError = undefined;
      this.cancelPendingGlobalSearch();
    }
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  clearGlobalSearchTimeout() {
    if (this.globalSearchTimeout) {
      window.clearTimeout(this.globalSearchTimeout);
      this.globalSearchTimeout = undefined;
    }
  }

  cancelPendingGlobalSearch() {
    this.latestGlobalSearchRequest += 1;
    this.clearGlobalSearchTimeout();
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }

    if (error?.body?.message) {
      return error.body.message;
    }

    if (error?.message) {
      return error.message;
    }

    return "Unknown error";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }
}