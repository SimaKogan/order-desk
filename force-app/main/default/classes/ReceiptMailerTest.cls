@IsTest
private class ReceiptMailerTest {
    @TestSetup
    static void setup() {
        Account account = OrderDeskTestFactory.createAccount('Receipt Test Account');
        Opportunity opp = OrderDeskTestFactory.createOpportunity(account.Id, 'Receipt Opportunity');
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account.Id, opp.Id);
        insert new List<Purchase_Line__c>{
            OrderDeskTestFactory.newLine(purchase.Id, 'A', 2, 12.5),
            OrderDeskTestFactory.newLine(purchase.Id, 'B', 1, 30)
        };
        purchase.Status__c = 'Submitted';
        purchase.Receipt_Email__c = 'customer@example.com';
        update purchase;
    }

    private static List<Purchase__c> purchases() {
        return [
            SELECT
                Id,
                Name,
                Receipt_Email__c,
                Receipt_Sent__c,
                Account__r.Name,
                (SELECT Product_Name__c, Quantity__c, Unit_Price__c FROM Lines__r ORDER BY Line_Key__c)
            FROM Purchase__c
        ];
    }

    @IsTest
    static void buildMessagesCreatesOneReceiptPerPurchase() {
        List<Purchase__c> purchases = purchases();

        List<Messaging.SingleEmailMessage> messages = ReceiptMailer.buildMessages(purchases);

        System.assertEquals(1, messages.size());
        Messaging.SingleEmailMessage message = messages[0];
        System.assertEquals(new List<String>{ 'customer@example.com' }, message.getToAddresses());
        System.assertEquals('Your receipt ' + purchases[0].Name, message.getSubject());
        String body = message.getPlainTextBody();
        System.assert(body.contains('Receipt Test Account'), body);
        System.assert(body.contains('Line A: 2 x 12.50 = 25.00'), body);
        System.assert(body.contains('Line B: 1 x 30.00 = 30.00'), body);
        System.assert(body.contains('Total: 55.00'), body);
    }

    @IsTest
    static void sendFlagsExactlyTheReceiptsThatWereAccepted() {
        Purchase__c purchase = purchases()[0];

        Test.startTest();
        Set<Id> sent = ReceiptMailer.send(new Set<Id>{ purchase.Id });
        Test.stopTest();

        System.assertEquals(
            sent.contains(purchase.Id),
            [SELECT Receipt_Sent__c FROM Purchase__c WHERE Id = :purchase.Id].Receipt_Sent__c,
            'Receipt Sent mirrors the delivery result'
        );
    }

    @IsTest
    static void sendIgnoresEmptyInputAndPurchasesWithoutAnAddress() {
        System.assert(ReceiptMailer.send(null).isEmpty());
        System.assert(ReceiptMailer.send(new Set<Id>()).isEmpty());

        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Purchase__c noAddress = OrderDeskTestFactory.createDraft(account.Id, opp.Id);
        System.assert(ReceiptMailer.send(new Set<Id>{ noAddress.Id }).isEmpty());
    }
}
