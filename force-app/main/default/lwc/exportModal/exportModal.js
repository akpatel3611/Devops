import { LightningElement, api } from "lwc";

import getAllObjects from "@salesforce/apex/ObjectManagerController.getAllObjects";
import getDocumentationData from "@salesforce/apex/ObjectManagerController.getDocumentationData";

import {
  buildDownloadArtifact,
  buildPreviewContent,
  downloadArtifact,
  ensureExportLibraries,
  EXPORT_FORMAT_OPTIONS,
  EXPORT_SECTION_OPTIONS,
  getDefaultIncludeSections
} from "c/docExporter";

export default class ExportModal extends LightningElement {
  @api mode = "single";

  @api objectId;

  objects = [];

  isLoading = true;

  isPreparingDownload = false;

  selectedFormat = "md";

  includeSections = getDefaultIncludeSections();

  preparedDownload;

  latestPrepareRequest = 0;

  errorMessage;

  connectedCallback() {
    this.loadDocumentation();
  }

  get subtitle() {
    if (this.mode === "all") {
      const count = this.objects.length;

      return `All Objects (${count} object${count === 1 ? "" : "s"})`;
    }

    const objectData = this.objects[0];

    if (!objectData) {
      return this.objectId || "";
    }

    return `${objectData.apiName} - ${objectData.type}`;
  }

  get normalizedSectionOptions() {
    return EXPORT_SECTION_OPTIONS.map((sectionOption) => ({
      ...sectionOption,
      checked: this.includeSections[sectionOption.key]
    }));
  }

  get formatOptions() {
    return EXPORT_FORMAT_OPTIONS.map((formatOption) => ({
      ...formatOption,
      className:
        formatOption.key === this.selectedFormat
          ? "format-option format-option_selected"
          : "format-option"
    }));
  }

  get previewText() {
    if (this.isLoading) {
      return "Loading documentation preview...";
    }

    if (!this.objects.length) {
      return "No documentation data available.";
    }

    return buildPreviewContent(this.objects, {
      format: this.selectedFormat,
      includeSections: this.includeSections
    });
  }

  get generateButtonLabel() {
    if (this.isPreparingDownload) {
      return "Preparing...";
    }

    return "Generate & Download";
  }

  get isGenerateDisabled() {
    return (
      this.isLoading ||
      this.isPreparingDownload ||
      !this.preparedDownload
    );
  }

  async loadDocumentation() {
    this.isLoading = true;
    this.errorMessage = undefined;

    try {
      const objectNames = await this.resolveObjectNames();

      this.objects = await getDocumentationData({
        objectNames
      });
      this.prepareDownload();
    } catch (error) {
      this.objects = [];
      this.preparedDownload = undefined;
      this.errorMessage = this.reduceError(error);
      console.error(error);
    } finally {
      this.isLoading = false;
    }
  }

  async resolveObjectNames() {
    if (this.mode === "all") {
      const objects = await getAllObjects();

      return objects.map((objectInfo) => objectInfo.apiName);
    }

    return this.objectId ? [this.objectId] : [];
  }

  handleSectionToggle(event) {
    const sectionKey = event.target.dataset.key;

    this.includeSections = {
      ...this.includeSections,
      [sectionKey]: event.target.checked
    };

    this.prepareDownload();
  }

  handleFormatChange(event) {
    this.selectedFormat = event.currentTarget.dataset.format;
    this.prepareDownload();
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleGenerate() {
    if (!this.preparedDownload) {
      this.errorMessage = this.isPreparingDownload
        ? "Preparing export file. Try again in a moment."
        : "The export file is not ready.";
      return;
    }

    this.errorMessage = undefined;

    try {
      downloadArtifact(this.preparedDownload);
      this.handleCancel();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      console.error(error);
    }
  }

  async prepareDownload() {
    const requestId = ++this.latestPrepareRequest;

    if (!this.objects.length) {
      this.preparedDownload = undefined;
      this.isPreparingDownload = false;
      return;
    }

    this.preparedDownload = undefined;
    this.isPreparingDownload = true;
    this.errorMessage = undefined;

    try {
      await ensureExportLibraries(this, this.selectedFormat);

      const preparedDownload = await buildDownloadArtifact(this.objects, {
        format: this.selectedFormat,
        includeSections: this.includeSections
      });

      if (requestId !== this.latestPrepareRequest) {
        return;
      }

      this.preparedDownload = preparedDownload;
    } catch (error) {
      if (requestId !== this.latestPrepareRequest) {
        return;
      }

      this.preparedDownload = undefined;
      this.errorMessage = this.reduceError(error);
      console.error(error);
    } finally {
      if (requestId === this.latestPrepareRequest) {
        this.isPreparingDownload = false;
      }
    }
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

    return "Unable to generate documentation.";
  }
}