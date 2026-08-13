/**
 * Global Browser & Network Exception Interceptor Utility for Salesforce DevOps Platform
 */
class DevOpsGlobalErrorInterceptor {
    static errorListeners = [];
    static isListening = false;

    static init() {
        if (this.isListening) return;
        this.isListening = true;

        console.log('[DevOpsGlobalErrorInterceptor] Initializing global window error listeners...');

        // 1. Safely Intercept Global Unhandled JS Exceptions
        try {
            if (typeof window !== 'undefined' && window.addEventListener) {
                window.addEventListener('error', (event) => {
                    console.error('[DevOpsGlobalErrorInterceptor] Intercepted window error event:', event);
                    const errorObj = {
                        id: 'BROWSER-ERR-' + Date.now(),
                        source: 'BROWSER',
                        severity: 'CRITICAL',
                        componentOrClass: event.filename ? event.filename.split('/').pop() : 'BrowserWindow',
                        methodName: event.lineno ? `Line ${event.lineno}:${event.colno}` : 'global',
                        rawErrorMessage: event.message || 'Unhandled JavaScript Exception',
                        stackTrace: event.error && event.error.stack ? event.error.stack : (event.filename + ':' + event.lineno),
                        diagnosedRootCause: '[BROWSER CLIENT CRASH]: Unhandled JavaScript Error or null dereference in LWC UI.',
                        recommendedFix: 'Inspect LWC component lifecycle code and check if target properties exist before accessing.',
                        timestamp: new Date().toLocaleTimeString()
                    };
                    this.notifyListeners(errorObj);
                });
            }
        } catch (e) {
            console.warn('[DevOpsGlobalErrorInterceptor] LWS notice: window.onerror listener skipped:', e.message);
        }

        // 2. Safely Intercept Global Unhandled Promise Rejections
        try {
            if (typeof window !== 'undefined' && window.addEventListener) {
                window.addEventListener('unhandledrejection', (event) => {
                    console.error('[DevOpsGlobalErrorInterceptor] Intercepted unhandled promise rejection:', event);
                    let reason = event.reason;
                    let msg = 'Unhandled Promise Rejection';
                    let stack = '';

                    if (reason) {
                        if (typeof reason === 'string') {
                            msg = reason;
                        } else if (reason.message) {
                            msg = reason.message;
                            stack = reason.stack || '';
                        } else if (reason.body && reason.body.message) {
                            msg = reason.body.message;
                        } else {
                            msg = JSON.stringify(reason);
                        }
                    }

                    const errorObj = {
                        id: 'PROMISE-ERR-' + Date.now(),
                        source: 'BROWSER',
                        severity: 'ERROR',
                        componentOrClass: 'LWC Async Promise',
                        methodName: 'imperativeCall / fetch',
                        rawErrorMessage: msg,
                        stackTrace: stack || 'Unhandled Promise Rejection Event',
                        diagnosedRootCause: '[ASYNC PROMISE REJECTION]: Imperative Apex or HTTP call failed without catch block handler.',
                        recommendedFix: 'Add try-catch or .catch() block to Apex imperative call in LWC JS controller.',
                        timestamp: new Date().toLocaleTimeString()
                    };
                    this.notifyListeners(errorObj);
                });
            }
        } catch (e) {
            console.warn('[DevOpsGlobalErrorInterceptor] LWS notice: window.unhandledrejection listener skipped:', e.message);
        }
    }

    static subscribe(callback) {
        this.init();
        if (typeof callback === 'function' && !this.errorListeners.includes(callback)) {
            this.errorListeners.push(callback);
        }
    }

    static notifyListeners(errorObj) {
        this.errorListeners.forEach(listener => {
            try {
                listener(errorObj);
            } catch (err) {
                console.error('[DevOpsGlobalErrorInterceptor] Error notifying listener:', err);
            }
        });
    }
}

export { DevOpsGlobalErrorInterceptor };
