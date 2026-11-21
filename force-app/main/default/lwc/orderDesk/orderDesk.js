import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listOpportunities from '@salesforce/apex/OrderDeskController.listOpportunities';
import getDeskState from '@salesforce/apex/OrderDeskController.getDeskState';
import addToCart from '@salesforce/apex/OrderDeskController.addToCart';
import removeLine from '@salesforce/apex/OrderDeskController.removeLine';
import submitPurchase from '@salesforce/apex/OrderDeskController.submitPurchase';
import { firstError } from 'c/errorUtils';

export default class OrderDesk extends LightningElement {
    /** Set automatically when the component is placed on an Opportunity record page. */
    @api recordId;

    opportunities = [];
    selectedId;
    desk;
    isLoading = false;
    isBusy = false;
    errorMessage;
    confirmation;
    opportunitiesLoaded = false;

    connectedCallback() {
        if (this.recordId) {
            this.selectedId = this.recordId;
            this.loadDesk();
        } else {
            this.loadOpportunities();
        }
    }

    // ---- view state -------------------------------------------------------------------------

    get showPicker() {
        return !this.recordId;
    }

    get opportunityOptions() {
        return this.opportunities.map((opportunity) => ({
            label: opportunity.accountName
                ? `${opportunity.name} \u00B7 ${opportunity.accountName}`
                : opportunity.name,
            value: opportunity.id
        }));
    }

    get hasDesk() {
        return !!this.desk;
    }

    get cartTotal() {
        return this.desk && this.desk.cart ? this.desk.cart.total : 0;
    }

    get showNoOpportunities() {
        return (
            this.showPicker &&
            this.opportunitiesLoaded &&
            !this.isLoading &&
            !this.errorMessage &&
            this.opportunities.length === 0
        );
    }

    get showPrompt() {
        return (
            this.showPicker && this.opportunities.length > 0 && !this.selectedId && !this.isLoading
        );
    }

    // ---- loading ----------------------------------------------------------------------------

    async loadOpportunities() {
        this.isLoading = true;
        try {
            this.opportunities = await listOpportunities();
        } catch (error) {
            this.errorMessage = firstError(error);
        } finally {
            this.opportunitiesLoaded = true;
            this.isLoading = false;
        }
    }

    async loadDesk() {
        this.errorMessage = undefined;
        if (!this.selectedId) {
            this.desk = undefined;
            return;
        }
        this.isLoading = true;
        try {
            this.desk = await getDeskState({ opportunityId: this.selectedId });
        } catch (error) {
            this.desk = undefined;
            this.errorMessage = firstError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ---- user actions -----------------------------------------------------------------------

    handleOpportunityChange(event) {
        this.selectedId = event.detail.value;
        this.confirmation = undefined;
        this.loadDesk();
    }

    async handleAddToCart(event) {
        const { lines } = event.detail;
        const added = await this.runAction(async () => {
            this.desk = await addToCart({ opportunityId: this.selectedId, lines });
        });
        if (added) {
            const list = this.template.querySelector('c-order-line-list');
            if (list) {
                list.clear();
            }
            this.confirmation = undefined;
            this.showToast('Added to cart', `${lines.length} product(s) added to the cart.`, 'success');
        }
    }

    async handleRemoveLine(event) {
        await this.runAction(async () => {
            this.desk = await removeLine({
                opportunityId: this.selectedId,
                lineId: event.detail.lineId
            });
        });
    }

    async handleCheckout(event) {
        const purchaseId = this.desk && this.desk.cart ? this.desk.cart.id : undefined;
        const submitted = await this.runAction(async () => {
            const result = await submitPurchase({
                purchaseId,
                receiptEmail: event.detail.receiptEmail
            });
            this.desk = await getDeskState({ opportunityId: this.selectedId });
            this.confirmation = result.receiptSent
                ? `${result.purchaseName} submitted. The receipt is on its way to ${event.detail.receiptEmail}.`
                : `${result.purchaseName} submitted, but the receipt email could not be sent. Check the email deliverability settings of this org.`;
        });
        if (submitted) {
            this.showToast('Purchase submitted', this.confirmation, 'success');
        }
    }

    handleDismissConfirmation() {
        this.confirmation = undefined;
    }

    // ---- helpers ----------------------------------------------------------------------------

    /** Runs a server call with the UI locked; resolves to true on success and false after showing the error. */
    async runAction(action) {
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            await action();
            return true;
        } catch (error) {
            this.errorMessage = firstError(error);
            return false;
        } finally {
            this.isBusy = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
