import { LightningElement, api } from 'lwc';

export default class EmptyState extends LightningElement {
    @api heading;
    @api message;
}
