import { LightningElement, api, track } from 'lwc';
import getRealtimeOrgErrors from '@salesforce/apex/DevOpsSystemErrorScannerController.getRealtimeOrgErrors';
import { DevOpsGlobalErrorInterceptor } from 'c/devOpsGlobalErrorInterceptor';

const DEBUG_PREFIX = '[devOpsErrorInspectorTerminal]';

export default class DevOpsErrorInspectorTerminal extends LightningElement {
    @api recordId;

    @track isTerminalOpen = false;
    @track isLoadingScan = false;
    @track activeTab = 'ALL'; // ALL, ORG, BROWSER, DEPLOYMENT
    @track searchFilterKey = '';
    @track errorLogs = [];

    _pollingTimer = null;

    connectedCallback() {
        console.log(`${DEBUG_PREFIX} [connectedCallback] Initializing real-time error scanner terminal...`);
        // Subscribe to client-side browser exception interceptor
        DevOpsGlobalErrorInterceptor.subscribe((browserErrorObj) => {
            console.log(`${DEBUG_PREFIX} [InterceptorCallback] Captured browser exception:`, browserErrorObj);
            this.appendUniqueErrorLog(browserErrorObj);
        });

        // Run initial server-side scan
        this.runRealtimeServerScan();

        // Start background polling for org async jobs & deployment errors (every 10 seconds)
        this._pollingTimer = setInterval(() => {
            this.runRealtimeServerScan();
        }, 10000);
    }

    disconnectedCallback() {
        console.log(`${DEBUG_PREFIX} [disconnectedCallback] Clearing polling timer...`);
        if (this._pollingTimer) {
            clearInterval(this._pollingTimer);
            this._pollingTimer = null;
        }
    }

    runRealtimeServerScan() {
        const activeIds = this.recordId ? [this.recordId] : [];
        getRealtimeOrgErrors({ activeRecordIds: activeIds })
            .then(result => {
                if (result && Array.isArray(result) && result.length > 0) {
                    console.log(`${DEBUG_PREFIX} [runRealtimeServerScan] Fetched ${result.length} org error logs from server.`);
                    result.forEach(serverLog => {
                        this.appendUniqueErrorLog(serverLog);
                    });
                }
            })
            .catch(err => {
                console.warn(`${DEBUG_PREFIX} [runRealtimeServerScan] Notice scanning server errors:`, err);
            });
    }

    appendUniqueErrorLog(logObj) {
        if (!logObj || !logObj.id) return;
        const exists = this.errorLogs.some(existing => existing.id === logObj.id);
        if (!exists) {
            const formattedLog = {
                ...logObj,
                severityBadgeClass: this.getSeverityBadgeClass(logObj.severity)
            };
            // Prepend new errors to top
            this.errorLogs = [formattedLog, ...this.errorLogs];
            console.log(`${DEBUG_PREFIX} [appendUniqueErrorLog] Added log entry: ${logObj.id} | Total count: ${this.errorLogs.length}`);
        }
    }

    getSeverityBadgeClass(severity) {
        switch ((severity || '').toUpperCase()) {
            case 'CRITICAL':
                return 'severity-badge badge-critical';
            case 'ERROR':
                return 'severity-badge badge-error';
            case 'WARN':
            case 'WARNING':
                return 'severity-badge badge-warn';
            default:
                return 'severity-badge badge-info';
        }
    }

    // Public API method so external components can explicitly push errors to this terminal
    @api
    logCustomError(source, severity, componentName, methodName, rawMessage, stackTrace, rootCause, fix) {
        console.log(`${DEBUG_PREFIX} [logCustomError] Custom error pushed from component:`, componentName);
        const errObj = {
            id: 'CUSTOM-ERR-' + Date.now(),
            source: source || 'UI_COMPONENT',
            severity: severity || 'ERROR',
            componentOrClass: componentName || 'LWC Component',
            methodName: methodName || 'handler',
            rawErrorMessage: rawMessage || 'Custom component error detected.',
            stackTrace: stackTrace || '',
            diagnosedRootCause: rootCause || '[COMPONENT EXCEPTION]: Error occurred inside LWC component execution.',
            recommendedFix: fix || 'Check component parameter bindings and server response.',
            timestamp: new Date().toLocaleTimeString()
        };
        this.appendUniqueErrorLog(errObj);
        // Automatically pop open badge alert
        this.isTerminalOpen = true;
    }

    // Getters for counts and UI states
    get totalErrorCount() {
        return this.errorLogs.length;
    }

    get hasActiveErrors() {
        return this.totalErrorCount > 0;
    }

    get orgErrorCount() {
        return this.errorLogs.filter(item => item.source === 'ORG' || item.source === 'LIMITS').length;
    }

    get browserErrorCount() {
        return this.errorLogs.filter(item => item.source === 'BROWSER').length;
    }

    get deploymentErrorCount() {
        return this.errorLogs.filter(item => item.source === 'DEPLOYMENT').length;
    }

    get filteredErrorLogs() {
        let logs = [...this.errorLogs];

        // Apply Tab Source Filter
        if (this.activeTab === 'ORG') {
            logs = logs.filter(item => item.source === 'ORG' || item.source === 'LIMITS');
        } else if (this.activeTab === 'BROWSER') {
            logs = logs.filter(item => item.source === 'BROWSER');
        } else if (this.activeTab === 'DEPLOYMENT') {
            logs = logs.filter(item => item.source === 'DEPLOYMENT');
        }

        // Apply Search Filter Key
        if (this.searchFilterKey && this.searchFilterKey.trim() !== '') {
            const key = this.searchFilterKey.toLowerCase().trim();
            logs = logs.filter(item =>
                (item.rawErrorMessage && item.rawErrorMessage.toLowerCase().includes(key)) ||
                (item.componentOrClass && item.componentOrClass.toLowerCase().includes(key)) ||
                (item.diagnosedRootCause && item.diagnosedRootCause.toLowerCase().includes(key)) ||
                (item.stackTrace && item.stackTrace.toLowerCase().includes(key))
            );
        }

        return logs;
    }

    get hasFilteredLogs() {
        return this.filteredErrorLogs && this.filteredErrorLogs.length > 0;
    }

    get filteredErrorLogsCount() {
        return this.filteredErrorLogs.length;
    }

    get badgeButtonClass() {
        return this.hasActiveErrors ? 'floating-terminal-btn btn-alert-active' : 'floating-terminal-btn btn-idle';
    }

    // Tab Classes
    get tabAllClass() { return this.activeTab === 'ALL' ? 'tab-btn tab-active' : 'tab-btn'; }
    get tabOrgClass() { return this.activeTab === 'ORG' ? 'tab-btn tab-active' : 'tab-btn'; }
    get tabBrowserClass() { return this.activeTab === 'BROWSER' ? 'tab-btn tab-active' : 'tab-btn'; }
    get tabDeploymentClass() { return this.activeTab === 'DEPLOYMENT' ? 'tab-btn tab-active' : 'tab-btn'; }

    // Handlers
    handleOpenTerminal() {
        this.isTerminalOpen = true;
        this.runRealtimeServerScan();
    }

    handleCloseTerminal() {
        this.isTerminalOpen = false;
    }

    handleSelectTabAll() { this.activeTab = 'ALL'; }
    handleSelectTabOrg() { this.activeTab = 'ORG'; }
    handleSelectTabBrowser() { this.activeTab = 'BROWSER'; }
    handleSelectTabDeployment() { this.activeTab = 'DEPLOYMENT'; }

    handleSearchInput(event) {
        this.searchFilterKey = event.target.value;
    }

    handleManualRefreshScan() {
        this.isLoadingScan = true;
        this.runRealtimeServerScan();
        setTimeout(() => {
            this.isLoadingScan = false;
        }, 600);
    }

    handleClearTerminalLogs() {
        console.log(`${DEBUG_PREFIX} [handleClearTerminalLogs] Clearing all terminal error history...`);
        this.errorLogs = [];
    }

    handleCopyAllLogs() {
        if (!this.hasFilteredLogs) return;
        let reportText = '=== DEVOPS REAL-TIME SYSTEM ERROR INSPECTOR REPORT ===\n';
        reportText += `Generated: ${new Date().toLocaleString()}\n`;
        reportText += `Total Filtered Errors: ${this.filteredErrorLogs.length}\n\n`;

        this.filteredErrorLogs.forEach((log, index) => {
            reportText += `--- ERROR ${index + 1} [${log.severity}] [${log.source}] ---\n`;
            reportText += `Timestamp: ${log.timestamp}\n`;
            reportText += `Component/Class: ${log.componentOrClass} -> ${log.methodName}\n`;
            reportText += `Message: ${log.rawErrorMessage}\n`;
            reportText += `Diagnosed Root Cause: ${log.diagnosedRootCause}\n`;
            reportText += `Recommended Fix: ${log.recommendedFix}\n`;
            if (log.stackTrace) reportText += `Stack Trace:\n${log.stackTrace}\n`;
            reportText += '\n';
        });

        navigator.clipboard.writeText(reportText)
            .then(() => {
                alert('Diagnostic Log Report copied to clipboard!');
            })
            .catch(err => {
                console.error(`${DEBUG_PREFIX} [handleCopyAllLogs] Error copying to clipboard:`, err);
            });
    }

    handleExportLogFile() {
        if (!this.hasFilteredLogs) return;
        let reportText = '=== DEVOPS REAL-TIME SYSTEM ERROR INSPECTOR REPORT ===\n';
        reportText += `Generated: ${new Date().toLocaleString()}\n`;
        reportText += `Total Filtered Errors: ${this.filteredErrorLogs.length}\n\n`;

        this.filteredErrorLogs.forEach((log, index) => {
            reportText += `--- ERROR ${index + 1} [${log.severity}] [${log.source}] ---\n`;
            reportText += `Timestamp: ${log.timestamp}\n`;
            reportText += `Component/Class: ${log.componentOrClass} -> ${log.methodName}\n`;
            reportText += `Message: ${log.rawErrorMessage}\n`;
            reportText += `Diagnosed Root Cause: ${log.diagnosedRootCause}\n`;
            reportText += `Recommended Fix: ${log.recommendedFix}\n`;
            if (log.stackTrace) reportText += `Stack Trace:\n${log.stackTrace}\n`;
            reportText += '\n';
        });

        const element = document.createElement('a');
        const file = new Blob([reportText], { type: 'text/plain' });
        element.href = URL.createObjectURL(file);
        element.download = `DevOps_System_Error_Report_${Date.now()}.txt`;
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
    }
}
