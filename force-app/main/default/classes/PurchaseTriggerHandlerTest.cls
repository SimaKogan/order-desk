@IsTest
private class PurchaseTriggerHandlerTest {
    @TestSetup
    static void setup() {
        Account account = OrderDeskTestFactory.createAccount('Trigger Test Account');
        OrderDeskTestFactory.createOpportunity(account.Id, 'Trigger Test Opportunity');
    }

    private static Account account() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Opportunity opportunity() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

    private static Purchase__c draftWithOneLine() {
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account().Id, opportunity().Id);
        insert OrderDeskTestFactory.newLine(purchase.Id, 'A', 1, 10);
        return purchase;
    }

    private static String firstError(Database.SaveResult result) {
        System.assert(!result.isSuccess(), 'The save was expected to fail');
        return result.getErrors()[0].getMessage();
    }

    @IsTest
    static void newPurchasesDefaultToDraft() {
        Purchase__c purchase = new Purchase__c(Account__c = account().Id, Opportunity__c = opportunity().Id);
        insert purchase;
        System.assertEquals('Draft', [SELECT Status__c FROM Purchase__c WHERE Id = :purchase.Id].Status__c);
    }

    @IsTest
    static void purchaseCannotBeCreatedAsSubmitted() {
        Purchase__c purchase = new Purchase__c(
            Account__c = account().Id,
            Opportunity__c = opportunity().Id,
            Status__c = 'Submitted',
            Receipt_Email__c = 'a@example.com'
        );
        System.assertEquals('A purchase must be created as Draft.', firstError(Database.insert(purchase, false)));
    }

    @IsTest
    static void submittingStampsTheDateWhenLinesExist() {
        Purchase__c purchase = draftWithOneLine();
        Datetime before = System.now().addMinutes(-1);

        purchase.Status__c = 'Submitted';
        purchase.Receipt_Email__c = 'a@example.com';
        update purchase;

        Purchase__c saved = [SELECT Status__c, Submitted_On__c FROM Purchase__c WHERE Id = :purchase.Id];
        System.assertEquals('Submitted', saved.Status__c);
        System.assert(saved.Submitted_On__c >= before, 'Submitted On is stamped');
    }

    @IsTest
    static void submittingWithoutLinesIsRejected() {
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account().Id, opportunity().Id);
        purchase.Status__c = 'Submitted';
        purchase.Receipt_Email__c = 'a@example.com';

        System.assertEquals(
            'Add at least one product before submitting the purchase.',
            firstError(Database.update(purchase, false))
        );
    }

    @IsTest
    static void submittingNeedsAReceiptEmail() {
        Purchase__c purchase = draftWithOneLine();
        purchase.Status__c = 'Submitted';

        System.assertEquals(
            'Enter a receipt email before submitting the purchase.',
            firstError(Database.update(purchase, false))
        );
    }

    @IsTest
    static void lifeCycleOnlyMovesForward() {
        Purchase__c purchase = draftWithOneLine();
        purchase.Status__c = 'Submitted';
        purchase.Receipt_Email__c = 'a@example.com';
        update purchase;

        purchase.Status__c = 'Draft';
        System.assertEquals(
            'A Submitted purchase cannot be moved to Draft.',
            firstError(Database.update(purchase, false))
        );

        purchase.Status__c = 'Cancelled';
        update purchase;

        purchase.Status__c = 'Submitted';
        System.assertEquals(
            'A Cancelled purchase cannot be moved to Submitted.',
            firstError(Database.update(purchase, false))
        );
    }

    @IsTest
    static void draftCanBeCancelledDirectly() {
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account().Id, opportunity().Id);
        purchase.Status__c = 'Cancelled';
        update purchase;
        System.assertEquals('Cancelled', [SELECT Status__c FROM Purchase__c WHERE Id = :purchase.Id].Status__c);
    }

    @IsTest
    static void accountAndOpportunityAreFixedAfterCreation() {
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account().Id, opportunity().Id);
        Account otherAccount = OrderDeskTestFactory.createAccount('Another account');
        Opportunity otherOpp = OrderDeskTestFactory.createOpportunity(otherAccount.Id, 'Another opportunity');

        purchase.Account__c = otherAccount.Id;
        System.assertEquals(
            'The account of a purchase cannot be changed.',
            firstError(Database.update(purchase, false))
        );

        purchase.Account__c = account().Id;
        purchase.Opportunity__c = otherOpp.Id;
        System.assertEquals(
            'The opportunity of a purchase cannot be changed.',
            firstError(Database.update(purchase, false))
        );
    }

    @IsTest
    static void lineQuantityMustBePositive() {
        Purchase__c purchase = OrderDeskTestFactory.createDraft(account().Id, opportunity().Id);
        Purchase_Line__c line = OrderDeskTestFactory.newLine(purchase.Id, 'Z', 0, 10);
        System.assertEquals('Quantity must be greater than zero.', firstError(Database.insert(line, false)));
    }

    @IsTest
    static void twoHundredPurchasesAreSubmittedInOneUpdate() {
        List<Purchase__c> purchases = new List<Purchase__c>();
        for (Integer i = 0; i < 200; i++) {
            purchases.add(new Purchase__c(Account__c = account().Id, Opportunity__c = opportunity().Id));
        }
        insert purchases;
        List<Purchase_Line__c> lines = new List<Purchase_Line__c>();
        for (Integer i = 0; i < purchases.size(); i++) {
            lines.add(OrderDeskTestFactory.newLine(purchases[i].Id, 'L' + i, 1, 5));
            purchases[i].Status__c = 'Submitted';
            purchases[i].Receipt_Email__c = 'bulk@example.com';
        }
        insert lines;

        Test.startTest();
        List<Database.SaveResult> results = Database.update(purchases, false);
        Integer queries = Limits.getQueries();
        Test.stopTest();

        for (Database.SaveResult result : results) {
            System.assert(result.isSuccess(), 'Unexpected failure: ' + result.getErrors());
        }
        System.assertEquals(200, [SELECT COUNT() FROM Purchase__c WHERE Status__c = 'Submitted']);
        System.assert(queries <= 3, 'The trigger must not query per record. Queries used: ' + queries);
    }

    @IsTest
    static void transitionTableIsExhaustive() {
        System.assert(PurchaseTriggerHandler.isTransitionAllowed('Draft', 'Submitted'));
        System.assert(PurchaseTriggerHandler.isTransitionAllowed('Draft', 'Cancelled'));
        System.assert(PurchaseTriggerHandler.isTransitionAllowed('Submitted', 'Cancelled'));
        System.assert(!PurchaseTriggerHandler.isTransitionAllowed('Submitted', 'Draft'));
        System.assert(!PurchaseTriggerHandler.isTransitionAllowed('Cancelled', 'Draft'));
        System.assert(!PurchaseTriggerHandler.isTransitionAllowed('Unknown', 'Draft'));
    }
}
