import { LightningElement, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getObjects from "@salesforce/apex/BulkMetadataService.getObjects";
import getObjectFields from "@salesforce/apex/BulkMetadataService.getObjectFields";
import deploySchema from "@salesforce/apex/BulkMetadataService.deploySchema";
import insertRecords from "@salesforce/apex/BulkMetadataService.insertRecords";
import getProfiles from "@salesforce/apex/BulkMetadataService.getProfiles";
import assignProfileFls from "@salesforce/apex/BulkMetadataService.assignProfileFls";

export default class BulkMetadataCreator extends LightningElement {
  @track objectOptions = [];
  @track objectMode = "existing";
  @track selectedExistingObject = "";
  @track existingObjectSearchTerm = "";
  @track showExistingObjectDropdown = false;
  @track newObject = {
    label: "",
    pluralLabel: "",
    apiName: "",
    nameFieldLabel: "Name",
    nameFieldType: "Text",
    theme: "Custom67: Gear"
  };

  @track fieldRows = [];
  @track recordTargetObject = "";
  @track recordTargetObjectSearchTerm = "";
  @track showRecordTargetObjectDropdown = false;
  @track activeObjectFields = [];
  @track recordRows = [];
  @track deploymentResult = null;
  @track deploymentFilter = "all";
  @track isDeploymentModalOpen = false;

  isLoading = false;
  wiredObjectsResult;
  suppressExistingObjectBlur = false;
  suppressRecordTargetObjectBlur = false;
  suppressFieldBlurKey = null;
  suppressProfileBlur = false;

  @track flsEnabled = false;
  @track profileOptions = [];
  @track selectedProfiles = [];
  @track profileSearchTerm = "";
  @track showProfileDropdown = false;
  @track flsResults = [];

  objectModeOptions = [
    { label: "Existing Object", value: "existing" },
    { label: "Create New Object", value: "new" }
  ];

  nameFieldTypeOptions = [
    { label: "Text", value: "Text" },
    { label: "Auto Number", value: "AutoNumber" }
  ];

  themeOptions = [
    { label: "Gear (Blue)", value: "Custom67: Gear" },
    { label: "Heart (Red)", value: "Custom1: Heart" },
    { label: "Star (Yellow)", value: "Custom11: Star" },
    { label: "People (Green)", value: "Custom15: People" },
    { label: "Laptop (Grey)", value: "Custom27: Laptop" },
    { label: "Wrench (Orange)", value: "Custom19: Wrench" },
    { label: "Building (Brown)", value: "Custom24: Building" },
    { label: "Trophy (Gold)", value: "Custom48: Trophy" },
    { label: "Cash (Green)", value: "Custom41: Cash" }
  ];

  dataTypeOptions = [
    { label: "Auto Number", value: "AutoNumber" },
    { label: "Formula", value: "Formula" },
    { label: "Roll-Up Summary", value: "Summary" },
    { label: "Lookup Relationship", value: "Lookup" },
    { label: "External Lookup Relationship", value: "ExternalLookup" },
    { label: "Checkbox", value: "Checkbox" },
    { label: "Currency", value: "Currency" },
    { label: "Date", value: "Date" },
    { label: "Date/Time", value: "DateTime" },
    { label: "Email", value: "Email" },
    { label: "Geolocation", value: "Location" },
    { label: "Number", value: "Number" },
    { label: "Percent", value: "Percent" },
    { label: "Phone", value: "Phone" },
    { label: "Picklist", value: "Picklist" },
    { label: "Picklist (Multi-Select)", value: "MultiselectPicklist" },
    { label: "Text", value: "Text" },
    { label: "Text Area", value: "TextArea" },
    { label: "Text Area (Long)", value: "LongTextArea" },
    { label: "Text Area (Rich)", value: "Html" },
    { label: "Text (Encrypted)", value: "EncryptedText" },
    { label: "Time", value: "Time" },
    { label: "URL", value: "Url" }
  ];

  formulaTypeOptions = [
    { label: "Checkbox", value: "Checkbox" },
    { label: "Currency", value: "Currency" },
    { label: "Date", value: "Date" },
    { label: "Date/Time", value: "DateTime" },
    { label: "Number", value: "Number" },
    { label: "Percent", value: "Percent" },
    { label: "Text", value: "Text" },
    { label: "Time", value: "Time" }
  ];

  deploymentFilterOptions = [
    { label: "All Rows", value: "all" },
    { label: "Failed Only", value: "failed" }
  ];

  @wire(getObjects)
  wiredObjects(result) {
    this.wiredObjectsResult = result;
    if (result.data) {
      this.objectOptions = result.data;
    } else if (result.error) {
      this.showToast(
        "Error",
        "Failed to retrieve Salesforce objects: " + result.error.body.message,
        "error"
      );
    }
  }

  @wire(getProfiles)
  wiredProfiles({ data }) {
    if (data) {
      this.profileOptions = data;
    }
    // Non-critical — silently ignore errors; FLS section won't show profiles if load fails
  }

  get isExistingObjectMode() {
    return this.objectMode === "existing";
  }

  get isNewObjectMode() {
    return this.objectMode === "new";
  }

  get isSaveDisabled() {
    return !this.recordTargetObject || this.recordRows.length === 0;
  }

  get filteredExistingObjectOptions() {
    if (!this.existingObjectSearchTerm) {
      return this.objectOptions;
    }
    const term = this.existingObjectSearchTerm.toLowerCase();
    return this.objectOptions.filter(
      (opt) =>
        opt.label.toLowerCase().includes(term) ||
        opt.value.toLowerCase().includes(term)
    );
  }

  get filteredRecordTargetObjectOptions() {
    if (!this.recordTargetObjectSearchTerm) {
      return this.objectOptions;
    }
    const term = this.recordTargetObjectSearchTerm.toLowerCase();
    return this.objectOptions.filter(
      (opt) =>
        opt.label.toLowerCase().includes(term) ||
        opt.value.toLowerCase().includes(term)
    );
  }

  get processedFieldRows() {
    return this.fieldRows.map((row, index) => {
      const term = (row.relatedObjectSearchTerm || "").toLowerCase();
      const filteredOptions = this.objectOptions.filter(
        (opt) =>
          opt.label.toLowerCase().includes(term) ||
          opt.value.toLowerCase().includes(term)
      );

      const dataTypeOptionsWithSelection = this.dataTypeOptions.map((opt) => ({
        ...opt,
        isSelected: opt.value === row.dataType
      }));

      const formulaTypeOptionsWithSelection = this.formulaTypeOptions.map((opt) => ({
        ...opt,
        isSelected: opt.value === row.formulaType
      }));

      const resultRow = this.getDeploymentRowResult(row.key);
      const statusClass = resultRow
        ? resultRow.success
          ? "row-status row-status-success"
          : "row-status row-status-error"
        : "row-status";

      return {
        ...row,
        rowNumber: index + 1,
        filteredOptions,
        dataTypeOptionsWithSelection,
        formulaTypeOptionsWithSelection,
        isNoFormulaTypeSelected: !row.formulaType,
        resultStatus: resultRow ? (resultRow.success ? "Success" : resultRow.status) : "",
        resultMessage: resultRow ? resultRow.message : "",
        hasResult: Boolean(resultRow),
        statusClass
      };
    });
  }

  get deploymentSummaryLabel() {
    if (!this.deploymentResult) {
      return "";
    }
    return `${this.deploymentResult.successCount} succeeded, ${this.deploymentResult.failureCount} failed`;
  }

  get hasObjectResult() {
    return Boolean(this.deploymentResult && this.deploymentResult.objectResult);
  }

  get objectResultClass() {
    if (!this.deploymentResult || !this.deploymentResult.objectResult) {
      return "status-pill";
    }
    return this.deploymentResult.objectResult.success
      ? "status-pill status-pill-success"
      : "status-pill status-pill-error";
  }

  get filteredDeploymentRows() {
    if (!this.deploymentResult) {
      return [];
    }

    const rows =
      this.deploymentFilter === "failed"
        ? this.deploymentResult.fieldResults.filter((row) => !row.success)
        : this.deploymentResult.fieldResults;

    return rows.map((row, index) => ({
      ...row,
      rowNumber: this.findRowNumber(row.rowKey, index),
      statusClass: row.success
        ? "status-pill status-pill-success"
        : "status-pill status-pill-error"
    }));
  }

  get hasDeploymentFailures() {
    return Boolean(this.deploymentResult && this.deploymentResult.failureCount > 0);
  }

  get hasFailedRowsToRetry() {
    return this.filteredFailedFieldRows.length > 0;
  }

  get isRetryFailedDisabled() {
    return !this.hasFailedRowsToRetry;
  }

  get filteredFailedFieldRows() {
    return this.fieldRows.filter((row) => {
      const resultRow = this.getDeploymentRowResult(row.key);
      return resultRow && !resultRow.success;
    });
  }

  get filteredProfileOptions() {
    const selected = new Set(this.selectedProfiles.map((p) => p.value));
    const term = this.profileSearchTerm.toLowerCase();
    return this.profileOptions.filter(
      (opt) =>
        !selected.has(opt.value) &&
        (!term || opt.label.toLowerCase().includes(term))
    );
  }

  get hasFlsResults() {
    return this.flsResults && this.flsResults.length > 0;
  }

  get processedFlsResults() {
    return this.flsResults.map((r) => ({
      ...r,
      statusLabel: r.success ? "Success" : "Failed",
      statusClass: r.success
        ? "status-pill status-pill-success"
        : "status-pill status-pill-error",
      summaryLine: r.success
        ? `${r.fieldsApplied} field(s) updated`
        : r.message
    }));
  }

  get showFlsSection() {
    return this.fieldRows.length > 0;
  }

  handleObjectModeChange(event) {
    this.objectMode = event.detail.value;
    this.fieldRows = [];
    this.selectedExistingObject = "";
    this.existingObjectSearchTerm = "";
    this.clearDeploymentResult();
  }

  handleExistingObjectSearch(event) {
    this.existingObjectSearchTerm = event.target.value;
    this.selectedExistingObject = event.target.value;
    this.showExistingObjectDropdown = true;
  }

  handleExistingObjectFocus() {
    this.showExistingObjectDropdown = true;
  }

  handleExistingObjectOptionMouseDown() {
    this.suppressExistingObjectBlur = true;
  }

  handleExistingObjectBlur() {
    if (this.suppressExistingObjectBlur) {
      this.suppressExistingObjectBlur = false;
      return;
    }

    this.showExistingObjectDropdown = false;
    const matched = this.findObjectMatch(this.existingObjectSearchTerm);
    if (matched) {
      this.selectedExistingObject = matched.value;
      this.existingObjectSearchTerm = matched.label;
    } else if (this.selectedExistingObject) {
      const current = this.objectOptions.find(
        (opt) => opt.value === this.selectedExistingObject
      );
      this.existingObjectSearchTerm = current ? current.label : "";
    } else {
      this.existingObjectSearchTerm = "";
    }
  }

  handleExistingObjectSelect(event) {
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;
    this.selectedExistingObject = value;
    this.existingObjectSearchTerm = label;
    this.showExistingObjectDropdown = false;
  }

  handleNewObjectLabelChange(event) {
    const val = event.detail.value;
    this.newObject.label = val;

    if (val) {
      this.newObject.pluralLabel = val.endsWith("s") ? val : val + "s";
      this.newObject.apiName = this.formatApiName(val);
    } else {
      this.newObject.pluralLabel = "";
      this.newObject.apiName = "";
    }
  }

  handleNewObjectPluralChange(event) {
    this.newObject.pluralLabel = event.detail.value;
  }

  handleNewObjectApiChange(event) {
    this.newObject.apiName = event.detail.value;
  }

  handleNewObjectNameFieldLabelChange(event) {
    this.newObject.nameFieldLabel = event.detail.value;
  }

  handleNewObjectNameFieldTypeChange(event) {
    this.newObject.nameFieldType = event.detail.value;
  }

  handleNewObjectThemeChange(event) {
    this.newObject.theme = event.detail.value;
  }

  handleCloneFieldRow(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const rowToClone = this.fieldRows[index];
    const rowKey = this.generateRowKey();

    const clonedRow = {
      ...rowToClone,
      key: rowKey,
      label: rowToClone.label ? rowToClone.label + " Copy" : "",
      apiName: rowToClone.label
        ? this.formatApiName(rowToClone.label + " Copy")
        : "",
      showDropdown: false
    };

    const updatedRows = [...this.fieldRows];
    updatedRows.splice(index + 1, 0, clonedRow);
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleAddFieldRow() {
    this.fieldRows = [...this.fieldRows, this.createFieldRow()];
    this.clearDeploymentResult();
  }

  handleDeleteFieldRow(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    this.fieldRows = this.fieldRows.filter((_, idx) => idx !== index);
    this.clearDeploymentResult();
  }

  handleFieldLabelChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const val = event.target.value;
    const updatedRows = [...this.fieldRows];
    updatedRows[index].label = val;
    updatedRows[index].apiName = this.formatApiName(val);
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleFieldApiChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const updatedRows = [...this.fieldRows];
    updatedRows[index].apiName = event.target.value;
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleFieldTypeChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const typeSelected = event.target.value;
    const updatedRows = [...this.fieldRows];

    updatedRows[index].dataType = typeSelected;
    updatedRows[index].isText = typeSelected === "Text" || typeSelected === "TextArea";
    updatedRows[index].isLookup =
      typeSelected === "Lookup" || typeSelected === "ExternalLookup";
    updatedRows[index].isAutoNumber = typeSelected === "AutoNumber";
    updatedRows[index].isFormula = typeSelected === "Formula";
    updatedRows[index].isPicklist =
      typeSelected === "Picklist" || typeSelected === "MultiselectPicklist";
    updatedRows[index].isLocation = typeSelected === "Location";
    updatedRows[index].isHtml = typeSelected === "Html";
    updatedRows[index].isEncrypted = typeSelected === "EncryptedText";
    updatedRows[index].isMultiselect = typeSelected === "MultiselectPicklist";
    updatedRows[index].isOther =
      !updatedRows[index].isText &&
      !updatedRows[index].isLookup &&
      !updatedRows[index].isAutoNumber &&
      !updatedRows[index].isFormula &&
      !updatedRows[index].isPicklist &&
      !updatedRows[index].isLocation &&
      !updatedRows[index].isHtml &&
      !updatedRows[index].isEncrypted;

    updatedRows[index].length = updatedRows[index].isText
      ? 255
      : typeSelected === "Html"
        ? 32768
        : typeSelected === "EncryptedText"
          ? 175
          : null;
    updatedRows[index].relatedObject = updatedRows[index].isLookup ? "" : null;
    updatedRows[index].relatedObjectSearchTerm = updatedRows[index].isLookup
      ? ""
      : "";
    updatedRows[index].displayFormat =
      typeSelected === "AutoNumber" ? "AN-{0000}" : null;
    updatedRows[index].startingNumber = typeSelected === "AutoNumber" ? 1 : null;
    updatedRows[index].formula = typeSelected === "Formula" ? "" : null;
    updatedRows[index].formulaType = typeSelected === "Formula" ? "Text" : null;
    updatedRows[index].picklistValues = updatedRows[index].isPicklist
      ? "Value 1, Value 2, Value 3"
      : null;
    updatedRows[index].visibleLines =
      typeSelected === "Html" ? 10 : typeSelected === "MultiselectPicklist" ? 4 : null;
    updatedRows[index].scale =
      typeSelected === "Location"
        ? 2
        : typeSelected === "Number" ||
            typeSelected === "Percent" ||
            typeSelected === "Currency"
          ? 2
          : null;

    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleFieldDisplayFormatChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      displayFormat: event.target.value
    });
  }

  handleFieldStartingNumberChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      startingNumber: parseInt(event.target.value, 10)
    });
  }

  handleFieldFormulaChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      formula: event.target.value
    });
  }

  handleFieldFormulaTypeChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const updatedRows = [...this.fieldRows];
    const formulaType = event.target.value;
    updatedRows[index].formulaType = formulaType;
    updatedRows[index].length = formulaType === "Text" ? 255 : null;
    updatedRows[index].scale =
      formulaType === "Number" ||
      formulaType === "Percent" ||
      formulaType === "Currency"
        ? 2
        : null;
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleFieldPicklistValuesChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      picklistValues: event.target.value
    });
  }

  handleFieldVisibleLinesChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      visibleLines: parseInt(event.target.value, 10)
    });
  }

  handleFieldScaleChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      scale: parseInt(event.target.value, 10)
    });
  }

  handleFieldLengthChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      length: parseInt(event.target.value, 10)
    });
  }

  handleFieldRelatedObjectSearch(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const updatedRows = [...this.fieldRows];
    updatedRows[index].relatedObjectSearchTerm = event.target.value;
    updatedRows[index].relatedObject = event.target.value;
    updatedRows[index].showDropdown = true;
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  handleFieldRelatedObjectFocus(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const updatedRows = [...this.fieldRows];
    updatedRows[index].showDropdown = true;
    this.fieldRows = updatedRows;
  }

  handleFieldRelatedObjectOptionMouseDown(event) {
    this.suppressFieldBlurKey = event.currentTarget.dataset.key;
  }

  handleFieldRelatedObjectBlur(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const rowKey = event.target.dataset.key;
    if (this.suppressFieldBlurKey === rowKey) {
      this.suppressFieldBlurKey = null;
      return;
    }

    const updatedRows = [...this.fieldRows];
    if (updatedRows[index]) {
      updatedRows[index].showDropdown = false;
      const matched = this.findObjectMatch(updatedRows[index].relatedObjectSearchTerm);
      if (matched) {
        updatedRows[index].relatedObject = matched.value;
        updatedRows[index].relatedObjectSearchTerm = matched.label;
      } else if (updatedRows[index].relatedObject) {
        const current = this.objectOptions.find(
          (opt) => opt.value === updatedRows[index].relatedObject
        );
        updatedRows[index].relatedObjectSearchTerm = current ? current.label : "";
      } else {
        updatedRows[index].relatedObjectSearchTerm = "";
      }
      this.fieldRows = updatedRows;
    }
  }

  handleFieldRelatedObjectSelect(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;

    const updatedRows = [...this.fieldRows];
    updatedRows[index].relatedObject = value;
    updatedRows[index].relatedObjectSearchTerm = label;
    updatedRows[index].showDropdown = false;
    this.fieldRows = updatedRows;
    this.suppressFieldBlurKey = null;
    this.clearDeploymentResult();
  }

  handleFieldRequiredChange(event) {
    this.updateFieldRow(event.target.dataset.index, {
      isRequired: event.target.checked
    });
  }

  async handleDeploySchema() {
    const inputs = [
      ...this.template.querySelectorAll(
        ".schema-creator-tab lightning-input, .schema-creator-tab lightning-combobox, .schema-creator-tab lightning-textarea"
      )
    ];
    const allValid = inputs.reduce((validSoFar, inputFields) => {
      inputFields.reportValidity();
      return validSoFar && inputFields.checkValidity();
    }, true);

    if (!allValid) {
      this.showToast(
        "Validation Error",
        "Please complete all required fields.",
        "error"
      );
      return;
    }

    if (this.isExistingObjectMode && !this.selectedExistingObject) {
      this.showToast("Error", "Please select a target Object.", "error");
      return;
    }
    if (this.fieldRows.length === 0) {
      this.showToast("Error", "Please define at least one field to deploy.", "error");
      return;
    }

    const clientErrors = this.validateFieldRows();
    if (clientErrors.length > 0) {
      this.showToast("Validation Error", clientErrors[0], "error");
      return;
    }

    this.isLoading = true;
    this.clearDeploymentResult();

    const fieldsPayload = this.fieldRows.map((row) => ({
      rowKey: row.key,
      label: row.label,
      apiName: row.apiName,
      dataType: row.dataType,
      length: row.length,
      isRequired: row.isRequired,
      relatedObject: row.relatedObject,
      displayFormat: row.displayFormat,
      startingNumber: row.startingNumber,
      formula: row.formula,
      formulaType: row.formulaType,
      picklistValues: row.picklistValues,
      visibleLines: row.visibleLines,
      scale: row.scale
    }));

    let objDefPayload = null;
    if (this.isNewObjectMode) {
      objDefPayload = {
        label: this.newObject.label,
        pluralLabel: this.newObject.pluralLabel,
        apiName: this.newObject.apiName,
        nameFieldLabel: this.newObject.nameFieldLabel,
        nameFieldType: this.newObject.nameFieldType,
        theme: this.newObject.theme
      };
    } else {
      fieldsPayload.forEach((field) => {
        field.relatedObject = this.selectedExistingObject;
      });
    }

    try {
      const result = await deploySchema({ objDef: objDefPayload, fields: fieldsPayload });
      this.deploymentResult = result;
      this.deploymentFilter = result.failureCount > 0 ? "failed" : "all";

      const toastVariant = result.failureCount > 0 ? "warning" : "success";
      const toastTitle =
        result.failureCount > 0 ? "Deployment Completed With Issues" : "Deployment Successful";
      this.showToast(toastTitle, result.overallMessage, toastVariant);

      await refreshApex(this.wiredObjectsResult);

      // FLS step — runs only when fields succeeded and FLS is enabled
      this.flsResults = [];
      if (this.flsEnabled && this.selectedProfiles.length > 0 && result.successCount > 0) {
        const successfulFields = result.fieldResults
          .filter((r) => r.success)
          .map((r) => `${r.targetObject}.${r.apiName}`);

        try {
          this.flsResults = await assignProfileFls({
            assignments: this.selectedProfiles.map((p) => ({
              profileLabel: p.label,
              profileMetadataName: p.metadataName,
              readAll: p.readAll,
              editAll: p.editAll
            })),
            successfulFieldApiNames: successfulFields
          });

          const flsSuccessCount = this.flsResults.filter((r) => r.success).length;
          const flsFailCount = this.flsResults.length - flsSuccessCount;
          if (flsFailCount > 0) {
            this.showToast(
              "FLS Assignment Issues",
              `${flsSuccessCount} profile(s) updated, ${flsFailCount} failed. Check results for details.`,
              "warning"
            );
          } else {
            this.showToast(
              "FLS Assigned",
              `Field permissions applied to ${flsSuccessCount} profile(s).`,
              "success"
            );
          }
        } catch (flsError) {
          const flsMsg = flsError?.body?.message || flsError?.message || "FLS assignment failed.";
          this.showToast("FLS Assignment Failed", flsMsg, "error");
        }
      }

      this.isDeploymentModalOpen = true;

      if (result.failureCount === 0) {
        this.resetSchemaForm();
      }
    } catch (error) {
      const message = error?.body?.message || error?.message || "Deployment failed.";
      this.showToast("Deployment Failed", message, "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleDeploymentFilterChange(event) {
    this.deploymentFilter = event.detail.value;
  }

  handleCloseDeploymentModal() {
    this.isDeploymentModalOpen = false;
  }

  handleRetryFailedRows() {
    const failedRows = this.filteredFailedFieldRows.map((row) => ({
      ...row,
      showDropdown: false
    }));

    if (failedRows.length === 0) {
      return;
    }

    this.fieldRows = failedRows;
    this.clearDeploymentResult();
    this.isDeploymentModalOpen = false;
    this.showToast(
      "Retry Ready",
      `${failedRows.length} failed row(s) kept for correction and retry.`,
      "info"
    );
  }

  handleRecordTargetObjectSearch(event) {
    const val = event.target.value;
    this.recordTargetObjectSearchTerm = val;
    this.showRecordTargetObjectDropdown = true;
    if (!val) {
      this.recordTargetObject = "";
      this.activeObjectFields = [];
      this.recordRows = [];
    }
  }

  handleRecordTargetObjectFocus() {
    this.showRecordTargetObjectDropdown = true;
  }

  handleRecordTargetObjectOptionMouseDown() {
    this.suppressRecordTargetObjectBlur = true;
  }

  handleRecordTargetObjectBlur() {
    if (this.suppressRecordTargetObjectBlur) {
      this.suppressRecordTargetObjectBlur = false;
      return;
    }

    this.showRecordTargetObjectDropdown = false;
    const matched = this.findObjectMatch(this.recordTargetObjectSearchTerm);
    if (matched) {
      if (this.recordTargetObject !== matched.value) {
        this.recordTargetObject = matched.value;
        this.recordTargetObjectSearchTerm = matched.label;
        this.loadRecordFields();
      } else {
        this.recordTargetObjectSearchTerm = matched.label;
      }
    } else if (this.recordTargetObject) {
      const current = this.objectOptions.find(
        (opt) => opt.value === this.recordTargetObject
      );
      this.recordTargetObjectSearchTerm = current ? current.label : "";
    } else {
      this.recordTargetObjectSearchTerm = "";
    }
  }

  handleRecordTargetObjectSelect(event) {
    const value = event.currentTarget.dataset.value;
    const label = event.currentTarget.dataset.label;
    if (this.recordTargetObject !== value) {
      this.recordTargetObject = value;
      this.recordTargetObjectSearchTerm = label;
      this.showRecordTargetObjectDropdown = false;
      this.loadRecordFields();
    } else {
      this.recordTargetObjectSearchTerm = label;
      this.showRecordTargetObjectDropdown = false;
    }
  }

  async loadRecordFields() {
    this.recordRows = [];
    this.activeObjectFields = [];

    if (!this.recordTargetObject) return;

    this.isLoading = true;
    try {
      const rawFields = await getObjectFields({
        objectApiName: this.recordTargetObject
      });

      this.activeObjectFields = rawFields.map((field) => {
        const type = field.type;
        return {
          label: field.label,
          value: field.value,
          type,
          isRequired: field.isRequired === "true",
          isBoolean: type === "BOOLEAN",
          isDate: type === "DATE",
          isDateTime: type === "DATETIME",
          isNumber:
            type === "INTEGER" ||
            type === "DOUBLE" ||
            type === "CURRENCY" ||
            type === "PERCENT",
          isText:
            type !== "BOOLEAN" &&
            type !== "DATE" &&
            type !== "DATETIME" &&
            type !== "INTEGER" &&
            type !== "DOUBLE" &&
            type !== "CURRENCY" &&
            type !== "PERCENT"
        };
      });
    } catch (error) {
      this.showToast(
        "Error",
        "Failed to fetch fields: " + error.body.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleAddRecordRow() {
    const rowKey = this.generateRowKey();
    const valueMap = {};
    this.activeObjectFields.forEach((field) => {
      valueMap[field.value] = field.isBoolean ? false : "";
    });

    this.recordRows = [
      ...this.recordRows,
      {
        key: rowKey,
        values: valueMap
      }
    ];
  }

  handleDeleteRecordRow(event) {
    const rowIndex = parseInt(event.target.dataset.row, 10);
    this.recordRows = this.recordRows.filter((_, idx) => idx !== rowIndex);
  }

  handleRecordValueChange(event) {
    const fieldName = event.target.dataset.field;
    const rowIndex = parseInt(event.target.dataset.row, 10);
    const value =
      event.detail.checked !== undefined
        ? event.detail.checked
        : event.detail.value;

    const updatedRows = [...this.recordRows];
    updatedRows[rowIndex] = {
      ...updatedRows[rowIndex],
      values: {
        ...updatedRows[rowIndex].values,
        [fieldName]: value
      }
    };
    this.recordRows = updatedRows;
  }

  async handleSaveRecords() {
    const recordInputs = [
      ...this.template.querySelectorAll(".record-creator-tab .record-input")
    ];
    const allValid = recordInputs.reduce((validSoFar, field) => {
      field.reportValidity();
      return validSoFar && field.checkValidity();
    }, true);

    if (!allValid) {
      this.showToast(
        "Validation Error",
        "Please correct the fields before saving.",
        "error"
      );
      return;
    }

    this.isLoading = true;
    const recordsPayload = this.recordRows.map((row) => row.values);

    try {
      await insertRecords({
        objectApiName: this.recordTargetObject,
        records: recordsPayload
      });
      this.showToast(
        "Success",
        `${recordsPayload.length} records saved successfully.`,
        "success"
      );
      this.recordRows = [];
    } catch (error) {
      this.showToast("Save Failed", error.body.message, "error");
    } finally {
      this.isLoading = false;
    }
  }

  findObjectMatch(searchTerm) {
    const term = (searchTerm || "").toLowerCase();
    return this.objectOptions.find(
      (opt) => opt.value.toLowerCase() === term || opt.label.toLowerCase() === term
    );
  }

  validateFieldRows() {
    const errors = [];
    const seenApiNames = new Set();

    this.fieldRows.forEach((row, index) => {
      const rowLabel = `Row ${index + 1}`;
      const apiName = this.ensureCustomSuffix(row.apiName).toLowerCase();
      if (seenApiNames.has(apiName)) {
        errors.push(`${rowLabel}: duplicate field API names are not allowed.`);
      } else {
        seenApiNames.add(apiName);
      }

      if (row.isLookup && !row.relatedObject) {
        errors.push(`${rowLabel}: lookup fields require a related object.`);
      }
      if (row.isFormula && !row.formula) {
        errors.push(`${rowLabel}: formula fields require an expression.`);
      }
      if (row.isPicklist && !row.picklistValues) {
        errors.push(`${rowLabel}: picklist fields require values.`);
      }
      if (row.dataType === "Summary") {
        errors.push(`${rowLabel}: roll-up summary fields are not supported yet.`);
      }
    });

    return errors;
  }

  createFieldRow() {
    return {
      key: this.generateRowKey(),
      label: "",
      apiName: "",
      dataType: "Text",
      length: 255,
      isRequired: false,
      relatedObject: "",
      relatedObjectSearchTerm: "",
      showDropdown: false,
      isText: true,
      isLookup: false,
      isAutoNumber: false,
      isFormula: false,
      isPicklist: false,
      isLocation: false,
      isHtml: false,
      isEncrypted: false,
      isMultiselect: false,
      isOther: false
    };
  }

  updateFieldRow(indexValue, updates) {
    const index = parseInt(indexValue, 10);
    const updatedRows = [...this.fieldRows];
    updatedRows[index] = {
      ...updatedRows[index],
      ...updates
    };
    this.fieldRows = updatedRows;
    this.clearDeploymentResult();
  }

  findRowNumber(rowKey, fallbackIndex) {
    const index = this.fieldRows.findIndex((row) => row.key === rowKey);
    return index === -1 ? fallbackIndex + 1 : index + 1;
  }

  getDeploymentRowResult(rowKey) {
    return this.deploymentResult?.fieldResults?.find((row) => row.rowKey === rowKey);
  }

  clearDeploymentResult() {
    this.deploymentResult = null;
    this.deploymentFilter = "all";
    this.isDeploymentModalOpen = false;
  }

  resetSchemaForm() {
    this.fieldRows = [];
    this.selectedExistingObject = "";
    this.existingObjectSearchTerm = "";
    if (this.isNewObjectMode) {
      this.newObject = {
        label: "",
        pluralLabel: "",
        apiName: "",
        nameFieldLabel: "Name",
        nameFieldType: "Text",
        theme: "Custom67: Gear"
      };
    }
  }

  generateRowKey() {
    return Date.now().toString() + Math.random().toString(36).slice(2, 7);
  }

  ensureCustomSuffix(apiName) {
    if (!apiName) return "";
    return apiName.endsWith("__c") ? apiName : `${apiName}__c`;
  }

  formatApiName(label) {
    if (!label) return "";

    let formatted = label
      .trim()
      .replace(/[\s-]+/g, "_")
      .replace(/[^a-zA-Z0-9_]/g, "")
      .replace(/_+/g, "_");

    if (formatted.startsWith("_")) formatted = formatted.substring(1);
    if (formatted.endsWith("_")) formatted = formatted.slice(0, -1);

    if (!formatted.endsWith("__c")) {
      formatted += "__c";
    }
    return formatted;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  // ─── FLS / Profile handlers ────────────────────────────────────────────────

  handleFlsToggleChange(event) {
    this.flsEnabled = event.target.checked;
    if (!this.flsEnabled) {
      this.selectedProfiles = [];
      this.profileSearchTerm = "";
      this.flsResults = [];
    }
  }

  handleProfileSearch(event) {
    this.profileSearchTerm = event.target.value;
    this.showProfileDropdown = true;
  }

  handleProfileFocus() {
    this.showProfileDropdown = true;
  }

  handleProfileOptionMouseDown() {
  // Sirf blur ko suppress karein taaki click register hone se pehle dropdown hide na ho jaye
  this.suppressProfileBlur = true;
}

  handleProfileBlur() {
    if (this.suppressProfileBlur) {
      this.suppressProfileBlur = false;
      return;
    }
    this.showProfileDropdown = false;
    this.profileSearchTerm = "";
  }

  handleProfileSelect(event) {
  event.preventDefault();
  event.stopPropagation();
  
  // Ab event.currentTarget perfect work karega kyunki ye seedha onclick se trigger ho raha hai
  const value = event.currentTarget.dataset.value;
  const label = event.currentTarget.dataset.label;
  const metadataName = event.currentTarget.dataset.metadataName;

  if (!this.selectedProfiles.find((p) => p.value === value)) {
    this.selectedProfiles = [
      ...this.selectedProfiles,
      { value, label, metadataName, readAll: true, editAll: true, isEditDisabled: false }
    ];
  }
  
  this.profileSearchTerm = "";
  this.showProfileDropdown = false;
  this.suppressProfileBlur = false; // Flag ko wapas reset kar dein
  this.clearProfileSearchInput();
}

  clearProfileSearchInput() {
    const profileInput = this.template.querySelector(".fls-profile-input");
    if (profileInput) {
      profileInput.value = "";
      profileInput.blur();
    }
  }

  handleProfileRemove(event) {
    event.preventDefault();
    event.stopPropagation();
    const value = event.currentTarget.dataset.value;
    this.selectedProfiles = this.selectedProfiles.filter((p) => p.value !== value);
  }

  handleProfileReadChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const isRead = event.target.checked;
    const updated = [...this.selectedProfiles];
    updated[index] = {
      ...updated[index],
      readAll: isRead,
      editAll: isRead ? updated[index].editAll : false,
      isEditDisabled: !isRead
    };
    this.selectedProfiles = updated;
  }

  handleProfileEditChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const isEdit = event.target.checked;
    const updated = [...this.selectedProfiles];
    updated[index] = {
      ...updated[index],
      editAll: isEdit,
      // Auto-fix: Salesforce requires readable=true whenever editable=true
      readAll: isEdit ? true : updated[index].readAll,
      isEditDisabled: false
    };
    this.selectedProfiles = updated;
  }
}