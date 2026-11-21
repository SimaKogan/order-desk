@IsTest
private class OrderDeskControllerTest {
    @TestSetup
    static void setup() {
        Account account = OrderDeskTestFactory.createAccount('Controller Test Account');
        Opportunity opp = OrderDeskTestFactory.createOpportunity(account.Id, 'Controller Opportunity');
        OrderDeskTestFactory.addProducts(opp.Id, 2, 4, 20);
    }

    private static Opportunity opportunity() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

    private static List<OpportunityLineItem> items() {
        return [SELECT Id FROM OpportunityLineItem ORDER BY Name];
    }

    private static String messageOf(AuraHandledException e) {
        return e.getMessage();
    }

    @IsTest
    static void fullFlowThroughTheController() {
        List<OpportunityLineItem> items = items();
        Id oppId = opportunity().Id;

        System.assertEquals(1, OrderDeskController.listOpportunities().size());

        OrderDeskService.DeskState state = OrderDeskController.addToCart(
            oppId,
            new List<OrderDeskService.LineRequest>{
                OrderDeskTestFactory.request(items[0].Id, 2),
                OrderDeskTestFactory.request(items[1].Id, 1)
            }
        );
        System.assertEquals(2, state.cart.lines.size());
        System.assertEquals(60, state.cart.total);

        state = OrderDeskController.removeLine(oppId, state.cart.lines[0].Id);
        System.assertEquals(1, state.cart.lines.size());
        System.assertEquals(state.cart.id, OrderDeskController.getDeskState(oppId).cart.id);

        OrderDeskService.SubmitResult result = OrderDeskController.submitPurchase(state.cart.id, 'buyer@example.com');
        System.assertEquals(state.cart.id, result.purchaseId);
        System.assertEquals(null, OrderDeskController.getDeskState(oppId).cart);
    }

    @IsTest
    static void businessErrorsReachTheUserUnchanged() {
        try {
            OrderDeskController.getDeskState(null);
            System.assert(false, 'An exception was expected');
        } catch (AuraHandledException e) {
            System.assertEquals('Select an opportunity first.', messageOf(e));
        }

        try {
            OrderDeskController.addToCart(opportunity().Id, new List<OrderDeskService.LineRequest>());
            System.assert(false, 'An exception was expected');
        } catch (AuraHandledException e) {
            System.assertEquals('Choose at least one product with a quantity above zero.', messageOf(e));
        }

        try {
            OrderDeskController.removeLine(opportunity().Id, null);
            System.assert(false, 'An exception was expected');
        } catch (AuraHandledException e) {
            System.assertEquals('Choose a cart line to remove.', messageOf(e));
        }

        try {
            OrderDeskController.submitPurchase(null, 'buyer@example.com');
            System.assert(false, 'An exception was expected');
        } catch (AuraHandledException e) {
            System.assertEquals('There is no cart to submit.', messageOf(e));
        }
    }

    @IsTest
    static void unknownCartLineIsReportedAsNotFound() {
        Id missingLine = (Id) (Purchase_Line__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        try {
            OrderDeskController.removeLine(opportunity().Id, missingLine);
            System.assert(false, 'An exception was expected');
        } catch (AuraHandledException e) {
            System.assertEquals('The cart line was not found or you do not have access to it.', messageOf(e));
        }
    }
}
