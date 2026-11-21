import { createElement } from 'lwc';
import OrderLineList from 'c/orderLineList';

const PRODUCTS = [
    { id: '00k000000000001', name: 'Widget', quantity: 10, unitPrice: 25, reserved: 0, available: 10 },
    { id: '00k000000000002', name: 'Gadget', quantity: 4, unitPrice: 40, reserved: 4, available: 0 }
];

const flush = async () => {
    for (let i = 0; i < 3; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};

function build(products = PRODUCTS) {
    const element = createElement('c-order-line-list', { is: OrderLineList });
    element.products = products;
    document.body.appendChild(element);
    return element;
}

const typeQuantity = (element, value) => {
    const input = element.shadowRoot.querySelector('lightning-input');
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    return flush();
};

describe('c-order-line-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders a row per product and marks fully reserved products', () => {
        const element = build();
        expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(2);
        expect(element.shadowRoot.querySelectorAll('lightning-input')).toHaveLength(1);
        expect(element.shadowRoot.querySelector('.pill').textContent).toBe('All in cart');
    });

    it('shows an empty state without products', () => {
        const element = build([]);
        expect(element.shadowRoot.querySelector('c-empty-state')).not.toBeNull();
    });

    it('keeps the add button disabled until a quantity is chosen', async () => {
        const element = build();
        const button = element.shadowRoot.querySelector('lightning-button');
        expect(button.disabled).toBe(true);
        await typeQuantity(element, '3');
        expect(button.disabled).toBe(false);
    });

    it('sends the chosen quantities and clamps them to what is available', async () => {
        const element = build();
        const handler = jest.fn();
        element.addEventListener('addtocart', handler);

        await typeQuantity(element, '99');
        element.shadowRoot.querySelector('lightning-button').click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.lines).toEqual([
            { lineId: '00k000000000001', quantity: 10 }
        ]);
    });

    it('forgets quantities after clear()', async () => {
        const element = build();
        await typeQuantity(element, '2');
        element.clear();
        await flush();
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(true);
    });
});
