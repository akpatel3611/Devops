import { LightningElement, api } from "lwc";

import { loadSectionData } from "c/metadataService";

export default class SectionPlaceholder extends LightningElement {
  _objectName;

  _sectionId;

  @api sectionLabel;

  isLoading = false;

  error;

  data;

  searchTerm = "";

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    this._objectName = value;
    this.searchTerm = "";
    this.loadData();
  }

  @api
  get sectionId() {
    return this._sectionId;
  }

  set sectionId(value) {
    this._sectionId = value;
    this.searchTerm = "";
    this.loadData();
  }

  get isTableSection() {
    return this.data?.type === "table";
  }

  get hasDataTable() {
    return this.isTableSection;
  }

  get tableClass() {
    const baseClasses =
      "metadata-table slds-table slds-table_cell-buffer slds-table_bordered slds-no-row-hover";
    return this._sectionId === "buttonsLinksActions"
      ? `${baseClasses} metadata-table_buttons-links-actions`
      : baseClasses;
  }

  get hasMessage() {
    return this.data?.type === "message" && Boolean(this.messageText);
  }

  get messageText() {
    return this.data?.message || "";
  }

  get tableColumns() {
    return this.data?.columns || [];
  }

  get showSearch() {
    return this.isTableSection;
  }

  get columnCount() {
    return this.tableColumns.length || 1;
  }

  get hasTableRows() {
    return this.filteredRows.length > 0;
  }

  get rowCountLabel() {
    const count = this.filteredRows.length;
    return `${count} item${count === 1 ? "" : "s"}`;
  }

  get emptyStateMessage() {
    return this.searchTerm.trim()
      ? "No items match the current filter."
      : "No metadata rows available for this section.";
  }

  get filteredRows() {
    const rows = this.data?.rows || [];
    const normalizedSearch = this.searchTerm.trim().toLowerCase();

    if (!normalizedSearch) {
      return rows;
    }

    const searchableColumnKeys = this.tableColumns
      .map((column) => column.key)
      .filter((key) => key !== "editAction");

    return rows.filter((row) =>
      searchableColumnKeys.some((columnKey) =>
        String(row[columnKey] ?? "")
          .toLowerCase()
          .includes(normalizedSearch)
      )
    );
  }

  get tableRows() {
    return this.filteredRows.map((row, index) => ({
      _key: `${this._sectionId}-${index}`,
      cells: this.tableColumns.map((column) =>
        this.buildCell(column, row, index)
      )
    }));
  }

  buildCell(column, row, index) {
    const isEditAction =
      this._sectionId === "buttonsLinksActions" && column.key === "editAction";
    const href = isEditAction ? null : this.buildCellHref(column.key, row);
    const canRunAction = isEditAction && Boolean(row.canEdit && row.editUrl);

    return {
      key: `${column.key}-${index}`,
      value: isEditAction ? "Edit" : row[column.key],
      href,
      isActionCell: isEditAction,
      actionUrl: isEditAction ? row.editUrl || null : null,
      actionClass: canRunAction
        ? "action-button"
        : "action-button action-button_disabled",
      isDisabled: isEditAction && !canRunAction,
      linkClass: "table-link",
      textClass: ""
    };
  }

  handleActionClick(event) {
    const actionUrl = event.currentTarget?.dataset?.url;

    if (!actionUrl) {
      return;
    }

    window.open(actionUrl, "_blank", "noopener,noreferrer");
  }

  buildCellHref(columnKey, row) {
    const sectionUrl = this.getSectionBaseUrl();
    const fieldUrl = this.getFieldUrl(
      row.apiName || row.sourceField || row.name
    );

    if (
      this._sectionId === "lightningRecordPages" &&
      columnKey === "MasterLabel" &&
      row.Id
    ) {
      return `/lightning/setup/ObjectManager/${this._objectName}/LightningRecordPages/view`;
    }

    if (
      ["relatedLookupFilters", "hierarchyColumns"].includes(this._sectionId) &&
      ["label", "apiName"].includes(columnKey)
    ) {
      return fieldUrl;
    }

    if (
      this._sectionId === "searchLayouts" &&
      ["label", "apiName", "sourceField"].includes(columnKey)
    ) {
      return fieldUrl;
    }

    if (
      this._sectionId === "fieldSets" &&
      ["label", "developerName"].includes(columnKey)
    ) {
      return sectionUrl;
    }

    if (
      ["pageLayouts", "compactLayouts", "listViewButtonLayout"].includes(
        this._sectionId
      ) &&
      ["label", "name", "relatedList"].includes(columnKey)
    ) {
      return sectionUrl;
    }

    if (
      this._sectionId === "lightningRecordPages" &&
      ["MasterLabel", "DeveloperName"].includes(columnKey)
    ) {
      return sectionUrl;
    }

    if (
      this._sectionId === "validationRules" &&
      ["label"].includes(columnKey)
    ) {
      return sectionUrl;
    }

    return null;
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  getFieldUrl(fieldApiName) {
    if (!fieldApiName || fieldApiName === "N/A") {
      return null;
    }

    return `/lightning/setup/ObjectManager/${this._objectName}/FieldsAndRelationships/${fieldApiName}/view`;
  }

  getSectionBaseUrl() {
    const sectionRoutes = {
      pageLayouts: "PageLayouts",
      lightningRecordPages: "LightningRecordPages",
      buttonsLinksActions: "ButtonsLinksActions",
      compactLayouts: "CompactLayouts",
      fieldSets: "FieldSets",
      validationRules: "ValidationRules",
      relatedLookupFilters: "FieldsAndRelationships",
      searchLayouts: "SearchLayouts",
      listViewButtonLayout: "ButtonsLinksActions",
      hierarchyColumns: "FieldsAndRelationships",
      scopingRules: "ScopingRules"
    };

    const route = sectionRoutes[this._sectionId];

    return route
      ? `/lightning/setup/ObjectManager/${this._objectName}/${route}/view`
      : null;
  }

  async loadData() {
    if (!this._objectName || !this._sectionId) {
      return;
    }

    this.isLoading = true;
    this.data = undefined;
    this.error = undefined;

    try {
      this.data = await loadSectionData(this._sectionId, this._objectName);
    } catch (error) {
      this.data = undefined;
      this.error = error;
      console.error(error);
    } finally {
      this.isLoading = false;
    }
  }
}