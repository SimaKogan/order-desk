/**
 * Sends purchase receipts. One email per purchase, one Messaging.sendEmail call for the whole batch.
 */
public with sharing class ReceiptMailer {
    /**
     * @param purchaseIds purchases whose receipt should be sent to their Receipt Email
     * @return ids of the purchases whose receipt was accepted for delivery; Receipt Sent is set on them
     */
    public static Set<Id> send(Set<Id> purchaseIds) {
        Set<Id> sent = new Set<Id>();
        if (purchaseIds == null || purchaseIds.isEmpty()) {
            return sent;
        }

        List<Purchase__c> purchases = [
            SELECT
                Id,
                Name,
                Receipt_Email__c,
                Account__r.Name,
                (SELECT Product_Name__c, Quantity__c, Unit_Price__c FROM Lines__r ORDER BY CreatedDate, Id)
            FROM Purchase__c
            WHERE Id IN :purchaseIds AND Receipt_Email__c != NULL
            WITH USER_MODE
        ];
        List<Messaging.SingleEmailMessage> messages = buildMessages(purchases);
        if (messages.isEmpty()) {
            return sent;
        }

        List<Messaging.SendEmailResult> results;
        try {
            results = Messaging.sendEmail(messages, false);
        } catch (EmailException e) {
            // Email deliverability can be switched off in sandboxes; the purchase itself stays submitted.
            System.debug(LoggingLevel.WARN, 'Receipt email was not sent: ' + e.getMessage());
            return sent;
        }

        List<Purchase__c> flagged = new List<Purchase__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                sent.add(purchases[i].Id);
                flagged.add(new Purchase__c(Id = purchases[i].Id, Receipt_Sent__c = true));
            }
        }
        if (!flagged.isEmpty()) {
            update as user flagged;
        }
        return sent;
    }

    /** Builds one plain-text message per purchase, in the same order as the given purchases. */
    public static List<Messaging.SingleEmailMessage> buildMessages(List<Purchase__c> purchases) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Purchase__c purchase : purchases) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(new List<String>{ purchase.Receipt_Email__c });
            message.setSubject('Your receipt ' + purchase.Name);
            message.setPlainTextBody(buildBody(purchase));
            message.setSenderDisplayName('Order Desk');
            message.setSaveAsActivity(false);
            messages.add(message);
        }
        return messages;
    }

    private static String buildBody(Purchase__c purchase) {
        Decimal total = 0;
        List<String> rows = new List<String>();
        for (Purchase_Line__c line : purchase.Lines__r) {
            Decimal lineTotal = line.Quantity__c * line.Unit_Price__c;
            total += lineTotal;
            rows.add(
                ' - ' +
                    line.Product_Name__c +
                    ': ' +
                    line.Quantity__c.intValue() +
                    ' x ' +
                    line.Unit_Price__c.setScale(2) +
                    ' = ' +
                    lineTotal.setScale(2)
            );
        }
        return 'Hello,\n\n' +
            'Thank you for your purchase, ' +
            purchase.Account__r.Name +
            '. Here is your receipt ' +
            purchase.Name +
            ':\n\n' +
            String.join(rows, '\n') +
            '\n\nTotal: ' +
            total.setScale(2) +
            '\n\nOrder Desk';
    }
}
