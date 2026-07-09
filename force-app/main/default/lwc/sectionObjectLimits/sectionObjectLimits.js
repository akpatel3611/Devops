import { LightningElement, api, wire } from 'lwc';

import getObjectLimits from '@salesforce/apex/ObjectManagerController.getObjectLimits';

export default class SectionObjectLimits extends LightningElement {
    _objectName;

    limits;

    error;

   // branch scan testing     
    @api
    get objectName() {
        return this._objectName;
    }

    set objectName(value) {
        this._objectName = value;
        this.limits = undefined;
        this.error = undefined;
    }

    get limitRows() {
        if (!this.limits) {
            return [];
        }

        return [
            { label: 'Total Number of Fields', value: this.limits.maxFields },
            {
                label: 'Total Number of Child Relationships',
                value: this.limits.maxChildRelationships
            }
        ];
    }

    @wire(getObjectLimits, { objectName: '$_objectName' })
    wiredLimits({ data, error }) {
        if (data) {
            this.limits = data;
            this.error = undefined;
        } else if (error) {
            this.limits = undefined;
            this.error = error;
            console.error(error);
        }
    }
}