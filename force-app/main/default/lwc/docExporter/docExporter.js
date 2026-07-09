import { loadScript } from "lightning/platformResourceLoader";

import docxLibrary from "@salesforce/resourceUrl/docx";
import fileSaverLibrary from "@salesforce/resourceUrl/fileSaver";
import jspdfLibrary from "@salesforce/resourceUrl/jspdf";

const FORMAT_EXTENSION_BY_KEY = {
  md: "md",
  pdf: "pdf",
  docx: "docx"
};

const DOCX_DOWNLOAD_MIME_TYPE = "application/octet-stream";
const MARKDOWN_DOWNLOAD_MIME_TYPE = "text/markdown";

export const EXPORT_FORMAT_OPTIONS = [
  {
    key: "md",
    label: "Markdown (.md)"
  },
  {
    key: "pdf",
    label: "PDF (.pdf)"
  },
  {
    key: "docx",
    label: "Word (.docx)"
  }
];

export const EXPORT_SECTION_OPTIONS = [
  {
    key: "fields",
    label: "Fields & types"
  },
  {
    key: "validations",
    label: "Validation rules"
  },
  {
    key: "relationships",
    label: "Relationships"
  },
  {
    key: "picklists",
    label: "Picklist values"
  },
  {
    key: "layouts",
    label: "Page layouts"
  },
  {
    key: "details",
    label: "Details"
  },
  {
    key: "flows",
    label: "Flows"
  },
  {
    key: "lightningRecordPages",
    label: "Lightning Record Pages"
  },
  {
    key: "buttonsLinksActions",
    label: "Buttons, Links, and Actions"
  },
  {
    key: "compactLayouts",
    label: "Compact Layouts"
  },
  {
    key: "fieldSets",
    label: "Field Sets"
  },
  {
    key: "objectLimits",
    label: "Object Limits"
  },
  {
    key: "recordTypes",
    label: "Record Types"
  },
  {
    key: "relatedLookupFilters",
    label: "Related Lookup Filters"
  },
  {
    key: "searchLayouts",
    label: "Search Layouts"
  },
  {
    key: "listViewButtonLayout",
    label: "List View Button Layout"
  },
  {
    key: "hierarchyColumns",
    label: "Hierarchy Columns"
  },
  {
    key: "scopingRules",
    label: "Scoping Rules"
  }
];

let pdfLibraryPromise;
let wordLibraryPromise;

export function getDefaultIncludeSections() {
  return EXPORT_SECTION_OPTIONS.reduce(
    (includeSections, sectionOption) => ({
      ...includeSections,
      [sectionOption.key]: true
    }),
    {}
  );
}

export function buildPreviewContent(objects, options) {
  const format = options?.format || "md";
  const content =
    format === "md"
      ? buildMarkdownDocument(objects, options)
      : buildReadablePreviewDocument(objects, options, format);
  const lines = content.split("\n");

  if (lines.length <= 36 && content.length <= 1800) {
    return content;
  }

  return `${lines.slice(0, 36).join("\n")}\n\n...`;
}

export async function ensureExportLibraries(component, format) {
  if (format === "pdf") {
    if (!pdfLibraryPromise) {
      pdfLibraryPromise = loadScript(component, jspdfLibrary);
    }

    return pdfLibraryPromise;
  }

  if (format === "docx") {
    if (!wordLibraryPromise) {
      wordLibraryPromise = Promise.all([
        loadScript(component, docxLibrary),
        loadScript(component, fileSaverLibrary)
      ]);
    }

    return wordLibraryPromise;
  }

  return Promise.resolve();
}

export async function generateDoc(objects, options) {
  const artifact = await buildDownloadArtifact(objects, options);

  downloadArtifact(artifact);
}

export async function buildDownloadArtifact(objects, options) {
  const format = options?.format || "md";
  const normalizedObjects = Array.isArray(objects) ? objects : [];

  if (!normalizedObjects.length) {
    throw new Error("Documentation data was not loaded.");
  }

  if (format === "md") {
    const markdown = buildMarkdownDocument(normalizedObjects, options);

    return {
      blob: new Blob([markdown], { type: MARKDOWN_DOWNLOAD_MIME_TYPE }),
      fileName: buildFileName(normalizedObjects, format)
    };
  }

  if (format === "pdf") {
    return {
      blob: buildPdfBlob(normalizedObjects, options),
      fileName: buildFileName(normalizedObjects, format)
    };
  }

  if (format === "docx") {
    return {
      blob: await buildWordDocumentBlob(normalizedObjects, options),
      fileName: buildFileName(normalizedObjects, format)
    };
  }

  throw new Error(`Unsupported export format: ${format}`);
}

export function downloadArtifact(artifact) {
  if (!artifact?.blob || !artifact?.fileName) {
    throw new Error("The export file is not ready.");
  }

  downloadBlob(artifact.blob, artifact.fileName);
}

export function buildMarkdownDocument(objects, options) {
  const normalizedObjects = Array.isArray(objects) ? objects : [];
  const includeSections = normalizeIncludeSections(options?.includeSections);
  const lines = [];

  normalizedObjects.forEach((objectData, index) => {
    if (index > 0) {
      lines.push("", "---", "");
    }

    lines.push(`# ${objectData.apiName || objectData.name || "Object"}`);

    if (objectData.name || objectData.type) {
      lines.push(
        "",
        [objectData.name, objectData.type].filter(Boolean).join(" - ")
      );
    }

    appendMarkdownSections(lines, objectData, includeSections);
  });

  return lines.join("\n").trim();
}

function appendMarkdownSections(lines, objectData, includeSections) {
  EXPORT_SECTION_OPTIONS.forEach((sectionOption) => {
    if (!includeSections[sectionOption.key]) {
      return;
    }

    const sectionData = resolveSectionData(objectData, sectionOption.key);

    if (!sectionData) {
      return;
    }

    lines.push("", `## ${sectionData.title}`, "");

    if (sectionData.type === "table") {
      lines.push(...buildMarkdownTable(sectionData.columns, sectionData.rows));
      return;
    }

    if (sectionData.type === "message") {
      lines.push(sectionData.message || "No data available.");
      return;
    }

    if (sectionData.type === "picklists") {
      lines.push(...buildPicklistMarkdown(sectionData.entries));
      return;
    }

    if (sectionData.type === "layouts") {
      lines.push(...buildLayoutMarkdown(sectionData.layouts));
    }
  });
}

function buildMarkdownTable(columns, rows) {
  const normalizedColumns = Array.isArray(columns) ? columns : [];
  const normalizedRows = Array.isArray(rows) ? rows : [];

  if (!normalizedColumns.length) {
    return ["No data available."];
  }

  if (!normalizedRows.length) {
    return ["No data available."];
  }

  const headerRow = `| ${normalizedColumns
    .map((column) => escapeMarkdownCell(column.label))
    .join(" | ")} |`;

  const separatorRow = `| ${normalizedColumns.map(() => "---").join(" | ")} |`;

  const bodyRows = normalizedRows.map((row) => {
    const values = normalizedColumns.map((column) =>
      escapeMarkdownCell(formatCellValue(row[column.key]))
    );

    return `| ${values.join(" | ")} |`;
  });

  return [headerRow, separatorRow, ...bodyRows];
}

function buildPicklistMarkdown(entries) {
  const normalizedEntries = Array.isArray(entries) ? entries : [];

  if (!normalizedEntries.length) {
    return ["No picklist values available."];
  }

  const lines = [];

  normalizedEntries.forEach((entry, index) => {
    if (index > 0) {
      lines.push("");
    }

    lines.push(`### ${entry.fieldApiName}`, "");

    if (!entry.values.length) {
      lines.push("No values available.");
      return;
    }

    entry.values.forEach((value) => {
      lines.push(`- ${value}`);
    });
  });

  return lines;
}

function buildLayoutMarkdown(layouts) {
  const normalizedLayouts = Array.isArray(layouts) ? layouts : [];

  if (!normalizedLayouts.length) {
    return ["No page layout metadata available."];
  }

  const lines = [];

  normalizedLayouts.forEach((layout, index) => {
    if (index > 0) {
      lines.push("");
    }

    lines.push(`### ${layout.name || layout.recordType || layout.layoutId}`);
    lines.push("");
    lines.push(`- Record Type: ${layout.recordType || "N/A"}`);
    lines.push(`- Layout ID: ${layout.layoutId || "N/A"}`);
    lines.push(`- Layout Type: ${layout.layoutType || "N/A"}`);

    if (!layout.sections.length) {
      lines.push("- Fields: None");
      return;
    }

    lines.push("");

    layout.sections.forEach((section) => {
      lines.push(`#### ${section.heading || "Layout Section"}`, "");

      if (!section.fields.length) {
        lines.push("No fields available.", "");
        return;
      }

      section.fields.forEach((fieldName) => {
        lines.push(`- ${fieldName}`);
      });

      lines.push("");
    });
  });

  return trimTrailingBlankLines(lines);
}

function trimTrailingBlankLines(lines) {
  const trimmedLines = [...lines];

  while (trimmedLines.length && trimmedLines[trimmedLines.length - 1] === "") {
    trimmedLines.pop();
  }

  return trimmedLines;
}

function resolveSectionData(objectData, sectionKey) {
  if (sectionKey === "fields") {
    return {
      title: "Fields & Types",
      type: "table",
      columns: [
        {
          key: "apiName",
          label: "API Name"
        },
        {
          key: "label",
          label: "Label"
        },
        {
          key: "type",
          label: "Data Type"
        },
        {
          key: "required",
          label: "Required"
        }
      ],
      rows: (objectData.fields || []).map((field) => ({
        apiName: field.apiName,
        label: field.label,
        type: field.type,
        required: formatBoolean(field.required)
      }))
    };
  }

  if (sectionKey === "validations") {
    return {
      title: "Validation Rules",
      type: "table",
      columns: [
        {
          key: "name",
          label: "Rule Name"
        },
        {
          key: "formula",
          label: "Formula"
        },
        {
          key: "errorMessage",
          label: "Error Message"
        }
      ],
      rows: (objectData.validationRules || []).map((rule) => ({
        name: rule.name,
        formula: rule.formula,
        errorMessage: rule.errorMessage
      }))
    };
  }

  if (sectionKey === "relationships") {
    return {
      title: "Relationships",
      type: "table",
      columns: [
        {
          key: "name",
          label: "Field"
        },
        {
          key: "type",
          label: "Type"
        },
        {
          key: "relatedObject",
          label: "Related Object"
        }
      ],
      rows: objectData.relationships || []
    };
  }

  if (sectionKey === "picklists") {
    return {
      title: "Picklist Values",
      type: "picklists",
      entries: Object.entries(objectData.picklistValues || {}).map(
        ([fieldApiName, values]) => ({
          fieldApiName,
          values: Array.isArray(values) ? values : []
        })
      )
    };
  }

  if (sectionKey === "layouts") {
    return {
      title: "Page Layouts",
      type: "layouts",
      layouts: (objectData.pageLayouts || []).map((layout) => ({
        ...layout,
        sections: Array.isArray(layout.sections) ? layout.sections : []
      }))
    };
  }

  return (
    (objectData.additionalSections || []).find(
      (section) => section.key === sectionKey
    ) || null
  );
}

function normalizeIncludeSections(includeSections) {
  const defaultSections = getDefaultIncludeSections();

  return {
    ...defaultSections,
    ...(includeSections || {})
  };
}

function formatCellValue(value) {
  if (Array.isArray(value)) {
    return value.join(", ");
  }

  if (value === true || value === false) {
    return formatBoolean(value);
  }

  if (value === null || value === undefined || value === "") {
    return "N/A";
  }

  return String(value);
}

function escapeMarkdownCell(value) {
  return String(value || "")
    .replace(/\|/g, "\\|")
    .replace(/\r?\n/g, "<br/>");
}

function buildPdfBlob(objects, options) {
  const pdfApi = window.jspdf;
  const PdfConstructor = pdfApi?.jsPDF;

  if (!PdfConstructor) {
    throw new Error("The PDF export library did not load correctly.");
  }

  const documentText = buildMarkdownDocument(objects, options);
  const pdfDocument = new PdfConstructor({
    orientation: "portrait",
    unit: "pt",
    format: "a4"
  });
  const pageWidth = pdfDocument.internal.pageSize.getWidth();
  const pageHeight = pdfDocument.internal.pageSize.getHeight();
  const horizontalPadding = 40;
  const maxTextWidth = pageWidth - horizontalPadding * 2;
  let currentY = 48;

  documentText.split("\n").forEach((line) => {
    if (!line.trim()) {
      currentY += 10;
      return;
    }

    let text = line;
    let fontSize = 11;
    let fontStyle = "normal";

    if (line.startsWith("# ")) {
      text = line.replace(/^#\s+/, "");
      fontSize = 18;
      fontStyle = "bold";
    } else if (line.startsWith("## ")) {
      text = line.replace(/^##\s+/, "");
      fontSize = 14;
      fontStyle = "bold";
    } else if (line.startsWith("### ")) {
      text = line.replace(/^###\s+/, "");
      fontSize = 12;
      fontStyle = "bold";
    } else if (line.startsWith("#### ")) {
      text = line.replace(/^####\s+/, "");
      fontSize = 11;
      fontStyle = "bold";
    } else if (line.startsWith("|")) {
      if (/^\|\s*-/.test(line)) {
        return;
      }

      text = line.replace(/\|/g, "  ");
      fontSize = 10;
    }

    pdfDocument.setFont("helvetica", fontStyle);
    pdfDocument.setFontSize(fontSize);

    const wrappedLines = pdfDocument.splitTextToSize(text, maxTextWidth);
    const lineHeight = fontSize + 4;

    if (currentY + wrappedLines.length * lineHeight > pageHeight - 40) {
      pdfDocument.addPage();
      currentY = 48;
    }

    pdfDocument.text(wrappedLines, horizontalPadding, currentY);
    currentY += wrappedLines.length * lineHeight;
  });

  return pdfDocument.output("blob");
}

async function buildWordDocumentBlob(objects, options) {
  const docxApi = window.docx;

  if (!docxApi?.Document || !docxApi?.Packer) {
    throw new Error("The Word export library did not load correctly.");
  }

  const documentChildren = [];
  const includeSections = normalizeIncludeSections(options?.includeSections);

  objects.forEach((objectData, index) => {
    if (index > 0) {
      documentChildren.push(new docxApi.Paragraph({ text: "" }));
    }

    documentChildren.push(
      new docxApi.Paragraph({
        text: objectData.apiName || objectData.name || "Object",
        heading: docxApi.HeadingLevel.HEADING_1
      })
    );

    documentChildren.push(
      new docxApi.Paragraph({
        text: [objectData.name, objectData.type].filter(Boolean).join(" - ")
      })
    );

    EXPORT_SECTION_OPTIONS.forEach((sectionOption) => {
      if (!includeSections[sectionOption.key]) {
        return;
      }

      const sectionData = resolveSectionData(objectData, sectionOption.key);

      if (!sectionData) {
        return;
      }

      documentChildren.push(
        new docxApi.Paragraph({
          text: sectionData.title,
          heading: docxApi.HeadingLevel.HEADING_2
        })
      );

      if (sectionData.type === "table") {
        documentChildren.push(
          buildWordTable(docxApi, sectionData.columns, sectionData.rows)
        );
        return;
      }

      if (sectionData.type === "message") {
        documentChildren.push(
          new docxApi.Paragraph({
            text: sectionData.message || "No data available."
          })
        );
        return;
      }

      if (sectionData.type === "picklists") {
        appendWordPicklists(docxApi, documentChildren, sectionData.entries);
        return;
      }

      if (sectionData.type === "layouts") {
        appendWordLayouts(docxApi, documentChildren, sectionData.layouts);
      }
    });
  });

  const documentDefinition = new docxApi.Document({
    sections: [
      {
        children: documentChildren
      }
    ]
  });
  return buildWordBlob(docxApi, documentDefinition);
}

async function buildWordBlob(docxApi, documentDefinition) {
  if (typeof docxApi.Packer.toBlob === "function") {
    try {
      const blob = await docxApi.Packer.toBlob(documentDefinition);

      return normalizeBinaryBlob(blob, DOCX_DOWNLOAD_MIME_TYPE);
    } catch (error) {
      if (typeof docxApi.Packer.toBase64String !== "function") {
        throw error;
      }
    }
  }

  if (typeof docxApi.Packer.toBase64String !== "function") {
    throw new Error("The Word export library could not produce a file.");
  }

  const base64String = await docxApi.Packer.toBase64String(documentDefinition);

  return base64ToBlob(base64String, DOCX_DOWNLOAD_MIME_TYPE);
}

function buildWordTable(docxApi, columns, rows) {
  const normalizedColumns = Array.isArray(columns) ? columns : [];
  const normalizedRows = Array.isArray(rows) ? rows : [];

  if (!normalizedColumns.length || !normalizedRows.length) {
    return new docxApi.Paragraph({
      text: "No data available."
    });
  }

  const headerRow = new docxApi.TableRow({
    children: normalizedColumns.map(
      (column) =>
        new docxApi.TableCell({
          children: [
            new docxApi.Paragraph({
              children: [
                new docxApi.TextRun({
                  text: column.label,
                  bold: true
                })
              ]
            })
          ]
        })
    )
  });

  const bodyRows = normalizedRows.map(
    (row) =>
      new docxApi.TableRow({
        children: normalizedColumns.map(
          (column) =>
            new docxApi.TableCell({
              children: [
                new docxApi.Paragraph({
                  text: formatCellValue(row[column.key])
                })
              ]
            })
        )
      })
  );

  return new docxApi.Table({
    width: {
      size: 100,
      type: docxApi.WidthType.PERCENTAGE
    },
    rows: [headerRow, ...bodyRows]
  });
}

function appendWordPicklists(docxApi, children, entries) {
  const normalizedEntries = Array.isArray(entries) ? entries : [];

  if (!normalizedEntries.length) {
    children.push(
      new docxApi.Paragraph({
        text: "No picklist values available."
      })
    );
    return;
  }

  normalizedEntries.forEach((entry) => {
    children.push(
      new docxApi.Paragraph({
        text: entry.fieldApiName,
        heading: docxApi.HeadingLevel.HEADING_3
      })
    );

    if (!entry.values.length) {
      children.push(
        new docxApi.Paragraph({
          text: "No values available."
        })
      );
      return;
    }

    entry.values.forEach((value) => {
      children.push(
        new docxApi.Paragraph({
          text: value,
          bullet: {
            level: 0
          }
        })
      );
    });
  });
}

function appendWordLayouts(docxApi, children, layouts) {
  const normalizedLayouts = Array.isArray(layouts) ? layouts : [];

  if (!normalizedLayouts.length) {
    children.push(
      new docxApi.Paragraph({
        text: "No page layout metadata available."
      })
    );
    return;
  }

  normalizedLayouts.forEach((layout) => {
    children.push(
      new docxApi.Paragraph({
        text: layout.name || layout.recordType || layout.layoutId,
        heading: docxApi.HeadingLevel.HEADING_3
      })
    );

    children.push(
      new docxApi.Paragraph({
        text: `Record Type: ${layout.recordType || "N/A"}`
      })
    );
    children.push(
      new docxApi.Paragraph({
        text: `Layout ID: ${layout.layoutId || "N/A"}`
      })
    );
    children.push(
      new docxApi.Paragraph({
        text: `Layout Type: ${layout.layoutType || "N/A"}`
      })
    );

    if (!layout.sections.length) {
      children.push(
        new docxApi.Paragraph({
          text: "No fields available."
        })
      );
      return;
    }

    layout.sections.forEach((section) => {
      children.push(
        new docxApi.Paragraph({
          text: section.heading || "Layout Section",
          heading: docxApi.HeadingLevel.HEADING_4
        })
      );

      if (!section.fields.length) {
        children.push(
          new docxApi.Paragraph({
            text: "No fields available."
          })
        );
        return;
      }

      section.fields.forEach((fieldName) => {
        children.push(
          new docxApi.Paragraph({
            text: fieldName,
            bullet: {
              level: 0
            }
          })
        );
      });
    });
  });
}

function buildFileName(objects, format) {
  const normalizedObjects = Array.isArray(objects) ? objects : [];
  const baseName =
    normalizedObjects.length === 1
      ? `${normalizedObjects[0].apiName || "object"}-documentation`
      : "all-objects-documentation";

  return `${sanitizeFileName(baseName)}.${FORMAT_EXTENSION_BY_KEY[format]}`;
}

function sanitizeFileName(value) {
  return String(value || "documentation")
    .replace(/[\\/:*?"<>|]+/g, "-")
    .replace(/\s+/g, "-");
}

function downloadBlob(blob, fileName) {
  const downloadUrl = URL.createObjectURL(blob);
  const anchor = document.createElement("a");

  anchor.href = downloadUrl;
  anchor.download = fileName;
  anchor.rel = "noopener";
  anchor.style.display = "none";
  document.body.appendChild(anchor);
  anchor.click();

  // eslint-disable-next-line @lwc/lwc/no-async-operation
  window.setTimeout(() => {
    if (anchor.parentNode) {
      anchor.parentNode.removeChild(anchor);
    }

    URL.revokeObjectURL(downloadUrl);
  }, 1000);
}

function buildReadablePreviewDocument(objects, options, format) {
  const includeSections = normalizeIncludeSections(options?.includeSections);
  const heading =
    format === "pdf"
      ? "PDF Preview"
      : format === "docx"
        ? "Word Preview"
        : "Preview";
  const lines = [heading, ""];

  (Array.isArray(objects) ? objects : []).forEach((objectData, index) => {
    if (index > 0) {
      lines.push("", "-----", "");
    }

    lines.push(objectData.apiName || objectData.name || "Object");

    if (objectData.name || objectData.type) {
      lines.push([objectData.name, objectData.type].filter(Boolean).join(" - "));
    }

    EXPORT_SECTION_OPTIONS.forEach((sectionOption) => {
      if (!includeSections[sectionOption.key]) {
        return;
      }

      const sectionData = resolveSectionData(objectData, sectionOption.key);

      if (!sectionData) {
        return;
      }

      lines.push("", `${sectionData.title}:`);

      if (sectionData.type === "table") {
        appendReadableTable(lines, sectionData.columns, sectionData.rows);
        return;
      }

      if (sectionData.type === "message") {
        lines.push(sectionData.message || "No data available.");
        return;
      }

      if (sectionData.type === "picklists") {
        appendReadablePicklists(lines, sectionData.entries);
        return;
      }

      if (sectionData.type === "layouts") {
        appendReadableLayouts(lines, sectionData.layouts);
      }
    });
  });

  return lines.join("\n").trim();
}

function appendReadableTable(lines, columns, rows) {
  const normalizedColumns = Array.isArray(columns) ? columns : [];
  const normalizedRows = Array.isArray(rows) ? rows : [];

  if (!normalizedColumns.length || !normalizedRows.length) {
    lines.push("No data available.");
    return;
  }

  normalizedRows.slice(0, 6).forEach((row, rowIndex) => {
    if (rowIndex > 0) {
      lines.push("");
    }

    normalizedColumns.forEach((column) => {
      lines.push(`${column.label}: ${formatCellValue(row[column.key])}`);
    });
  });

  if (normalizedRows.length > 6) {
    lines.push("", `... ${normalizedRows.length - 6} more rows`);
  }
}

function appendReadablePicklists(lines, entries) {
  const normalizedEntries = Array.isArray(entries) ? entries : [];

  if (!normalizedEntries.length) {
    lines.push("No picklist values available.");
    return;
  }

  normalizedEntries.forEach((entry) => {
    lines.push(
      `${entry.fieldApiName}: ${(entry.values || []).join(", ") || "No values available."}`
    );
  });
}

function appendReadableLayouts(lines, layouts) {
  const normalizedLayouts = Array.isArray(layouts) ? layouts : [];

  if (!normalizedLayouts.length) {
    lines.push("No page layout metadata available.");
    return;
  }

  normalizedLayouts.forEach((layout) => {
    lines.push(
      `${layout.name || layout.recordType || layout.layoutId}: ${layout.layoutType || "N/A"}`
    );

    (layout.sections || []).slice(0, 3).forEach((section) => {
      lines.push(
        `  ${section.heading || "Layout Section"}: ${(section.fields || []).join(", ") || "No fields"}`
      );
    });
  });
}

function base64ToBlob(base64String, mimeType) {
  const decodedValue = window.atob(base64String);
  const byteValues = new Uint8Array(decodedValue.length);

  for (let index = 0; index < decodedValue.length; index += 1) {
    byteValues[index] = decodedValue.charCodeAt(index);
  }

  return new Blob([byteValues], { type: mimeType });
}

function normalizeBinaryBlob(blob, mimeType) {
  return new Blob([blob], { type: mimeType });
}

function formatBoolean(value) {
  return value ? "Yes" : "No";
}