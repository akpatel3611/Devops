import { LightningElement, api, wire } from "lwc";

import getObjectDetails from "@salesforce/apex/ObjectManagerController.getObjectDetails";

export default class SectionDetails extends LightningElement {
  _objectName;

  details;

  error;

  searchTerm = "";

  isExportModalOpen = false;

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    this._objectName = value;
    this.details = undefined;
    this.error = undefined;
    this.searchTerm = "";
    this.isExportModalOpen = false;
  }

  get hasDetails() {
    return Boolean(this.details);
  }

  get hasVisibleDetails() {
    return this.filteredDetailRows.length > 0;
  }

  get detailRows() {
    if (!this.details) {
      return [];
    }

    return [
      { label: "Object Label", value: this.details.label },
      { label: "Plural Label", value: this.details.pluralLabel },
      { label: "API Name", value: this.details.apiName },
      { label: "Key Prefix", value: this.details.keyPrefix || "N/A" },
      { label: "Is Custom", value: this.formatBoolean(this.details.isCustom) },
      {
        label: "Is Queryable",
        value: this.formatBoolean(this.details.isQueryable)
      },
      {
        label: "Is Createable",
        value: this.formatBoolean(this.details.isCreateable)
      },
      {
        label: "Is Updateable",
        value: this.formatBoolean(this.details.isUpdateable)
      },
      {
        label: "Is Deletable",
        value: this.formatBoolean(this.details.isDeletable)
      }
    ];
  }

  get filteredDetailRows() {
    const normalizedSearch = this.searchTerm.trim().toLowerCase();

    if (!normalizedSearch) {
      return this.detailRows;
    }

    return this.detailRows.filter(
      (row) =>
        String(row.label || "")
          .toLowerCase()
          .includes(normalizedSearch) ||
        String(row.value || "")
          .toLowerCase()
          .includes(normalizedSearch)
    );
  }

  get detailColumns() {
    const rows = this.filteredDetailRows;
    const midpoint = Math.ceil(rows.length / 2);

    return [
      {
        key: "left",
        rows: rows.slice(0, midpoint)
      },
      {
        key: "right",
        rows: rows.slice(midpoint)
      }
    ];
  }

  @wire(getObjectDetails, { objectName: "$_objectName" })
  wiredDetails({ data, error }) {
    if (data) {
      this.details = data;
      this.error = undefined;
    } else if (error) {
      this.details = undefined;
      this.error = error;
      console.error(error);
    }
  }

  formatBoolean(value) {
    return value ? "True" : "False";
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  openExportModal() {
    this.isExportModalOpen = true;
  }

  closeExportModal() {
    this.isExportModalOpen = false;
  }
}