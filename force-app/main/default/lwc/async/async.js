import { LightningElement, api, track } from 'lwc';

import {subscribe,unsubscribe,onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class Async extends LightningElement {
    @api recordId;
    channelName = '/event/Async_Process_Event__e';
    subscription = null;
    isLoading = false;
    message = 'No process running';
    progress = 0;
    showContainer = false;
    pollingIntervals = [];
    
    @track processList = [];

    get hasProcesses() {
        return this.processList.length > 0;
    }

    connectedCallback() {
        console.log('Component Loaded');
        this.registerErrorListener();
        this.showContainer = true;
        this.subscribeToPlatformEvent();
        console.log('Current Record Id');
        console.log(this.recordId);
    }
    disconnectedCallback() {
        this.pollingIntervals.forEach(
            intervalId => {
                clearInterval(intervalId);
            }
        );
        this.unsubscribeToPlatformEvent();
    }
    registerErrorListener() {
        onError((error) => {
            console.error('EMP API Error: ', JSON.stringify(error));
        });
    }
    subscribeToPlatformEvent() {
        const messageCallback = (response) => {
            // Direct hand-off to the handler. No delays.
            this.handlePlatformEvent(response);
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            console.log('Subscribed to ' + this.channelName);
            this.subscription = response;
        });
    }

      unsubscribeToPlatformEvent() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
        }
    }

    animateProgress(jobId, targetProgress) {
        const intervalId = setInterval(() => {
            this.processList =
                this.processList.map(currentProcess => {
                    if ( currentProcess.jobId === jobId && currentProcess.progress < targetProgress
                    ) {
                        return {
                            ...currentProcess,
                            progress: currentProcess.progress + 1
                        };
                    }
                    return currentProcess;
                });

            const activeProcess =
                this.processList.find(
                    item => item.jobId === jobId
                );
            // stop animation once we reach the target progress or if the process is no longer active
            if ( !activeProcess || activeProcess.progress >= targetProgress
            ) {
                clearInterval(intervalId);
            }
        }, 25);
    }

    startJobStatusPolling(jobId) {
        const intervalId = setInterval(() => {
            getAsyncJobStatus({
                jobId: jobId
            })
            .then((result) => {
                console.log('Async Job Status: ' + result);

                this.processList = this.processList.map(process => {

                        if ( process.jobId === jobId ) {

                            return {
                                ...process,
                                isLoading: result !== 'Completed' && result !== 'Failed' && result !== 'Aborted'
                            };
                        }
                        return process;
                    });

                if ( result === 'Completed' || result === 'Failed' || result === 'Aborted'
                ) {
                    clearInterval(intervalId);
                }
            })
            .catch((error) => {
                console.error(error);
                clearInterval(intervalId);
            });
        }, 1000);

        this.pollingIntervals.push(
            intervalId
        );
    }

    handlePlatformEvent(response) {
        const payload = response.data.payload;

        // 1. Check: Is this event for the current record?
        // Ensure your payload has Record_Id__c
        if (!payload.Record_Id__c || !this.recordId) return;
        
        // Safe ID comparison (15 vs 18 char safe)
        if (payload.Record_Id__c.substring(0, 15) !== this.recordId.substring(0, 15)) {
            return;
        }

        const jobId = payload.Job_Id__c;
        const serverProgress = payload.Progress__c || 0; // Direct mapping
        const status = payload.Status__c;

        // 2. Find existing process in the list
        let existingProcessIndex = this.processList.findIndex(p => p.jobId === jobId);

        // Logic for Loading Spinner State
        const isRunning = (status !== 'SUCCESS' && status !== 'FAILED' && status !== 'ABORTED');

        if (existingProcessIndex === -1) {
            // === CREATE NEW ===
            let newProcess = {
                jobId: jobId,
                resourceType: payload.Resource_Type__c || 'Async Process',
                operationName: payload.Operation_Name__c || 'Processing...',
                message: payload.Message__c,
                progress: 0,
                status: status,
                isLoading: isRunning
            };
            this.processList = [...this.processList, newProcess];
            this.startJobStatusPolling( jobId );
        } else {
            // === UPDATE EXISTING ===
            // We clone the object to ensure LWC detects the change
            let updatedProcess = {
                ...this.processList[existingProcessIndex]
            };
            updatedProcess.message = payload.Message__c;
            updatedProcess.status = status;
            updatedProcess.isLoading = isRunning;

            // REAL TIME DIRECT PROGRESS UPDATE
            if ( serverProgress > updatedProcess.progress
            ) {
                this.animateProgress(
                    jobId,
                    serverProgress
                );
            }

            // Replace in array
            let newList = [...this.processList];
            newList[existingProcessIndex] = updatedProcess;
            this.processList = newList;
        }

        // 3. Handle Completion (Toast & Cleanup)
        if (!isRunning) {
            this.showToast(
                status === 'SUCCESS' ? 'Success' : 'Error',
                payload.Message__c,
                status === 'SUCCESS' ? 'success' : 'error'
            );

            // Remove from UI after 5 seconds
            setTimeout(() => {
                this.processList =
                    this.processList.filter(
                        p => p.jobId !== jobId
                    );
            }, 5000);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}