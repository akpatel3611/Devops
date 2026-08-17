import getSectionData from '@salesforce/apex/ObjectManagerController.getSectionData';

export async function loadSectionData(sectionId, objectName) {
    try {
        return await getSectionData({
            sectionId,
            objectName
        });
    } catch (error) {
        console.error(`Metadata load failed for ${sectionId}:`, error);

        return {
            title: 'Metadata',
            objectName,
            type: 'message',
            message: 'Unable to load metadata for this section.'
        };
    }
}