import { LightningElement, api, wire } from "lwc";

import getAllObjects from "@salesforce/apex/ObjectManagerController.getAllObjects";

export default class ObjectDropdown extends LightningElement {
  allObjects = [];

  filteredObjects = [];

  isOpen = false;

  selectedLabel = "Select Object";

  selectedTypeLabel = "";

  _selectedObjectLabel;

  _selectedObjectApiName;

  handleDocumentClickBound = this.handleDocumentClick.bind(this);

  @api
  get selectedObjectApiName() {
    return this._selectedObjectApiName;
  }

  set selectedObjectApiName(value) {
    this._selectedObjectApiName = value;
    this.syncSelectedDisplay();
  }

  @api
  get selectedObjectLabel() {
    return this._selectedObjectLabel;
  }

  set selectedObjectLabel(value) {
    this._selectedObjectLabel = value;
    this.syncSelectedDisplay();
  }

  get hasFilteredObjects() {
    return this.filteredObjects.length > 0;
  }

  get hasSelection() {
    return Boolean(this.selectedTypeLabel);
  }

  get dropdownArrowClass() {
    return this.isOpen
      ? "dropdown-arrow dropdown-arrow--open"
      : "dropdown-arrow";
  }

  connectedCallback() {
    document.addEventListener("click", this.handleDocumentClickBound);
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.handleDocumentClickBound);
  }

  @wire(getAllObjects)
  wiredObjects({ error, data }) {
    if (data) {
      this.allObjects = data;
      this.filteredObjects = data;
      this.syncSelectedDisplay();
    } else if (error) {
      console.error("Object Load Error:", error);
    }
  }

  toggleDropdown(event) {
    event.stopPropagation();
    this.isOpen = !this.isOpen;

    if (this.isOpen) {
      this.filteredObjects = [...this.allObjects];
    }
  }

  handleSearch(event) {
    event.stopPropagation();
    const searchKey = event.target.value.toLowerCase();

    this.filteredObjects = this.allObjects.filter((objectInfo) => {
      const label = objectInfo.label.toLowerCase();
      const apiName = objectInfo.apiName.toLowerCase();
      const typeLabel = objectInfo.typeLabel.toLowerCase();

      return (
        label.includes(searchKey) ||
        apiName.includes(searchKey) ||
        typeLabel.includes(searchKey)
      );
    });
  }

  selectObject(event) {
    event.stopPropagation();
    const objectName = event.currentTarget.dataset.name;
    const selectedObject = this.allObjects.find(
      (objectInfo) => objectInfo.apiName === objectName
    );

    this.setSelection(selectedObject);
    this.isOpen = false;

    this.dispatchEvent(
      new CustomEvent("objectselect", {
        detail: objectName
      })
    );
  }

  handleDocumentClick(event) {
    if (!this.isOpen) {
      return;
    }

    const clickPath = event.composedPath();

    if (!clickPath.includes(this.template.host)) {
      this.isOpen = false;
    }
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  setSelection(selectedObject) {
    if (!selectedObject) {
      this.selectedLabel = "Select Object";
      this.selectedTypeLabel = "";
      return;
    }

    this.selectedLabel = selectedObject.label;
    this.selectedTypeLabel = selectedObject.typeLabel;
  }

  syncSelectedDisplay() {
    const selectedObject = this.allObjects.find(
      (objectInfo) =>
        objectInfo.apiName === this._selectedObjectApiName ||
        objectInfo.label === this._selectedObjectApiName
    );

    if (selectedObject) {
      this._selectedObjectApiName = selectedObject.apiName;
      this._selectedObjectLabel = selectedObject.label;
      this.setSelection(selectedObject);
      return;
    }

    if (this._selectedObjectApiName) {
      this.selectedLabel =
        this._selectedObjectLabel || this._selectedObjectApiName;
      this.selectedTypeLabel = "";
      return;
    }

    this.setSelection(undefined);
  }
}