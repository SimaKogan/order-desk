/**
 * Guards the purchase life cycle. Bulk-safe: one aggregate query per transaction, no DML, no query in loops.
 *
 * Rules
 *  - a purchase is created as Draft
 *  - Draft -> Submitted | Cancelled, Submitted -> Cancelled, Cancelled is final
 *  - Account and Opportunity are fixed after creation
 *  - a purchase can only be submitted when it has at least one line; Submitted On is stamped automatically
 */
public with sharing class PurchaseTriggerHandler {
    private static final String DRAFT = 'Draft';
    private static final String SUBMITTED = 'Submitted';
    private static final String CANCELLED = 'Cancelled';

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        DRAFT => new Set<String>{ SUBMITTED, CANCELLED },
        SUBMITTED => new Set<String>{ CANCELLED },
        CANCELLED => new Set<String>()
    };

    public static void run(List<Purchase__c> records, Map<Id, Purchase__c> oldById, Boolean isInsert) {
        List<Purchase__c> submitting = new List<Purchase__c>();

        for (Purchase__c purchase : records) {
            if (String.isBlank(purchase.Status__c)) {
                purchase.Status__c = DRAFT;
            }
            if (isInsert) {
                if (purchase.Status__c != DRAFT) {
                    purchase.Status__c.addError('A purchase must be created as Draft.');
                }
                continue;
            }

            Purchase__c previous = oldById.get(purchase.Id);
            if (purchase.Account__c != previous.Account__c) {
                purchase.Account__c.addError('The account of a purchase cannot be changed.');
            }
            if (purchase.Opportunity__c != previous.Opportunity__c) {
                purchase.Opportunity__c.addError('The opportunity of a purchase cannot be changed.');
            }
            if (purchase.Status__c == previous.Status__c) {
                continue;
            }
            if (!isTransitionAllowed(previous.Status__c, purchase.Status__c)) {
                purchase.Status__c.addError(
                    'A ' + previous.Status__c + ' purchase cannot be moved to ' + purchase.Status__c + '.'
                );
            } else if (purchase.Status__c == SUBMITTED) {
                submitting.add(purchase);
            }
        }

        requireLines(submitting);
    }

    @TestVisible
    private static Boolean isTransitionAllowed(String fromStatus, String toStatus) {
        Set<String> targets = ALLOWED_TRANSITIONS.get(fromStatus);
        return targets != null && targets.contains(toStatus);
    }

    private static void requireLines(List<Purchase__c> submitting) {
        if (submitting.isEmpty()) {
            return;
        }
        Set<Id> purchaseIds = new Set<Id>();
        for (Purchase__c purchase : submitting) {
            purchaseIds.add(purchase.Id);
        }

        Map<Id, Integer> lineCounts = new Map<Id, Integer>();
        for (AggregateResult result : [
            SELECT Purchase__c purchaseId, COUNT(Id) lineCount
            FROM Purchase_Line__c
            WHERE Purchase__c IN :purchaseIds
            GROUP BY Purchase__c
        ]) {
            lineCounts.put((Id) result.get('purchaseId'), (Integer) result.get('lineCount'));
        }

        Datetime now = System.now();
        for (Purchase__c purchase : submitting) {
            if (lineCounts.containsKey(purchase.Id) && lineCounts.get(purchase.Id) > 0) {
                purchase.Submitted_On__c = now;
            } else {
                purchase.addError('Add at least one product before submitting the purchase.');
            }
        }
    }
}
