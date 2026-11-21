import { LightningElement, api } from 'lwc';

export default class OrderLineList extends LightningElement {
    @api disabled = false;

    _products = [];
    quantities = {};

    /** Products of the opportunity, each with `available` units left to add to the cart. */
    @api
    get products() {
        return this._products;
    }
    set products(value) {
        this._products = Array.isArray(value) ? value : [];
        this.quantities = this.clampToAvailable(this.quantities);
    }

    /** Forgets the quantities typed so far. */
    @api
    clear() {
        this.quantities = {};
    }

    get hasProducts() {
        return this._products.length > 0;
    }

    get rows() {
        return this._products.map((product) => {
            const quantity = this.quantities[product.id] || 0;
            const isSoldOut = product.available <= 0;
            let className = 'row';
            if (isSoldOut) {
                className = 'row row_done';
            } else if (quantity > 0) {
                className = 'row row_active';
            }
            return {
                id: product.id,
                name: product.name,
                unitPrice: product.unitPrice,
                quantity: product.quantity,
                available: product.available,
                isSoldOut,
                inputValue: quantity,
                inputLabel: `Quantity of ${product.name}`,
                className
            };
        });
    }

    get selectedUnits() {
        return this._products.reduce((sum, product) => sum + (this.quantities[product.id] || 0), 0);
    }

    get subtotal() {
        return this._products.reduce(
            (sum, product) => sum + (this.quantities[product.id] || 0) * product.unitPrice,
            0
        );
    }

    get isAddDisabled() {
        return this.disabled || this.selectedUnits === 0;
    }

    handleQuantityChange(event) {
        const id = event.target.dataset.id;
        const product = this._products.find((item) => item.id === id);
        if (!product) {
            return;
        }
        const typed = parseInt(event.detail.value, 10);
        const quantity = Number.isNaN(typed) ? 0 : Math.min(Math.max(typed, 0), product.available);
        this.quantities = { ...this.quantities, [id]: quantity };
        if (!Number.isNaN(typed) && typed !== quantity) {
            // Show the corrected value instead of what was typed.
            event.target.value = quantity;
        }
    }

    handleAdd() {
        const lines = Object.keys(this.quantities)
            .filter((lineId) => this.quantities[lineId] > 0)
            .map((lineId) => ({ lineId, quantity: this.quantities[lineId] }));
        if (lines.length > 0) {
            this.dispatchEvent(new CustomEvent('addtocart', { detail: { lines } }));
        }
    }

    clampToAvailable(current) {
        const clamped = {};
        this._products.forEach((product) => {
            const quantity = Math.min(current[product.id] || 0, Math.max(product.available, 0));
            if (quantity > 0) {
                clamped[product.id] = quantity;
            }
        });
        return clamped;
    }
}
