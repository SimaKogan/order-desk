import { createElement } from 'lwc';
import OrderDesk from 'c/orderDesk';
import listOpportunities from '@salesforce/apex/OrderDeskController.listOpportunities';
import getDeskState from '@salesforce/apex/OrderDeskController.getDeskState';
import addToCart from '@salesforce/apex/OrderDeskController.addToCart';
import removeLine from '@salesforce/apex/OrderDeskController.removeLine';
import submitPurchase from '@salesforce/apex/OrderDeskController.submitPurchase';

jest.mock(
    '@salesforce/apex/OrderDeskController.listOpportunities',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/apex/OrderDeskController.getDeskState', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/OrderDeskController.addToCart', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/OrderDeskController.removeLine', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/OrderDeskController.submitPurchase', () => ({ default: jest.fn() }), {
    virtual: true
});

const OPP_ID = '006000000000001';
const OPPORTUNITIES = [{ id: OPP_ID, name: 'Renewal', accountName: 'Northwind' }];
const PRODUCTS = [
    { id: '00k000000000001', name: 'Widget', quantity: 10, unitPrice: 25, reserved: 0, available: 10 }
];
const EMPTY_DESK = {
    opportunityId: OPP_ID,
    opportunityName: 'Renewal',
    accountName: 'Northwind',
    products: PRODUCTS,
    cart: null
};
const CART_DESK = {
    ...EMPTY_DESK,
    cart: {
        id: 'a00000000000001',
        total: 50,
        lines: [
            { id: 'a01000000000001', productName: 'Widget', quantity: 2, unitPrice: 25, lineTotal: 50 }
        ]
    }
};

const flush = async () => {
    for (let i = 0; i < 6; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
};

async function build(props = {}) {
    const element = createElement('c-order-desk', { is: OrderDesk });
    Object.assign(element, props);
    document.body.appendChild(element);
    await flush();
    return element;
}

async function selectOpportunity(element) {
    element.shadowRoot
        .querySelector('lightning-combobox')
        .dispatchEvent(new CustomEvent('change', { detail: { value: OPP_ID } }));
    await flush();
}

describe('c-order-desk', () => {
    beforeEach(() => {
        listOpportunities.mockResolvedValue(OPPORTUNITIES);
        getDeskState.mockResolvedValue(EMPTY_DESK);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.resetAllMocks();
    });

    it('offers the opportunities and prompts for a selection', async () => {
        const element = await build();
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.options).toEqual([{ label: 'Renewal \u00B7 Northwind', value: OPP_ID }]);
        expect(element.shadowRoot.querySelector('c-empty-state').heading).toBe(
            'Select an opportunity'
        );
    });

    it('explains when there is nothing to work with', async () => {
        listOpportunities.mockResolvedValue([]);
        const element = await build();
        expect(element.shadowRoot.querySelector('c-empty-state').heading).toBe(
            'No opportunities to work with'
        );
    });

    it('loads the desk of the selected opportunity', async () => {
        const element = await build();
        await selectOpportunity(element);

        expect(getDeskState).toHaveBeenCalledWith({ opportunityId: OPP_ID });
        expect(element.shadowRoot.querySelector('c-order-line-list').products).toEqual(PRODUCTS);
        expect(element.shadowRoot.querySelector('c-cart-panel')).not.toBeNull();
    });

    it('skips the picker on a record page', async () => {
        const element = await build({ recordId: OPP_ID });
        expect(element.shadowRoot.querySelector('lightning-combobox')).toBeNull();
        expect(listOpportunities).not.toHaveBeenCalled();
        expect(getDeskState).toHaveBeenCalledWith({ opportunityId: OPP_ID });
    });

    it('adds products to the cart and confirms with a toast', async () => {
        addToCart.mockResolvedValue(CART_DESK);
        const element = await build();
        await selectOpportunity(element);
        const toast = jest.fn();
        element.addEventListener('lightning__showtoast', toast);
        const lines = [{ lineId: '00k000000000001', quantity: 2 }];

        element.shadowRoot
            .querySelector('c-order-line-list')
            .dispatchEvent(new CustomEvent('addtocart', { detail: { lines } }));
        await flush();

        expect(addToCart).toHaveBeenCalledWith({ opportunityId: OPP_ID, lines });
        expect(element.shadowRoot.querySelector('c-cart-panel').cart).toEqual(CART_DESK.cart);
        expect(toast).toHaveBeenCalledTimes(1);
    });

    it('shows the server message when adding fails', async () => {
        addToCart.mockRejectedValue({ body: { message: '"Widget" has only 1 unit(s) left.' } });
        const element = await build();
        await selectOpportunity(element);

        element.shadowRoot
            .querySelector('c-order-line-list')
            .dispatchEvent(
                new CustomEvent('addtocart', {
                    detail: { lines: [{ lineId: '00k000000000001', quantity: 5 }] }
                })
            );
        await flush();

        expect(element.shadowRoot.querySelector('.banner_error').textContent).toContain(
            '"Widget" has only 1 unit(s) left.'
        );
    });

    it('removes a cart line', async () => {
        getDeskState.mockResolvedValue(CART_DESK);
        removeLine.mockResolvedValue(EMPTY_DESK);
        const element = await build();
        await selectOpportunity(element);

        element.shadowRoot
            .querySelector('c-cart-panel')
            .dispatchEvent(new CustomEvent('removeline', { detail: { lineId: 'a01000000000001' } }));
        await flush();

        expect(removeLine).toHaveBeenCalledWith({
            opportunityId: OPP_ID,
            lineId: 'a01000000000001'
        });
        expect(element.shadowRoot.querySelector('c-cart-panel').cart).toBeNull();
    });

    it('submits the purchase, reloads the desk and shows the confirmation', async () => {
        getDeskState.mockResolvedValueOnce(CART_DESK).mockResolvedValueOnce(EMPTY_DESK);
        submitPurchase.mockResolvedValue({
            purchaseId: 'a00000000000001',
            purchaseName: 'PUR-00001',
            receiptSent: true
        });
        const element = await build();
        await selectOpportunity(element);

        element.shadowRoot
            .querySelector('c-cart-panel')
            .dispatchEvent(
                new CustomEvent('checkout', { detail: { receiptEmail: 'buyer@example.com' } })
            );
        await flush();

        expect(submitPurchase).toHaveBeenCalledWith({
            purchaseId: 'a00000000000001',
            receiptEmail: 'buyer@example.com'
        });
        expect(getDeskState).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('.banner_success').textContent).toContain(
            'PUR-00001 submitted'
        );
    });
});
