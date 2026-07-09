import { LightningElement, api, wire } from "lwc";

import getRecordTypes from "@salesforce/apex/ObjectManagerController.getRecordTypes";

export default class SectionRecordTypes extends LightningElement {
  _objectName;

  recordTypes = [];

  error;

  searchTerm = "";

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    this._objectName = value;
    this.recordTypes = [];
    this.error = undefined;
    this.searchTerm = "";
  }

  get hasRecordTypes() {
    return this.filteredRecordTypes.length > 0;
  }

  get recordTypeCountLabel() {
    const count = this.filteredRecordTypes.length;
    return `${count} record type${count === 1 ? "" : "s"}`;
  }

  get normalizedRecordTypes() {
    return this.filteredRecordTypes.map((recordType) => ({
      ...recordType,
      activeLabel: recordType.isActive ? "Yes" : "No",
      defaultLabel: recordType.isDefault ? "Yes" : "No",
      recordTypeUrl: this.buildRecordTypeUrl(recordType)
    }));
  }

  get filteredRecordTypes() {
    const normalizedSearch = this.searchTerm.trim().toLowerCase();

    if (!normalizedSearch) {
      return this.recordTypes;
    }

    return this.recordTypes.filter((recordType) => {
      const activeLabel = recordType.isActive ? "yes" : "no";
      const defaultLabel = recordType.isDefault ? "yes" : "no";

      return (
        String(recordType.name || "")
          .toLowerCase()
          .includes(normalizedSearch) ||
        String(recordType.developerName || "")
          .toLowerCase()
          .includes(normalizedSearch) ||
        activeLabel.includes(normalizedSearch) ||
        defaultLabel.includes(normalizedSearch)
      );
    });
  }

  buildRecordTypeUrl(recordType) {
    if (recordType.id) {
      return `/lightning/setup/ObjectManager/${this._objectName}/RecordTypes/${recordType.id}/view`;
    }

    return `/lightning/setup/ObjectManager/${this._objectName}/RecordTypes/view`;
  }

  @wire(getRecordTypes, { objectName: "$_objectName" })
  wiredRecordTypes({ data, error }) {
    if (data) {
      this.recordTypes = data;
      this.error = undefined;
    } else if (error) {
      this.recordTypes = [];
      this.error = error;
      console.error(error);
    }
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }
}