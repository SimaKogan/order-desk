import { createElement } from 'lwc';
import EmptyState from 'c/emptyState';

describe('c-empty-state', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the heading and the optional message', async () => {
        const element = createElement('c-empty-state', { is: EmptyState });
        element.heading = 'Nothing here';
        document.body.appendChild(element);
        await Promise.resolve();
        expect(element.shadowRoot.querySelector('.empty__heading').textContent).toBe('Nothing here');
        expect(element.shadowRoot.querySelector('.empty__message')).toBeNull();

        element.message = 'Try again later';
        await Promise.resolve();
        expect(element.shadowRoot.querySelector('.empty__message').textContent).toBe(
            'Try again later'
        );
    });
});
