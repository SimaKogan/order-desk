import { createElement } from 'lwc';
import CartPanel from 'c/cartPanel';

const CART = {
    id: 'a00000000000001',
    name: 'PUR-00001',
    total: 75,
    lines: [
        { id: 'a01000000000001', productName: 'Widget', quantity: 3, unitPrice: 25, lineTotal: 75 }
    ]
};

const flush = async () => {
    for (let i = 0; i < 3; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};

function build(cart) {
    const element = createElement('c-cart-panel', { is: CartPanel });
    element.cart = cart;
    document.body.appendChild(element);
    return element;
}

describe('c-cart-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows an empty state when there is no cart', () => {
        const element = build(null);
        expect(element.shadowRoot.querySelector('c-empty-state')).not.toBeNull();
        expect(element.shadowRoot.querySelector('li')).toBeNull();
    });

    it('lists the cart lines', () => {
        const element = build(CART);
        expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(1);
        expect(element.shadowRoot.querySelector('.line__name').textContent).toBe('Widget');
    });

    it('asks to remove a line', () => {
        const element = build(CART);
        const handler = jest.fn();
        element.addEventListener('removeline', handler);
        element.shadowRoot.querySelector('lightning-button-icon').click();
        expect(handler.mock.calls[0][0].detail).toEqual({ lineId: 'a01000000000001' });
    });

    it('enables checkout only for a valid email and sends it trimmed', async () => {
        const element = build(CART);
        const handler = jest.fn();
        element.addEventListener('checkout', handler);
        const input = element.shadowRoot.querySelector('lightning-input');
        const button = element.shadowRoot.querySelector('.checkout__button');
        expect(button.disabled).toBe(true);

        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'nope' } }));
        await flush();
        expect(button.disabled).toBe(true);
        expect(element.shadowRoot.querySelector('.checkout__hint')).not.toBeNull();

        input.dispatchEvent(new CustomEvent('change', { detail: { value: ' buyer@example.com ' } }));
        await flush();
        expect(button.disabled).toBe(false);
        button.click();
        expect(handler.mock.calls[0][0].detail).toEqual({ receiptEmail: 'buyer@example.com' });
    });

    it('locks the controls while the desk is busy', async () => {
        const element = build(CART);
        element.disabled = true;
        await flush();
        expect(element.shadowRoot.querySelector('.checkout__button').disabled).toBe(true);
    });
});
