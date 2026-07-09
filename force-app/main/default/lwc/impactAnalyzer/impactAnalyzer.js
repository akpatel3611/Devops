const TYPE_CODE_BY_NAME = {
  ApexClass: "Apex",
  Dashboard: "Dash",
  Flow: "Flw",
  Formula: "Fml",
  PageLayout: "PL",
  ProcessBuilder: "PB",
  Report: "Rprt",
  ValidationRule: "VR",
  WorkflowRule: "WF"
};

function collectSearchableParts(value, parts) {
  if (value === null || value === undefined) {
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item) => collectSearchableParts(item, parts));
    return;
  }

  if (typeof value === "object") {
    Object.values(value).forEach((item) => collectSearchableParts(item, parts));
    return;
  }

  parts.push(String(value));
}

function buildSearchableText(value) {
  const parts = [];

  collectSearchableParts(value, parts);

  return parts.join(" ").toLowerCase();
}

function buildTargetTerms(target) {
  if (!target) {
    return [];
  }

  if (target.type === "field") {
    return [target.fieldApiName];
  }

  return [target.apiName, target.name];
}

function hasTargetMatch(target, source, options = {}) {
  if (!target) {
    return false;
  }

  if (options.alwaysMatch) {
    return true;
  }

  const searchableText = buildSearchableText(source);

  return buildTargetTerms(target).some(
    (term) => term && searchableText.includes(String(term).toLowerCase())
  );
}

function createImpactItem(config) {
  return {
    type: config.type,
    name: config.name || config.type,
    description: config.description || "",
    severity: config.severity,
    isActive: config.isActive !== false
  };
}

function addImpactItem(target, bucketState, config) {
  const item = createImpactItem(config);
  const itemKey = `${item.type}:${item.name}:${item.severity}`;

  if (bucketState.seen.has(itemKey)) {
    return;
  }

  bucketState.seen.add(itemKey);
  bucketState[item.severity].push(item);
}

function isEmptyLayout(layout) {
  const sectionCount = Array.isArray(layout?.sections) ? layout.sections.length : 0;
  const fieldCount = Array.isArray(layout?.fields) ? layout.fields.length : 0;

  return sectionCount === 0 && fieldCount === 0;
}

function addFlowDependencies(target, bucketState, flows) {
  (flows || []).forEach((flow) => {
    if (!hasTargetMatch(target, flow, { alwaysMatch: target.type === "object" })) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "Flow",
      name: flow.label || flow.name || flow.apiName || "Flow",
      description:
        target.type === "field"
          ? `${target.fieldApiName} is referenced by this flow. Deleting the field can break automation.`
          : `${target.apiName} is referenced by this flow. Deleting the object can break automation.`,
      severity: "critical",
      isActive: flow.isActive !== false
    });
  });
}

function addValidationRuleDependencies(target, bucketState, validationRules) {
  (validationRules || []).forEach((rule) => {
    if (!hasTargetMatch(target, rule, { alwaysMatch: target.type === "object" })) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "ValidationRule",
      name: rule.name || "Validation Rule",
      description:
        target.type === "field"
          ? `${target.fieldApiName} is referenced in this validation rule formula.`
          : `${target.apiName} has validation logic that will be removed with the object.`,
      severity:
        target.type === "object"
          ? "critical"
          : rule.isActive === false
            ? "warning"
            : "critical",
      isActive: rule.isActive !== false
    });
  });
}

function addApexDependencies(target, bucketState, apexClasses) {
  (apexClasses || []).forEach((apexClass) => {
    if (!hasTargetMatch(target, apexClass)) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "ApexClass",
      name: apexClass.name || "Apex Class",
      description:
        target.type === "field"
          ? `${target.fieldApiName} appears in this Apex class body.`
          : `${target.apiName} appears in this Apex class body.`,
      severity: "critical"
    });
  });
}

function addReportDependencies(target, bucketState, reports) {
  (reports || []).forEach((report) => {
    if (!hasTargetMatch(target, report)) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "Report",
      name: report.name || "Report",
      description:
        target.type === "field"
          ? `${target.fieldApiName} appears in this report's columns, filters, or metadata.`
          : `${target.apiName} appears in this report's metadata.`,
      severity: "warning"
    });
  });
}

function addDashboardDependencies(target, bucketState, dashboards) {
  (dashboards || []).forEach((dashboard) => {
    if (!hasTargetMatch(target, dashboard)) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "Dashboard",
      name: dashboard.name || dashboard.title || "Dashboard",
      description:
        target.type === "field"
          ? `${target.fieldApiName} appears in dashboard metadata or an associated report reference.`
          : `${target.apiName} appears in dashboard metadata or an associated report reference.`,
      severity: "warning"
    });
  });
}

function addPageLayoutDependencies(target, bucketState, pageLayouts) {
  (pageLayouts || []).forEach((layout) => {
    if (
      target.type === "field" &&
      !hasTargetMatch(target, layout)
    ) {
      return;
    }

    const emptyLayout = isEmptyLayout(layout);

    addImpactItem(target, bucketState, {
      type: "PageLayout",
      name: layout.name || layout.recordType || "Page Layout",
      description:
        target.type === "field"
          ? `${target.fieldApiName} is on this page layout. Salesforce removes layout references automatically.`
          : emptyLayout
            ? "This layout is empty and can be removed safely with the object."
            : `${target.apiName} has a populated page layout that will be removed with the object.`,
      severity:
        target.type === "field"
          ? "safe"
          : emptyLayout
            ? "safe"
            : "critical"
    });
  });
}

function addWorkflowDependencies(target, bucketState, workflowRules) {
  (workflowRules || []).forEach((workflowRule) => {
    if (!hasTargetMatch(target, workflowRule, { alwaysMatch: target.type === "object" })) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "WorkflowRule",
      name: workflowRule.name || "Workflow Rule",
      description:
        target.type === "field"
          ? `${target.fieldApiName} is referenced by this workflow rule.`
          : `${target.apiName} is referenced by this workflow rule.`,
      severity:
        target.type === "object"
          ? "critical"
          : workflowRule.isActive === false
            ? "warning"
            : "critical",
      isActive: workflowRule.isActive !== false
    });
  });
}

function addFormulaDependencies(target, bucketState, formulas) {
  (formulas || []).forEach((formula) => {
    if (!hasTargetMatch(target, formula, { alwaysMatch: target.type === "object" })) {
      return;
    }

    addImpactItem(target, bucketState, {
      type: "Formula",
      name: formula.name || formula.apiName || "Formula Field",
      description:
        target.type === "field"
          ? `${target.fieldApiName} is referenced by this formula field.`
          : `${target.apiName} is referenced by this formula field.`,
      severity: "critical"
    });
  });
}

function sortItems(items) {
  return [...items].sort((left, right) =>
    (left.name || "").localeCompare(right.name || "")
  );
}

export function analyzeImpact(target, allMetadata = {}) {
  const bucketState = {
    critical: [],
    warning: [],
    safe: [],
    seen: new Set()
  };

  addFlowDependencies(target, bucketState, allMetadata.flows);
  addValidationRuleDependencies(
    target,
    bucketState,
    allMetadata.validationRules
  );
  addApexDependencies(target, bucketState, allMetadata.apexClasses);
  addReportDependencies(target, bucketState, allMetadata.reports);
  addDashboardDependencies(target, bucketState, allMetadata.dashboards);
  addPageLayoutDependencies(target, bucketState, allMetadata.pageLayouts);
  addWorkflowDependencies(
    target,
    bucketState,
    allMetadata.workflowRules
  );
  addFormulaDependencies(target, bucketState, allMetadata.formulas);

  const critical = sortItems(bucketState.critical);
  const warning = sortItems(bucketState.warning);
  const safe = sortItems(bucketState.safe);

  return {
    total: critical.length + warning.length + safe.length,
    critical,
    warning,
    safe,
    blocked: critical.length > 0
  };
}

export function getImpactTypeCode(type) {
  return TYPE_CODE_BY_NAME[type] || type;
}

export function getImpactSubtitle(target, analysis) {
  if (!target) {
    return "";
  }

  const criticalCount = analysis?.critical?.length || 0;
  const issueLabel =
    criticalCount === 1 ? "critical issue" : "critical issues";

  if (target.type === "field") {
    return `Field: ${target.fieldApiName} on ${target.objectApiName} · ${criticalCount} ${issueLabel}`;
  }

  return `Object: ${target.apiName} · ${criticalCount} ${issueLabel}`;
}