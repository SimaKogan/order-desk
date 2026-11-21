import { LightningElement, api } from 'lwc';

const EMAIL_PATTERN = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

export default class CartPanel extends LightningElement {
    @api disabled = false;

    _cart;
    email = '';

    /** The open cart (Draft purchase) or nothing when there is none. */
    @api
    get cart() {
        return this._cart;
    }
    set cart(value) {
        this._cart = value;
        if (!value) {
            this.email = '';
        } else if (!this.email && value.receiptEmail) {
            this.email = value.receiptEmail;
        }
    }

    get lines() {
        const lines = this._cart && this._cart.lines ? this._cart.lines : [];
        return lines.map((line) => ({ ...line, removeLabel: `Remove ${line.productName}` }));
    }

    get hasLines() {
        return this.lines.length > 0;
    }

    get isEmailValid() {
        return EMAIL_PATTERN.test(this.email.trim());
    }

    get showEmailHint() {
        return this.email.trim().length > 0 && !this.isEmailValid;
    }

    get isCheckoutDisabled() {
        return this.disabled || !this.hasLines || !this.isEmailValid;
    }

    handleEmailChange(event) {
        this.email = event.detail.value || '';
    }

    handleRemove(event) {
        this.dispatchEvent(
            new CustomEvent('removeline', { detail: { lineId: event.currentTarget.dataset.id } })
        );
    }

    handleCheckout() {
        if (!this.isCheckoutDisabled) {
            this.dispatchEvent(
                new CustomEvent('checkout', { detail: { receiptEmail: this.email.trim() } })
            );
        }
    }
}
