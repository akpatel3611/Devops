import { LightningElement, track } from 'lwc';
import processResumeFile from '@salesforce/apex/ResumeAiController.processResumeFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ResumeAiBuilder extends LightningElement {
    // Harmless comment to trigger git difference for end-to-end testing
    @track uploadedFileId;
    @track promptValue = '';
    @track isLoading = false;

    // Jab user file upload karta hai, tab ye function chalega
    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        this.uploadedFileId = uploadedFiles[0].contentVersionId;
    }

    // Jab user prompt type karta hai
    handlePromptChange(event) {
        this.promptValue = event.target.value;
    }

    // Jab user 'Generate' button dabata hai
    handleProcess() {
        if (!this.promptValue) {
            this.dispatchEvent(new ShowToastEvent({title: 'Required', message: 'Prompt dalna zaroori hai.', variant: 'error'}));
            return;
        }

        this.isLoading = true; // Spinner on

        // Apex ko call karna
        processResumeFile({ contentVersionId: this.uploadedFileId, masterPrompt: this.promptValue })
        .then(newFileId => {
            this.isLoading = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success!', 
                message: 'Aapka Resume update ho gaya hai. Salesforce "Files" tab me check karein.', 
                variant: 'success'
            }));
            // Reset fields
            this.uploadedFileId = null;
            this.promptValue = '';
        })
        .catch(error => {
            this.isLoading = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', 
                message: error.body ? error.body.message : error.message, 
                variant: 'error'
            }));
        });
    }
}
/* Simulated metadata content for resumeAiBuilder (LightningComponentBundle) */
