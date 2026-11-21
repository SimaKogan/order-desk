import { reduceErrors, firstError } from 'c/errorUtils';

describe('errorUtils', () => {
    it('reads Apex errors, arrays, plain errors and status texts', () => {
        expect(reduceErrors({ body: { message: 'Apex says no' } })).toEqual(['Apex says no']);
        expect(reduceErrors({ body: [{ message: 'one' }, { message: 'two' }] })).toEqual([
            'one',
            'two'
        ]);
        expect(reduceErrors(new Error('plain'))).toEqual(['plain']);
        expect(reduceErrors({ statusText: 'Not Found' })).toEqual(['Not Found']);
        expect(reduceErrors([undefined, null])).toEqual([]);
    });

    it('returns the first message or the fallback', () => {
        expect(firstError({ body: { message: 'boom' } })).toBe('boom');
        expect(firstError(undefined, 'fallback')).toBe('fallback');
        expect(firstError({})).toBe('Something went wrong. Please try again.');
    });
});
