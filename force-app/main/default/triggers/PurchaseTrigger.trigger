/**
 * Keeps purchases consistent. All logic lives in PurchaseTriggerHandler so it can be tested without DML.
 */
trigger PurchaseTrigger on Purchase__c(before insert, before update) {
    PurchaseTriggerHandler.run(Trigger.new, Trigger.oldMap, Trigger.isInsert);
}
