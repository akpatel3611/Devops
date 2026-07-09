import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getObjectFields from "@salesforce/apex/ObjectManagerController.getObjectFields";
import createFieldsBulk from "@salesforce/apex/ObjectManagerController.createFieldsBulk";
import deleteField from "@salesforce/apex/ObjectManagerController.deleteField";

const ALL_DATA_TYPES = "ALL";
const FIELD_TYPE_OPTIONS = [
  { label: "Text", value: "Text", detailMode: "length", length: 255 },
  {
    label: "Text Area",
    value: "TextArea",
    detailMode: "length",
    length: 255
  },
  {
    label: "Long Text Area",
    value: "LongTextArea",
    detailMode: "longText",
    length: 32768,
    visibleLines: 3
  },
  {
    label: "Rich Text Area",
    value: "Html",
    detailMode: "longText",
    length: 32768,
    visibleLines: 3
  },
  {
    label: "Number",
    value: "Number",
    detailMode: "number",
    precision: 18,
    scale: 0
  },
  {
    label: "Currency",
    value: "Currency",
    detailMode: "number",
    precision: 18,
    scale: 2
  },
  {
    label: "Percent",
    value: "Percent",
    detailMode: "number",
    precision: 3,
    scale: 2
  },
  { label: "Checkbox", value: "Checkbox", detailMode: "none" },
  { label: "Date", value: "Date", detailMode: "none" },
  { label: "Date/Time", value: "DateTime", detailMode: "none" },
  { label: "Time", value: "Time", detailMode: "none" },
  { label: "Email", value: "Email", detailMode: "length", length: 80 },
  { label: "Phone", value: "Phone", detailMode: "length", length: 40 },
  { label: "URL", value: "Url", detailMode: "length", length: 255 },
  {
    label: "Auto Number",
    value: "AutoNumber",
    detailMode: "autoNumber",
    displayFormat: "AUTO-{0000}",
    startingNumber: 1
  },
  {
    label: "Encrypted Text",
    value: "EncryptedText",
    detailMode: "length",
    length: 175
  },
  { label: "Picklist", value: "Picklist", detailMode: "picklist" },
  {
    label: "Picklist (Multi-Select)",
    value: "MultiselectPicklist",
    detailMode: "picklist"
  }
];

const FIELD_TYPE_LOOKUP = FIELD_TYPE_OPTIONS.reduce((lookup, option) => {
  lookup[option.value] = option;
  return lookup;
}, {});

const FIELD_TYPE_ALIASES = {
  text: "Text",
  textarea: "TextArea",
  "textarea field": "TextArea",
  "text area": "TextArea",
  longtextarea: "LongTextArea",
  "long text area": "LongTextArea",
  longtextareaarea: "LongTextArea",
  html: "Html",
  "rich text area": "Html",
  richtextarea: "Html",
  number: "Number",
  currency: "Currency",
  percent: "Percent",
  checkbox: "Checkbox",
  boolean: "Checkbox",
  date: "Date",
  datetime: "DateTime",
  "date/time": "DateTime",
  "date time": "DateTime",
  time: "Time",
  email: "Email",
  phone: "Phone",
  url: "Url",
  autonumber: "AutoNumber",
  "auto number": "AutoNumber",
  "encrypted text": "EncryptedText",
  encryptedtext: "EncryptedText",
  picklist: "Picklist",
  "picklist (multi-select)": "MultiselectPicklist",
  "multi-select picklist": "MultiselectPicklist",
  multipicklist: "MultiselectPicklist",
  "multi picklist": "MultiselectPicklist"
};

const EXTRA_DATA_TYPE_FILTER_OPTIONS = [
  "AutoNumber",
  "Reference",
  "Formula",
  "RollUpSummary",
  "Location",
  "Address",
  "Id",
  "Html"
];

const DATA_TYPE_CANONICAL_VALUE_BY_KEY = {
  text: "Text",
  textarea: "TextArea",
  longtextarea: "LongTextArea",
  html: "Html",
  richtextarea: "Html",
  number: "Number",
  currency: "Currency",
  percent: "Percent",
  checkbox: "Checkbox",
  boolean: "Checkbox",
  date: "Date",
  datetime: "DateTime",
  time: "Time",
  email: "Email",
  phone: "Phone",
  url: "Url",
  autonumber: "AutoNumber",
  encryptedtext: "EncryptedText",
  picklist: "Picklist",
  multiselectpicklist: "MultiselectPicklist",
  multipicklist: "MultiselectPicklist",
  reference: "Reference",
  lookup: "Reference",
  formula: "Formula",
  rollupsummary: "RollUpSummary",
  location: "Location",
  address: "Address",
  id: "Id"
};

const DATA_TYPE_LABEL_BY_VALUE = {
  Text: "Text",
  TextArea: "Text Area",
  LongTextArea: "Long Text Area",
  Html: "Rich Text Area",
  Number: "Number",
  Currency: "Currency",
  Percent: "Percent",
  Checkbox: "Checkbox",
  Date: "Date",
  DateTime: "Date/Time",
  Time: "Time",
  Email: "Email",
  Phone: "Phone",
  Url: "URL",
  AutoNumber: "Auto Number",
  EncryptedText: "Encrypted Text",
  Picklist: "Picklist",
  MultiselectPicklist: "Picklist (Multi-Select)",
  Reference: "Lookup/Reference",
  Formula: "Formula",
  RollUpSummary: "Roll-Up Summary",
  Location: "Location",
  Address: "Address",
  Id: "ID"
};

const DEFAULT_MANUAL_ROW = {
  label: "",
  apiName: "",
  apiNameManuallyEdited: false,
  type: "Text",
  length: 255,
  precision: 18,
  scale: 0,
  required: false,
  unique: false,
  externalId: false,
  picklistValues: "",
  description: "",
  inlineHelpText: "",
  defaultValue: false,
  displayFormat: "AUTO-{0000}",
  startingNumber: 1,
  visibleLines: 3
};

export default class SectionFields extends LightningElement {
  _objectName;

  _initialSearchTerm = "";

  allFields = [];

  error;

  searchTerm = "";

  selectedDataType = ALL_DATA_TYPES;

  isManualModalOpen = false;

  isCsvModalOpen = false;

  manualRows = [];

  manualReviewRows = [];

  isManualReviewMode = false;

  manualSubmitErrors = [];

  csvRows = [];

  csvErrors = [];

  selectedCsvFileName = "";

  isSaving = false;

  isImpactModalOpen = false;

  impactTarget;

  wiredFieldsResult;

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    this._objectName = value;
    this.allFields = [];
    this.error = undefined;
    this.searchTerm = this._initialSearchTerm || "";
    this.selectedDataType = ALL_DATA_TYPES;
  }

  @api
  get initialSearchTerm() {
    return this._initialSearchTerm;
  }

  set initialSearchTerm(value) {
    this._initialSearchTerm = value || "";
    this.searchTerm = this._initialSearchTerm;
  }

  get hasFields() {
    return this.filteredFields.length > 0;
  }

  get dataTypeOptions() {
    const uniqueTypeMap = new Map();
    [
      ...this.allFields.map((field) => field.dataType),
      ...FIELD_TYPE_OPTIONS.map((option) => option.value),
      ...EXTRA_DATA_TYPE_FILTER_OPTIONS
    ].forEach((value) => {
      const canonicalValue = this.normalizeDataTypeValue(value);
      if (canonicalValue) {
        uniqueTypeMap.set(canonicalValue.toLowerCase(), canonicalValue);
      }
    });

    const uniqueTypes = [...uniqueTypeMap.values()].sort((left, right) =>
      this.getDataTypeLabel(left).localeCompare(this.getDataTypeLabel(right))
    );

    return [
      { label: "All Data Types", value: ALL_DATA_TYPES },
      ...uniqueTypes.map((dataType) => ({
        label: this.getDataTypeLabel(dataType),
        value: dataType
      }))
    ];
  }

  get bulkDataTypeOptions() {
    return FIELD_TYPE_OPTIONS.map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get filteredFields() {
    const normalizedSearch = this.searchTerm.trim().toLowerCase();

    return this.allFields
      .filter((field) => {
        const matchesSearch =
          !normalizedSearch ||
          field.label.toLowerCase().includes(normalizedSearch) ||
          field.apiName.toLowerCase().includes(normalizedSearch);

        const matchesDataType =
          this.selectedDataType === ALL_DATA_TYPES ||
          field.dataType === this.selectedDataType;

        return matchesSearch && matchesDataType;
      })
      .map((field) => ({
        ...field,
        requiredLabel: field.isRequired ? "Yes" : "No",
        externalIdLabel: field.isExternalId ? "Yes" : "No",
        dataTypeLabel: this.getDataTypeLabel(field.dataType),
        fieldUrl: this.buildFieldSetupUrl(
          this.resolveFieldNavigationKey(field)
        ),
        fieldEditUrl: this.buildFieldEditUrl(field.durableIdToken),
        canDelete: Boolean(field.isCustom),
        deleteDisabled: !field.isCustom
      }));
  }

  get fieldCountLabel() {
    return `${this.filteredFields.length} fields`;
  }

  get hasCsvRows() {
    return this.csvRows.length > 0;
  }

  get hasCsvErrors() {
    return this.csvErrors.length > 0;
  }

  get csvCountLabel() {
    return `${this.csvRows.length} rows parsed`;
  }

  get manualRowsView() {
    return this.manualRows.map((row, index) => ({
      ...row,
      typeLabel: this.getTypeDefinition(row.type).label,
      isText:
        row.type === "Text" ||
        row.type === "Email" ||
        row.type === "Phone" ||
        row.type === "Url" ||
        row.type === "EncryptedText",
      isTextArea: row.type === "TextArea",
      isNumber: row.type === "Number",
      isCurrency: row.type === "Currency",
      isPercent: row.type === "Percent",
      isCheckbox: row.type === "Checkbox",
      isPicklist: row.type === "Picklist",
      isMultiSelectPicklist: row.type === "MultiselectPicklist",
      isLongTextArea: row.type === "LongTextArea" || row.type === "Html",
      isAutoNumber: row.type === "AutoNumber",
      isDateTime: row.type === "DateTime",
      isLastRow: index === this.manualRows.length - 1
    }));
  }

  get manualReviewRowsView() {
    return this.manualReviewRows.map((row, index) => ({
      ...row,
      typeLabel: this.getTypeDefinition(row.type).label,
      key: row.key || `review-${index + 1}`,
      extraLabel: this.getCsvExtraLabel(row),
      validationLabel: row.validationErrors?.length
        ? row.validationErrors.join(" ")
        : "Ready",
      validationClass: row.validationErrors?.length
        ? "csv-validation csv-validation_error"
        : "csv-validation csv-validation_ok"
    }));
  }

  get csvRowsView() {
    return this.csvRows.map((row, index) => ({
      ...row,
      typeLabel: this.getTypeDefinition(row.type).label,
      key: row.key || `csv-${index + 1}`,
      extraLabel: this.getCsvExtraLabel(row),
      validationLabel: row.validationErrors?.length
        ? row.validationErrors.join(" ")
        : "Ready",
      validationClass: row.validationErrors?.length
        ? "csv-validation csv-validation_error"
        : "csv-validation csv-validation_ok"
    }));
  }

  get hasManualSubmitErrors() {
    return this.manualSubmitErrors.length > 0;
  }

  get hasManualReviewValidationErrors() {
    return this.manualReviewRows.some((row) => row.validationErrors?.length);
  }

  get isManualConfirmDisabled() {
    return this.isSaving || this.hasManualReviewValidationErrors;
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  buildFieldSetupUrl(fieldKey) {
    const viewKey = (fieldKey || "").trim();
    if (!viewKey) {
      return "";
    }

    return `/lightning/setup/ObjectManager/${this._objectName}/FieldsAndRelationships/${viewKey}/view`;
  }

  buildFieldEditUrl(fieldDurableIdToken) {
    const editKey = (fieldDurableIdToken || "").trim();

    if (!editKey) {
      return "";
    }

    return `/lightning/setup/ObjectManager/${this._objectName}/FieldsAndRelationships/${editKey}/edit`;
  }

  async handleFieldAction(event) {
    const action = event.detail.value;
    const fieldApiName = event.currentTarget.dataset.fieldApiName;
    const fieldInfo = (this.allFields || []).find(
      (field) => field.apiName === fieldApiName
    );

    if (!fieldApiName) {
      return;
    }

    if (action === "edit") {
      const editKey = this.resolveFieldEditKey(
        fieldInfo || { apiName: fieldApiName }
      );
      const editUrl = this.buildFieldEditUrl(editKey);

      if (!editUrl) {
        this.showToast(
          "Edit not available",
          "Could not resolve field durable id.",
          "warning"
        );
        return;
      }

      window.open(editUrl, "_blank");
      return;
    }

    if (action === "delete") {
      if (this.isSaving) {
        return;
      }

      if (!fieldInfo?.isCustom) {
        this.showToast(
          "Delete not allowed",
          "Only custom fields can be deleted.",
          "warning"
        );
        return;
      }

      this.impactTarget = {
        type: "field",
        fieldId:
          fieldInfo?.customFieldId || fieldInfo?.durableIdToken || fieldApiName,
        fieldApiName,
        objectId: this._objectName,
        objectApiName: this._objectName
      };
      this.isImpactModalOpen = true;
    }
  }

  handleCloseImpactModal() {
    this.isImpactModalOpen = false;
    this.impactTarget = undefined;
  }

  async handleConfirmDeleteField() {
    const fieldApiName = this.impactTarget?.fieldApiName;

    if (!fieldApiName) {
      return;
    }

    const fieldInfo = (this.allFields || []).find(
      (field) => field.apiName === fieldApiName
    );
    const didDelete = await this.handleDeleteField(
      fieldInfo || { apiName: fieldApiName }
    );

    if (didDelete) {
      this.handleCloseImpactModal();
    }
  }

  async handleDeleteField(fieldInfo) {
    const fieldApiName = fieldInfo?.apiName;
    const fieldDurableIdToken = fieldInfo?.durableIdToken;
    const customFieldId = fieldInfo?.customFieldId;
    let didDelete = false;

    this.isSaving = true;

    try {
      await deleteField({
        objectName: this._objectName,
        fieldApiName,
        fieldDurableIdToken,
        customFieldIdInput: customFieldId
      });

      this.showToast(
        "Field deleted",
        `${fieldApiName} was deleted successfully.`,
        "success"
      );
      didDelete = true;
    } catch (error) {
      console.error(error);
      this.showToast("Delete failed", this.reduceError(error), "error");
    } finally {
      try {
        await refreshApex(this.wiredFieldsResult);
      } catch (refreshError) {
        console.error(refreshError);
      }
      this.isSaving = false;
    }

    return didDelete;
  }

  handleDataTypeChange(event) {
    this.selectedDataType = event.detail.value;
  }

  handleBulkMenuSelect(event) {
    const action = event.detail.value;

    if (action === "manual") {
      this.openManualModal();
    }

    if (action === "csv") {
      this.openCsvModal();
    }
  }

  openManualModal() {
    this.isManualModalOpen = true;
    this.isManualReviewMode = false;
    this.manualSubmitErrors = [];
    this.manualRows = [this.buildManualRow(1)];
    this.manualReviewRows = [];
  }

  closeManualModal() {
    this.isManualModalOpen = false;
    this.isManualReviewMode = false;
    this.manualReviewRows = [];
    this.manualSubmitErrors = [];
    this.manualRows = [];
  }

  openCsvModal() {
    this.isCsvModalOpen = true;
    this.csvRows = [];
    this.csvErrors = [];
    this.selectedCsvFileName = "";
  }

  closeCsvModal() {
    this.isCsvModalOpen = false;
    this.csvRows = [];
    this.csvErrors = [];
    this.selectedCsvFileName = "";
  }

  buildManualRow(index) {
    return {
      id: this.createRowId(index),
      ...this.getDefaultManualRowValues(),
      ...DEFAULT_MANUAL_ROW
    };
  }

  addManualRow() {
    this.manualRows = [
      ...this.manualRows,
      this.buildManualRow(this.manualRows.length + 1)
    ];
  }

  copyManualRow(event) {
    event.stopPropagation();

    const rowId = event.currentTarget.dataset.id;
    const sourceRow = this.manualRows.find((row) => row.id === rowId);

    if (!sourceRow) {
      return;
    }

    const copiedRow = {
      ...sourceRow,
      id: this.createRowId(this.manualRows.length + 1),
      apiNameManuallyEdited: false
    };

    this.manualRows = [...this.manualRows, copiedRow];
  }

  switchToManualEditMode() {
    this.isManualReviewMode = false;
  }

  handleManualCellChange(event) {
    const rowId = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    const type = event.currentTarget.type;

    this.manualRows = this.manualRows.map((row) => {
      if (row.id !== rowId) {
        return row;
      }

      let value = event.detail?.value ?? event.target.value;

      if (type === "checkbox") {
        value = event.target.checked;
      }

      if (field === "label") {
        const shouldAutofill =
          !row.apiNameManuallyEdited || !(row.apiName || "").trim();

        return {
          ...row,
          label: value,
          apiName: shouldAutofill
            ? this.generateApiNameFromLabel(value)
            : row.apiName
        };
      }

      if (field === "apiName") {
        return {
          ...row,
          apiName: value,
          apiNameManuallyEdited: Boolean((value || "").trim())
        };
      }

      if (field === "type") {
        const typeDefaults = this.getDefaultValuesForType(value);

        return {
          ...row,
          type: value,
          ...typeDefaults
        };
      }

      if (field === "defaultValue") {
        return {
          ...row,
          defaultValue:
            value === true || value === "true" || value === "1" || value === 1
        };
      }

      return {
        ...row,
        [field]: value
      };
    });
  }

  generateApiNameFromLabel(label) {
    const base = (label || "")
      .trim()
      .replace(/[^a-zA-Z0-9_]/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "");

    const withPrefix = /^[A-Za-z_]/.test(base) ? base : `F_${base || "Field"}`;
    const normalized = withPrefix || "Field";

    return normalized.endsWith("__c") ? normalized : `${normalized}__c`;
  }

  async saveManualRows() {
    const reviewRows = this.manualRows
      .map((row, index) => ({
        key: row.id || `draft-${index + 1}`,
        rowNumber: index + 1,
        ...this.normalizeRowForSave(row)
      }))
      .filter((row) => this.hasRowInput(row));

    if (!reviewRows.length) {
      this.showToast(
        "Nothing to save",
        "Add at least one valid row.",
        "warning"
      );
      return;
    }

    const validatedRows = this.validateRowsForSubmission(reviewRows);

    this.manualReviewRows = validatedRows;
    this.isManualReviewMode = true;
    this.manualSubmitErrors = this.collectValidationMessages(validatedRows);

    if (this.manualSubmitErrors.length) {
      this.showToast(
        "Validation errors",
        "Fix the highlighted row errors before creating fields.",
        "warning"
      );
    }
  }

  async confirmManualRows() {
    const validatedRows = this.validateRowsForSubmission(this.manualReviewRows);

    this.manualReviewRows = validatedRows;
    this.manualSubmitErrors = this.collectValidationMessages(validatedRows);

    if (this.manualSubmitErrors.length) {
      this.showToast(
        "Validation errors",
        "Fix the highlighted row errors before creating fields.",
        "warning"
      );
      return;
    }

    const payload = validatedRows.map((row) =>
      this.stripValidationMetadata(this.normalizeRowForSave(row))
    );

    const results = await this.saveRows(payload, "Manual fields created.");
    const failures = (results || []).filter((result) => !result.success);

    if (failures.length) {
      this.manualSubmitErrors = failures.map(
        (failure) =>
          `Row ${failure.rowNumber || "-"} (${failure.label || failure.apiName || "Unknown"}): ${
            failure.message || "Failed to create field."
          }`
      );
    } else {
      this.manualSubmitErrors = [];
    }
  }

  async handleCsvFileChange(event) {
    const [file] = event.target.files || [];

    if (!file) {
      return;
    }

    this.selectedCsvFileName = file.name;
    this.csvErrors = [];

    try {
      const text = await file.text();
      const parsed = this.parseCsvText(text);
      this.csvRows = parsed.rows;
      this.csvErrors = parsed.errors;
    } catch (error) {
      this.csvRows = [];
      this.csvErrors = ["Unable to read CSV file."];
      console.error(error);
    }
  }

  async saveCsvRows() {
    if (!this.csvRows.length) {
      this.showToast(
        "No rows found",
        "Upload a CSV with at least one valid row.",
        "warning"
      );
      return;
    }

    const validatedRows = this.validateRowsForSubmission(this.csvRows);
    this.csvRows = validatedRows;
    this.csvErrors = this.collectValidationMessages(validatedRows);

    if (validatedRows.some((row) => row.validationErrors?.length)) {
      this.showToast(
        "CSV has errors",
        "Fix the highlighted CSV errors before creating fields.",
        "warning"
      );
      return;
    }

    const payload = validatedRows.map((row) =>
      this.stripValidationMetadata(this.normalizeRowForSave(row))
    );
    await this.saveRows(payload, "CSV fields created.");
  }

  async saveRows(rows, successMessage) {
    this.isSaving = true;

    try {
      const results = await createFieldsBulk({
        objectName: this._objectName,
        fieldDefinitions: rows
      });

      const normalizedResults = (results || []).map((result) => ({
        ...result,
        status: result.success ? "Success" : "Failed"
      }));

      const successCount = normalizedResults.filter(
        (result) => result.success
      ).length;
      const failureCount = normalizedResults.length - successCount;

      if (successCount > 0) {
        await refreshApex(this.wiredFieldsResult);
      }

      if (failureCount === 0) {
        if (this.isManualModalOpen) {
          this.closeManualModal();
        }

        if (this.isCsvModalOpen) {
          this.closeCsvModal();
        }
      }

      this.showToast(
        "Bulk create completed",
        `${successCount} succeeded, ${failureCount} failed. ${successMessage}`,
        failureCount ? "warning" : "success"
      );

      return normalizedResults;
    } catch (error) {
      console.error(error);
      this.showToast("Bulk create failed", this.reduceError(error), "error");
      return [];
    } finally {
      this.isSaving = false;
    }
  }

  normalizeRowForSave(row) {
    const label = (row.label || "").trim();
    const apiNameInput = (row.apiName || "").trim();
    const apiName = apiNameInput || this.generateApiNameFromLabel(label);

    return {
      label,
      apiName,
      type: (row.type || "").trim(),
      length: row.length,
      precision: row.precision,
      scale: row.scale,
      required: Boolean(row.required),
      unique: Boolean(row.unique),
      externalId: Boolean(row.externalId),
      picklistValues: (row.picklistValues || "").trim(),
      description: (row.description || "").trim(),
      inlineHelpText: (row.inlineHelpText || "").trim(),
      defaultValue:
        row.defaultValue === true ||
        row.defaultValue === "true" ||
        row.defaultValue === "1",
      displayFormat: (row.displayFormat || "").trim(),
      startingNumber: row.startingNumber,
      visibleLines: row.visibleLines,
      rowNumber: row.rowNumber,
      key: row.key,
      validationErrors: row.validationErrors,
      baseValidationErrors: row.baseValidationErrors
    };
  }

  parseCsvText(text) {
    const lines = this.parseCsvLines(text);

    if (!lines.length) {
      return { rows: [], errors: ["CSV file is empty."] };
    }

    const headerMap = this.buildHeaderMap(lines[0]);
    const rows = [];

    for (let i = 1; i < lines.length; i += 1) {
      const line = lines[i];

      if (!line.some((cell) => (cell || "").trim().length)) {
        continue;
      }

      rows.push(this.normalizeCsvRow(line, headerMap, i + 1));
    }

    const validatedRows = this.validateRowsForSubmission(rows);

    return {
      rows: validatedRows,
      errors: this.collectValidationMessages(validatedRows)
    };
  }

  normalizeCsvRow(line, headerMap, rowNumber) {
    const label = this.readCsvCell(line, headerMap, ["label", "fieldlabel"]);
    const apiNameInput = this.readCsvCell(line, headerMap, [
      "apiname",
      "developername",
      "fieldapi"
    ]);
    const rawType = this.readCsvCell(line, headerMap, ["type", "datatype"]);
    const normalizedType = this.normalizeFieldTypeInput(rawType);
    const rowErrors = [];

    if (!label) {
      rowErrors.push(`Row ${rowNumber}: label is required.`);
    }

    if (!rawType) {
      rowErrors.push(`Row ${rowNumber}: type is required.`);
    }

    if (!normalizedType) {
      rowErrors.push(
        `Row ${rowNumber}: unsupported field type "${rawType || "blank"}".`
      );
    }

    const typeDefinition =
      normalizedType && this.getTypeDefinition(normalizedType);
    const typeDefaults = this.getDefaultValuesForType(normalizedType);

    const row = {
      key: `csv-${rowNumber}`,
      rowNumber,
      label,
      apiName: apiNameInput || this.generateApiNameFromLabel(label),
      apiNameManuallyEdited: Boolean((apiNameInput || "").trim()),
      type: normalizedType || rawType,
      ...typeDefaults,
      length:
        this.readCsvNumberCell(line, headerMap, ["length"]) ??
        typeDefaults.length,
      precision:
        this.readCsvNumberCell(line, headerMap, ["precision"]) ??
        typeDefaults.precision,
      scale:
        this.readCsvNumberCell(line, headerMap, ["scale"]) ??
        typeDefaults.scale,
      required: this.readCsvBooleanCell(line, headerMap, ["required"]),
      unique: this.readCsvBooleanCell(line, headerMap, ["unique"]),
      externalId: this.readCsvBooleanCell(line, headerMap, ["externalid"]),
      picklistValues:
        this.readCsvCell(line, headerMap, [
          "picklistvalues",
          "picklist",
          "values"
        ]) || typeDefaults.picklistValues,
      description: this.readCsvCell(line, headerMap, ["description"]),
      inlineHelpText: this.readCsvCell(line, headerMap, [
        "inlinehelptext",
        "helptext"
      ]),
      defaultValue: this.readCsvBooleanCell(line, headerMap, [
        "defaultvalue",
        "default"
      ]),
      displayFormat:
        this.readCsvCell(line, headerMap, ["displayformat"]) ||
        typeDefaults.displayFormat,
      startingNumber:
        this.readCsvNumberCell(line, headerMap, ["startingnumber", "start"]) ??
        typeDefaults.startingNumber,
      visibleLines:
        this.readCsvNumberCell(line, headerMap, ["visiblelines", "lines"]) ??
        typeDefaults.visibleLines,
      baseValidationErrors: [...rowErrors],
      validationErrors: [...rowErrors]
    };

    if (typeDefinition?.detailMode === "picklist" && !row.picklistValues) {
      rowErrors.push(
        `Row ${rowNumber}: picklist values are required for ${typeDefinition.label}.`
      );
    }

    if (
      typeDefinition &&
      !rowErrors.length &&
      typeDefinition.detailMode === "number"
    ) {
      row.precision =
        this.readCsvNumberCell(line, headerMap, ["precision"]) ?? row.precision;
      row.scale =
        this.readCsvNumberCell(line, headerMap, ["scale"]) ?? row.scale;
    }

    if (typeDefinition && typeDefinition.detailMode === "longText") {
      row.length =
        this.readCsvNumberCell(line, headerMap, ["length"]) ?? row.length;
      row.visibleLines =
        this.readCsvNumberCell(line, headerMap, ["visiblelines", "lines"]) ??
        row.visibleLines;
    }

    if (typeDefinition && typeDefinition.detailMode === "length") {
      row.length =
        this.readCsvNumberCell(line, headerMap, ["length"]) ?? row.length;
    }

    if (typeDefinition && typeDefinition.detailMode === "autoNumber") {
      row.displayFormat =
        this.readCsvCell(line, headerMap, ["displayformat"]) ||
        row.displayFormat;
      row.startingNumber =
        this.readCsvNumberCell(line, headerMap, ["startingnumber", "start"]) ??
        row.startingNumber;
    }

    return row;
  }

  parseCsvLines(text) {
    const rows = [];
    let currentCell = "";
    let currentRow = [];
    let inQuotes = false;

    for (let i = 0; i < text.length; i += 1) {
      const char = text[i];
      const next = text[i + 1];

      if (char === '"') {
        if (inQuotes && next === '"') {
          currentCell += '"';
          i += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char === "," && !inQuotes) {
        currentRow.push(currentCell);
        currentCell = "";
      } else if ((char === "\n" || char === "\r") && !inQuotes) {
        if (char === "\r" && next === "\n") {
          i += 1;
        }

        currentRow.push(currentCell);
        rows.push(currentRow);
        currentCell = "";
        currentRow = [];
      } else {
        currentCell += char;
      }
    }

    if (currentCell.length || currentRow.length) {
      currentRow.push(currentCell);
      rows.push(currentRow);
    }

    return rows;
  }

  buildHeaderMap(headerRow) {
    const map = {};

    headerRow.forEach((header, index) => {
      map[(header || "").trim().toLowerCase().replace(/\s+/g, "")] = index;
    });

    return map;
  }

  readCsvCell(row, headerMap, aliases) {
    for (let i = 0; i < aliases.length; i += 1) {
      const index = headerMap[aliases[i]];
      if (index !== undefined) {
        return (row[index] || "").trim();
      }
    }

    return "";
  }

  readCsvNumberCell(row, headerMap, aliases) {
    const rawValue = this.readCsvCell(row, headerMap, aliases);

    if (!rawValue) {
      return undefined;
    }

    const parsed = Number(rawValue);
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  readCsvBooleanCell(row, headerMap, aliases) {
    const rawValue = this.readCsvCell(row, headerMap, aliases);
    const normalized = rawValue.toLowerCase();

    return ["true", "yes", "1", "y"].includes(normalized);
  }

  hasRowInput(row) {
    if (!row) {
      return false;
    }

    return Boolean(
      (row.label || "").trim() ||
      (row.apiName || "").trim() ||
      (row.picklistValues || "").trim() ||
      (row.description || "").trim() ||
      (row.inlineHelpText || "").trim() ||
      row.required ||
      row.unique ||
      row.externalId ||
      row.defaultValue
    );
  }

  stripValidationMetadata(row) {
    const sanitized = { ...row };
    delete sanitized.rowNumber;
    delete sanitized.key;
    delete sanitized.validationErrors;
    delete sanitized.baseValidationErrors;
    return sanitized;
  }

  collectValidationMessages(rows) {
    const messages = [];

    (rows || []).forEach((row) => {
      (row.validationErrors || []).forEach((message) => messages.push(message));
    });

    return [...new Set(messages)];
  }

  validateRowsForSubmission(rows) {
    const seenApiNames = new Map();
    const existingFieldApiNames = new Map(
      (this.allFields || [])
        .filter((field) => (field.apiName || "").trim())
        .map((field) => [field.apiName.trim().toLowerCase(), field.apiName])
    );

    return (rows || []).map((sourceRow, index) => {
      const rowNumber = sourceRow.rowNumber || index + 1;
      const baseErrors = [
        ...(sourceRow.baseValidationErrors || sourceRow.validationErrors || [])
      ];
      const normalizedRow = {
        ...this.normalizeRowForSave(sourceRow),
        rowNumber
      };

      const normalizedType = this.normalizeFieldTypeInput(normalizedRow.type);
      if (!normalizedRow.label) {
        baseErrors.push(`Row ${rowNumber}: label is required.`);
      }

      if (!normalizedRow.type) {
        baseErrors.push(`Row ${rowNumber}: type is required.`);
      }

      if (!normalizedType) {
        baseErrors.push(
          `Row ${rowNumber}: unsupported field type "${normalizedRow.type || "blank"}".`
        );
      } else {
        normalizedRow.type = normalizedType;
      }

      const apiNameKey = (normalizedRow.apiName || "").trim().toLowerCase();
      if (!apiNameKey) {
        baseErrors.push(`Row ${rowNumber}: API name is required.`);
      } else {
        if (seenApiNames.has(apiNameKey)) {
          const firstRow = seenApiNames.get(apiNameKey);
          baseErrors.push(
            `Row ${rowNumber}: duplicate API name "${normalizedRow.apiName}" also appears in row ${firstRow}.`
          );
        } else {
          seenApiNames.set(apiNameKey, rowNumber);
        }

        if (existingFieldApiNames.has(apiNameKey)) {
          baseErrors.push(
            `Row ${rowNumber}: field "${normalizedRow.apiName}" already exists on this object.`
          );
        }
      }

      this.validateRowTypeDetails(normalizedRow, rowNumber, baseErrors);

      return {
        ...normalizedRow,
        validationErrors: [...new Set(baseErrors)],
        baseValidationErrors: sourceRow.baseValidationErrors || []
      };
    });
  }

  validateRowTypeDetails(row, rowNumber, errors) {
    const typeDefinition = this.getTypeDefinition(row.type);
    const detailMode = typeDefinition.detailMode;

    if (detailMode === "picklist" && !(row.picklistValues || "").trim()) {
      errors.push(
        `Row ${rowNumber}: picklist values are required for ${typeDefinition.label}.`
      );
    }

    if (detailMode === "length" && !this.isPositiveInteger(row.length, false)) {
      errors.push(`Row ${rowNumber}: length must be a positive number.`);
    }

    if (detailMode === "longText") {
      if (!this.isPositiveInteger(row.length, false)) {
        errors.push(`Row ${rowNumber}: length must be a positive number.`);
      }

      if (!this.isPositiveInteger(row.visibleLines, false)) {
        errors.push(
          `Row ${rowNumber}: visible lines must be a positive number.`
        );
      }
    }

    if (detailMode === "number") {
      if (!this.isPositiveInteger(row.precision, false)) {
        errors.push(`Row ${rowNumber}: precision must be a positive number.`);
      }

      if (!this.isPositiveInteger(row.scale, true)) {
        errors.push(
          `Row ${rowNumber}: scale must be zero or a positive number.`
        );
      }

      const precision = Number(row.precision);
      const scale = Number(row.scale);
      if (
        Number.isFinite(precision) &&
        Number.isFinite(scale) &&
        scale > precision
      ) {
        errors.push(
          `Row ${rowNumber}: scale cannot be greater than precision.`
        );
      }
    }

    if (detailMode === "autoNumber") {
      if (!(row.displayFormat || "").trim()) {
        errors.push(
          `Row ${rowNumber}: display format is required for Auto Number.`
        );
      }

      if (!this.isPositiveInteger(row.startingNumber, true)) {
        errors.push(
          `Row ${rowNumber}: starting number must be zero or a positive number.`
        );
      }
    }

    if (row.externalId && !["Text", "Number", "Email"].includes(row.type)) {
      errors.push(
        `Row ${rowNumber}: External ID is supported only for Text, Number, and Email.`
      );
    }

    if (row.unique && !["Text", "Number", "Email"].includes(row.type)) {
      errors.push(
        `Row ${rowNumber}: Unique is supported only for Text, Number, and Email.`
      );
    }
  }

  isPositiveInteger(value, allowZero) {
    if (value === undefined || value === null || value === "") {
      return false;
    }

    const number = Number(value);
    if (!Number.isInteger(number)) {
      return false;
    }

    return allowZero ? number >= 0 : number > 0;
  }

  normalizeFieldTypeInput(rawType) {
    const normalized = (rawType || "").trim().toLowerCase();

    if (!normalized) {
      return "";
    }

    if (FIELD_TYPE_ALIASES[normalized]) {
      return FIELD_TYPE_ALIASES[normalized];
    }

    const exactMatch = FIELD_TYPE_OPTIONS.find(
      (option) =>
        option.value.toLowerCase() === normalized ||
        option.label.toLowerCase() === normalized
    );

    return exactMatch ? exactMatch.value : "";
  }

  normalizeDataTypeValue(rawDataType) {
    const rawValue = (rawDataType || "").trim();
    if (!rawValue) {
      return "";
    }

    const normalizedKey = rawValue.toLowerCase().replace(/[^a-z0-9]/g, "");
    if (DATA_TYPE_CANONICAL_VALUE_BY_KEY[normalizedKey]) {
      return DATA_TYPE_CANONICAL_VALUE_BY_KEY[normalizedKey];
    }

    return rawValue;
  }

  getDataTypeLabel(dataTypeValue) {
    return DATA_TYPE_LABEL_BY_VALUE[dataTypeValue] || dataTypeValue;
  }

  extractDurableIdToken(durableId) {
    const raw = (durableId || "").trim();
    if (!raw) {
      return "";
    }

    const separatorIndex = raw.indexOf(".");
    return separatorIndex >= 0 ? raw.substring(separatorIndex + 1) : raw;
  }

  resolveFieldEditKey(field) {
    const customFieldId = (field?.customFieldId || "").trim();
    if (customFieldId) {
      return customFieldId;
    }

    const durableIdToken = this.extractDurableIdToken(field?.durableId);
    if (durableIdToken) {
      return durableIdToken;
    }

    return (field?.apiName || "").trim();
  }

  resolveFieldNavigationKey(field) {
    const customFieldId = (field?.customFieldId || "").trim();
    if (customFieldId) {
      return customFieldId;
    }

    const durableIdToken = this.extractDurableIdToken(field?.durableId);
    if (durableIdToken) {
      return durableIdToken;
    }

    return (field?.apiName || "").trim();
  }

  getTypeDefinition(typeValue) {
    return (
      FIELD_TYPE_LOOKUP[typeValue] || {
        label: typeValue || "Unknown",
        value: typeValue || "",
        detailMode: "none"
      }
    );
  }

  getDefaultValuesForType(typeValue) {
    const typeDefinition = this.getTypeDefinition(typeValue);
    const defaults = {
      length: undefined,
      precision: undefined,
      scale: undefined,
      picklistValues: "",
      visibleLines: undefined,
      displayFormat: undefined,
      startingNumber: undefined,
      defaultValue: false,
      unique: false,
      externalId: false
    };

    if (typeDefinition.detailMode === "length") {
      defaults.length = typeDefinition.length;
    }

    if (typeDefinition.detailMode === "number") {
      defaults.precision = typeDefinition.precision;
      defaults.scale = typeDefinition.scale;
    }

    if (typeDefinition.detailMode === "longText") {
      defaults.length = typeDefinition.length;
      defaults.visibleLines = typeDefinition.visibleLines;
    }

    if (typeDefinition.detailMode === "picklist") {
      defaults.picklistValues = "";
    }

    if (typeDefinition.detailMode === "autoNumber") {
      defaults.displayFormat = typeDefinition.displayFormat || "AUTO-{0000}";
      defaults.startingNumber = typeDefinition.startingNumber ?? 1;
    }

    return defaults;
  }

  getDefaultManualRowValues() {
    return this.getDefaultValuesForType(DEFAULT_MANUAL_ROW.type);
  }

  createRowId(index) {
    this._rowSequence = (this._rowSequence || 0) + 1;
    return `row-${Date.now()}-${index}-${this._rowSequence}`;
  }

  getCsvExtraLabel(row) {
    if (row.type === "AutoNumber") {
      return `Format ${row.displayFormat || "AUTO-{0000}"}, Start ${row.startingNumber ?? 1}`;
    }

    if (row.picklistValues) {
      return row.picklistValues;
    }

    if (row.length !== undefined && row.length !== null) {
      if (row.visibleLines !== undefined && row.visibleLines !== null) {
        return `Length ${row.length}, ${row.visibleLines} lines`;
      }

      return `Length ${row.length}`;
    }

    if (row.precision !== undefined && row.precision !== null) {
      return `Precision ${row.precision}, Scale ${row.scale}`;
    }

    if (row.visibleLines !== undefined && row.visibleLines !== null) {
      return `${row.visibleLines} lines`;
    }

    return "No extra details";
  }

  reduceError(error) {
    return error?.body?.message || error?.message || "Unknown error";
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

  @wire(getObjectFields, { objectName: "$_objectName" })
  wiredFields(response) {
    this.wiredFieldsResult = response;
    const { data, error } = response;

    if (data) {
      this.allFields = (data || []).map((field) => {
        const dataType = this.normalizeDataTypeValue(field.dataType);

        return {
          ...field,
          dataType,
          durableIdToken: this.extractDurableIdToken(field.durableId)
        };
      });
      this.error = undefined;
    } else if (error) {
      this.allFields = [];
      this.error = error;
      console.error(error);
    }
  }
}