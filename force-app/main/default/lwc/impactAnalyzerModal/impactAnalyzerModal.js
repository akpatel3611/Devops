import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";

import getImpactAnalysisMetadata from "@salesforce/apex/ObjectManagerController.getImpactAnalysisMetadata";

import {
  analyzeImpact,
  getImpactSubtitle,
  getImpactTypeCode
} from "c/impactAnalyzer";

const SEVERITY_CARD_CONFIG = [
  { key: "critical", label: "Critical", className: "summary-card summary-card_critical" },
  { key: "warning", label: "Warning", className: "summary-card summary-card_warning" },
  { key: "safe", label: "Safe", className: "summary-card summary-card_safe" }
];

export default class ImpactAnalyzerModal extends LightningElement {
  _target;

  analysis;

  isLoading = true;

  errorMessage;

  @api
  get target() {
    return this._target;
  }

  set target(value) {
    this._target = value;

    if (this.isConnected) {
      this.loadAnalysis();
    }
  }

  connectedCallback() {
    this.loadAnalysis();
  }

  get title() {
    const dependencyCount = this.analysis?.total || 0;

    return `Delete impact - ${dependencyCount} dependencies found`;
  }

  get subtitle() {
    return getImpactSubtitle(this._target, this.analysis);
  }

  get summaryCards() {
    return SEVERITY_CARD_CONFIG.map((cardConfig) => ({
      ...cardConfig,
      count: this.analysis?.[cardConfig.key]?.length || 0
    }));
  }

  get dependencyItems() {
    if (!this.analysis) {
      return [];
    }

    return [...this.analysis.critical, ...this.analysis.warning, ...this.analysis.safe].map(
      (item) => ({
        ...item,
        key: `${item.type}-${item.name}-${item.severity}`,
        severityLabel:
          item.severity.charAt(0).toUpperCase() + item.severity.slice(1),
        severityClass: `severity-pill severity-pill_${item.severity}`,
        rowClass:
          item.severity === "safe"
            ? "dependency-item"
            : `dependency-item dependency-item_${item.severity}`,
        typeCode: getImpactTypeCode(item.type)
      })
    );
  }

  get hasDependencies() {
    return (this.analysis?.total || 0) > 0;
  }

  get showBlockedNote() {
    return (this.analysis?.critical?.length || 0) > 0;
  }

  get blockedMessage() {
    const criticalCount = this.analysis?.critical?.length || 0;
    const issueLabel = criticalCount === 1 ? "dependency" : "dependencies";

    return `Delete is blocked until ${criticalCount} critical ${issueLabel} are fixed.`;
  }

  get deleteButtonLabel() {
    if (this.showBlockedNote) {
      return "Delete (blocked)";
    }

    if ((this.analysis?.warning?.length || 0) > 0) {
      return "Delete anyway";
    }

    return "Delete";
  }

  get deleteButtonClass() {
    if (this.showBlockedNote) {
      return "modal-action-button modal-action-button_blocked";
    }

    if ((this.analysis?.warning?.length || 0) > 0) {
      return "modal-action-button modal-action-button_warning";
    }

    return "modal-action-button modal-action-button_destructive";
  }

  get isDeleteDisabled() {
    return this.isLoading || Boolean(this.errorMessage) || this.showBlockedNote;
  }

  async loadAnalysis() {
    if (!this._target) {
      this.analysis = {
        total: 0,
        critical: [],
        warning: [],
        safe: [],
        blocked: false
      };
      this.isLoading = false;
      this.errorMessage = undefined;
      return;
    }

    this.isLoading = true;
    this.errorMessage = undefined;

    try {
      const metadata = await getImpactAnalysisMetadata({
        targetType: this._target.type,
        apiName: this._target.fieldApiName || this._target.apiName,
        objectApiName: this._target.objectApiName || this._target.apiName
      });

      this.analysis = analyzeImpact(this._target, metadata || {});
    } catch (error) {
      this.analysis = undefined;
      this.errorMessage = this.reduceError(error);
      console.error(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleRetry() {
    this.loadAnalysis();
  }

  async handleDelete() {
    if (this.isDeleteDisabled) {
      return;
    }

    const hasWarnings = (this.analysis?.warning?.length || 0) > 0;
    const confirmConfig = {
      label: hasWarnings ? "Delete anyway" : "Confirm Delete",
      message: hasWarnings
        ? "This delete has warnings. Continue anyway?"
        : "Delete this metadata item now?"
    };

    if (hasWarnings) {
      confirmConfig.theme = "warning";
    }

    const confirmResult = await LightningConfirm.open(confirmConfig);

    if (!confirmResult) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent("confirmdelete", {
        detail: {
          target: this._target,
          analysis: this.analysis
        }
      })
    );
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

    return "Unable to analyze dependencies.";
  }
}