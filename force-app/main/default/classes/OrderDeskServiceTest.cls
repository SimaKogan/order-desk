@IsTest
private class OrderDeskServiceTest {
    @TestSetup
    static void setup() {
        Account account = OrderDeskTestFactory.createAccount('Northwind Test Account');
        Opportunity opp = OrderDeskTestFactory.createOpportunity(account.Id, 'Northwind Renewal');
        OrderDeskTestFactory.addProducts(opp.Id, 3, 10, 25);
    }

    private static Opportunity opportunity() {
        return [SELECT Id, AccountId FROM Opportunity WHERE Name = 'Northwind Renewal'];
    }

    private static List<OpportunityLineItem> items() {
        return [SELECT Id, Name FROM OpportunityLineItem ORDER BY Name];
    }

    private static Purchase__c reload(Id purchaseId) {
        return [
            SELECT
                Id,
                Status__c,
                Total_Amount__c,
                Receipt_Email__c,
                Receipt_Sent__c,
                Submitted_On__c,
                (SELECT Id, Opportunity_Product_Id__c, Quantity__c FROM Lines__r ORDER BY Opportunity_Product_Id__c)
            FROM Purchase__c
            WHERE Id = :purchaseId
        ];
    }

    private static Decimal availableOf(Id opportunityId, String productName) {
        for (OrderDeskService.ProductLine product : OrderDeskService.getDeskState(opportunityId).products) {
            if (product.name == productName) {
                return product.available;
            }
        }
        return null;
    }

    private static String errorOf(System.Callable action) {
        try {
            action.call('run', null);
        } catch (OrderDeskException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void listOpportunitiesReturnsOnlyOpenOnesWithAccountAndProducts() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        OrderDeskTestFactory.createOpportunity(account.Id, 'No products');
        OrderDeskTestFactory.createOpportunity(null, 'No account');

        List<OrderDeskService.OpportunityOption> options = OrderDeskService.listOpportunities(null);

        System.assertEquals(1, options.size(), 'Only the opportunity with account and products is offered');
        System.assertEquals('Northwind Renewal', options[0].name);
        System.assertEquals('Northwind Test Account', options[0].accountName);
    }

    @IsTest
    static void addToCartCreatesDraftWithLines() {
        List<OpportunityLineItem> items = items();

        Test.startTest();
        Id purchaseId = OrderDeskService.addToCart(
            opportunity().Id,
            new List<OrderDeskService.LineRequest>{
                OrderDeskTestFactory.request(items[0].Id, 2),
                OrderDeskTestFactory.request(items[1].Id, 3),
                OrderDeskTestFactory.request(items[2].Id, 0)
            }
        );
        Test.stopTest();

        Purchase__c purchase = reload(purchaseId);
        System.assertEquals('Draft', purchase.Status__c);
        System.assertEquals(2, purchase.Lines__r.size(), 'Zero quantities are ignored');
        System.assertEquals(125, purchase.Total_Amount__c, '(2 + 3) units x 25');
    }

    @IsTest
    static void addToCartMergesIntoTheExistingDraft() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        Id first = OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 2) }
        );

        Id second = OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{
                OrderDeskTestFactory.request(items[0].Id, 4),
                OrderDeskTestFactory.request(items[0].Id, 1),
                OrderDeskTestFactory.request(items[2].Id, 1)
            }
        );

        System.assertEquals(first, second, 'The same draft is reused');
        System.assertEquals(1, [SELECT COUNT() FROM Purchase__c], 'No second draft is created');
        Purchase__c purchase = reload(first);
        Map<String, Decimal> quantityByItem = new Map<String, Decimal>();
        for (Purchase_Line__c line : purchase.Lines__r) {
            quantityByItem.put(line.Opportunity_Product_Id__c, line.Quantity__c);
        }
        System.assertEquals(2, quantityByItem.size());
        System.assertEquals(7, quantityByItem.get(String.valueOf(items[0].Id)), '2 + 4 + 1 (duplicates collapsed)');
        System.assertEquals(1, quantityByItem.get(String.valueOf(items[2].Id)));
    }

    @IsTest
    static void addToCartRejectsMoreThanAvailable() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;

        String tooMany = errorOf(
            new AddCall(oppId, new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 11) })
        );
        System.assert(tooMany != null && tooMany.contains('10 unit(s) left'), 'Message was: ' + tooMany);

        OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 8) }
        );
        String reserved = errorOf(
            new AddCall(oppId, new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 3) })
        );
        System.assert(reserved != null && reserved.contains('2 unit(s) left'), 'Message was: ' + reserved);
        System.assertEquals(1, [SELECT COUNT() FROM Purchase_Line__c], 'Nothing was added by the rejected requests');
    }

    @IsTest
    static void addToCartValidatesInput() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        List<OrderDeskService.LineRequest> one = new List<OrderDeskService.LineRequest>{
            OrderDeskTestFactory.request(items[0].Id, 1)
        };

        System.assertEquals(
            'Choose at least one product with a quantity above zero.',
            errorOf(new AddCall(oppId, null))
        );
        System.assertEquals(
            'Choose at least one product with a quantity above zero.',
            errorOf(new AddCall(oppId, new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 0) }))
        );
        System.assertEquals(
            'Every selected product needs a quantity of zero or more.',
            errorOf(new AddCall(oppId, new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, -1) }))
        );
        System.assertEquals(
            'Every selected product needs a quantity of zero or more.',
            errorOf(new AddCall(oppId, new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(null, 1) }))
        );
        System.assertEquals('Select an opportunity first.', errorOf(new AddCall(null, one)));

        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity otherOpp = OrderDeskTestFactory.createOpportunity(account.Id, 'Other');
        System.assertEquals(
            'A selected product does not belong to this opportunity.',
            errorOf(new AddCall(otherOpp.Id, one))
        );

        Opportunity noAccount = OrderDeskTestFactory.createOpportunity(null, 'Orphan');
        System.assertEquals(
            'Add an account to this opportunity before using the Order Desk.',
            errorOf(new AddCall(noAccount.Id, one))
        );
    }

    @IsTest
    static void addToCartIsBulkSafe() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity big = OrderDeskTestFactory.createOpportunity(account.Id, 'Big order');
        List<OpportunityLineItem> bigItems = OrderDeskTestFactory.addProducts(big.Id, 100, 5, 10);
        List<OrderDeskService.LineRequest> requests = new List<OrderDeskService.LineRequest>();
        for (OpportunityLineItem item : bigItems) {
            requests.add(OrderDeskTestFactory.request(item.Id, 2));
        }

        Test.startTest();
        Id purchaseId = OrderDeskService.addToCart(big.Id, requests);
        Integer queries = Limits.getQueries();
        Integer dmlStatements = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(100, reload(purchaseId).Lines__r.size());
        System.assert(queries <= 6, 'Queries used: ' + queries);
        System.assert(dmlStatements <= 3, 'DML statements used: ' + dmlStatements);
    }

    @IsTest
    static void deskStateShowsReservedAndAvailableUnits() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 4) }
        );

        OrderDeskService.DeskState state = OrderDeskService.getDeskState(oppId);

        System.assertEquals('Northwind Renewal', state.opportunityName);
        System.assertEquals('Northwind Test Account', state.accountName);
        System.assertEquals(3, state.products.size());
        Map<String, OrderDeskService.ProductLine> productByName = new Map<String, OrderDeskService.ProductLine>();
        for (OrderDeskService.ProductLine product : state.products) {
            productByName.put(product.name, product);
        }
        System.assertEquals(4, productByName.get('Product 1').reserved);
        System.assertEquals(6, productByName.get('Product 1').available);
        System.assertEquals(10, productByName.get('Product 2').available);
        System.assertNotEquals(null, state.cart);
        System.assertEquals(1, state.cart.lines.size());
        System.assertEquals(100, state.cart.total);
        System.assertEquals(100, state.cart.lines[0].lineTotal);
    }

    @IsTest
    static void deskStateWithoutCartHasNoCart() {
        System.assertEquals(null, OrderDeskService.getDeskState(opportunity().Id).cart);
    }

    @IsTest
    static void removeLineDeletesLinesOfDraftsOnly() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        Id purchaseId = OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{
                OrderDeskTestFactory.request(items[0].Id, 1),
                OrderDeskTestFactory.request(items[1].Id, 1)
            }
        );
        List<Purchase_Line__c> lines = reload(purchaseId).Lines__r;

        OrderDeskService.removeLine(lines[0].Id);
        System.assertEquals(1, reload(purchaseId).Lines__r.size());

        OrderDeskService.submit(purchaseId, 'buyer@example.com');
        System.assertEquals(
            'Only lines of a draft purchase can be removed.',
            errorOf(new RemoveCall(lines[1].Id))
        );
        System.assertEquals('Choose a cart line to remove.', errorOf(new RemoveCall(null)));
    }

    @IsTest
    static void submitMovesDraftToSubmittedAndReportsReceipt() {
        List<OpportunityLineItem> items = items();
        Id purchaseId = OrderDeskService.addToCart(
            opportunity().Id,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 2) }
        );

        Test.startTest();
        OrderDeskService.SubmitResult result = OrderDeskService.submit(purchaseId, '  buyer@example.com ');
        Test.stopTest();

        Purchase__c purchase = reload(purchaseId);
        System.assertEquals('Submitted', purchase.Status__c);
        System.assertEquals('buyer@example.com', purchase.Receipt_Email__c);
        System.assertNotEquals(null, purchase.Submitted_On__c);
        System.assertEquals(purchaseId, result.purchaseId);
        System.assertEquals(purchase.Receipt_Sent__c, result.receiptSent, 'Result mirrors the Receipt Sent flag');
        System.assertEquals(null, OrderDeskService.getDeskState(opportunity().Id).cart, 'The cart is closed');
    }

    @IsTest
    static void submitAllHandlesSeveralPurchases() {
        List<OpportunityLineItem> items = items();
        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity second = OrderDeskTestFactory.createOpportunity(account.Id, 'Second deal');
        List<OpportunityLineItem> secondItems = OrderDeskTestFactory.addProducts(second.Id, 1, 3, 40);
        Id firstId = OrderDeskService.addToCart(
            opportunity().Id,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 1) }
        );
        Id secondId = OrderDeskService.addToCart(
            second.Id,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(secondItems[0].Id, 3) }
        );

        List<OrderDeskService.SubmitResult> results = OrderDeskService.submitAll(
            new Map<Id, String>{ firstId => 'a@example.com', secondId => 'b@example.com' }
        );

        System.assertEquals(2, results.size());
        System.assertEquals('Submitted', reload(firstId).Status__c);
        System.assertEquals('Submitted', reload(secondId).Status__c);
        System.assertEquals('b@example.com', reload(secondId).Receipt_Email__c);
    }

    @IsTest
    static void submitRejectsInvalidRequests() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        Id purchaseId = OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 1) }
        );

        String badEmail = 'Enter a valid email address for the receipt.';
        System.assertEquals(badEmail, errorOf(new SubmitCall(purchaseId, 'not-an-email')));
        System.assertEquals(badEmail, errorOf(new SubmitCall(purchaseId, ' ')));
        System.assertEquals('There is no cart to submit.', errorOf(new SubmitCall(null, 'a@example.com')));
        System.assertEquals('There is nothing to submit.', errorOf(new SubmitAllCall(null)));

        OrderDeskService.submit(purchaseId, 'a@example.com');
        String again = errorOf(new SubmitCall(purchaseId, 'a@example.com'));
        System.assert(again != null && again.contains('already been submitted'), 'Message was: ' + again);

        Account account = [SELECT Id FROM Account LIMIT 1];
        Purchase__c empty = OrderDeskTestFactory.createDraft(account.Id, oppId);
        String noLines = errorOf(new SubmitCall(empty.Id, 'a@example.com'));
        System.assertEquals('Add at least one product before submitting the purchase.', noLines);

        Id ghostId = (Id) (Purchase__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        System.assertEquals(
            'The purchase was not found or you do not have access to it.',
            errorOf(new SubmitCall(ghostId, 'a@example.com'))
        );
    }

    @IsTest
    static void cancellingAPurchaseReleasesItsUnits() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        Id purchaseId = OrderDeskService.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 10) }
        );
        System.assertEquals(0, availableOf(oppId, 'Product 1'));

        update new Purchase__c(Id = purchaseId, Status__c = 'Cancelled');

        System.assertEquals(10, availableOf(oppId, 'Product 1'));
    }

    @IsTest
    static void userWithoutPermissionsCannotUseTheDesk() {
        User user = OrderDeskTestFactory.createStandardUser();
        if (user == null) {
            return; // org without a "Standard User" profile
        }
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;
        Boolean denied = false;

        System.runAs(user) {
            try {
                OrderDeskService.addToCart(
                    oppId,
                    new List<OrderDeskService.LineRequest>{ OrderDeskTestFactory.request(items[0].Id, 1) }
                );
            } catch (Exception e) {
                // not visible (OrderDeskException), no object access (QueryException / NoAccessException)
                denied = e instanceof OrderDeskException || e instanceof QueryException || e instanceof NoAccessException;
            }
        }

        System.assert(denied, 'User mode must stop a user without Order Desk permissions');
        System.assertEquals(0, [SELECT COUNT() FROM Purchase__c]);
    }

    // ---- small System.Callable adapters so one helper can assert on thrown messages ----

    private class AddCall implements System.Callable {
        private Id opportunityId;
        private List<OrderDeskService.LineRequest> requests;
        public AddCall(Id opportunityId, List<OrderDeskService.LineRequest> requests) {
            this.opportunityId = opportunityId;
            this.requests = requests;
        }
        public Object call(String action, Map<String, Object> args) {
            return OrderDeskService.addToCart(opportunityId, requests);
        }
    }

    private class RemoveCall implements System.Callable {
        private Id lineId;
        public RemoveCall(Id lineId) {
            this.lineId = lineId;
        }
        public Object call(String action, Map<String, Object> args) {
            OrderDeskService.removeLine(lineId);
            return null;
        }
    }

    private class SubmitCall implements System.Callable {
        private Id purchaseId;
        private String email;
        public SubmitCall(Id purchaseId, String email) {
            this.purchaseId = purchaseId;
            this.email = email;
        }
        public Object call(String action, Map<String, Object> args) {
            return OrderDeskService.submit(purchaseId, email);
        }
    }

    private class SubmitAllCall implements System.Callable {
        private Map<Id, String> emails;
        public SubmitAllCall(Map<Id, String> emails) {
            this.emails = emails;
        }
        public Object call(String action, Map<String, Object> args) {
            return OrderDeskService.submitAll(emails);
        }
    }
}
