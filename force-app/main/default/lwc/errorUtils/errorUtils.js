/**
 * Flattens the different shapes of errors returned by Apex and the platform into a list of messages.
 * @param {*} errors a single error or an array of errors
 * @returns {string[]}
 */
export function reduceErrors(errors) {
    const list = Array.isArray(errors) ? errors : [errors];
    return list
        .filter((error) => !!error)
        .map((error) => {
            if (Array.isArray(error.body)) {
                return error.body.map((item) => item.message);
            }
            if (error.body && typeof error.body.message === 'string') {
                return error.body.message;
            }
            if (typeof error.message === 'string') {
                return error.message;
            }
            return error.statusText;
        })
        .reduce((all, current) => all.concat(current), [])
        .filter((message) => !!message);
}

/**
 * @returns {string} the first message of the error, or the fallback when there is none
 */
export function firstError(error, fallback = 'Something went wrong. Please try again.') {
    const [message] = reduceErrors(error);
    return message || fallback;
}
