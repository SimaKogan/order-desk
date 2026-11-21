/**
 * Test data helpers shared by the Order Desk tests.
 */
@IsTest
public class OrderDeskTestFactory {
    public static Account createAccount(String name) {
        Account account = new Account(Name = name);
        insert account;
        return account;
    }

    public static Opportunity createOpportunity(Id accountId, String name) {
        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;
        return opp;
    }

    /** Adds `count` new products ("Product 1", "Product 2", ...) to the opportunity, each with the same quantity and price. */
    public static List<OpportunityLineItem> addProducts(
        Id opportunityId,
        Integer count,
        Decimal quantity,
        Decimal unitPrice
    ) {
        List<Product2> products = new List<Product2>();
        for (Integer i = 1; i <= count; i++) {
            products.add(new Product2(Name = 'Product ' + i, IsActive = true));
        }
        insert products;

        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            entries.add(
                new PricebookEntry(
                    Pricebook2Id = Test.getStandardPricebookId(),
                    Product2Id = product.Id,
                    UnitPrice = unitPrice,
                    IsActive = true
                )
            );
        }
        insert entries;

        List<OpportunityLineItem> items = new List<OpportunityLineItem>();
        for (PricebookEntry entry : entries) {
            items.add(
                new OpportunityLineItem(
                    OpportunityId = opportunityId,
                    PricebookEntryId = entry.Id,
                    Quantity = quantity,
                    UnitPrice = unitPrice
                )
            );
        }
        insert items;
        return items;
    }

    public static OrderDeskService.LineRequest request(Id lineId, Integer quantity) {
        OrderDeskService.LineRequest request = new OrderDeskService.LineRequest();
        request.lineId = lineId;
        request.quantity = quantity;
        return request;
    }

    public static Purchase__c createDraft(Id accountId, Id opportunityId) {
        Purchase__c purchase = new Purchase__c(
            Account__c = accountId,
            Opportunity__c = opportunityId,
            Status__c = 'Draft'
        );
        insert purchase;
        return purchase;
    }

    public static Purchase_Line__c newLine(Id purchaseId, String key, Decimal quantity, Decimal unitPrice) {
        return new Purchase_Line__c(
            Purchase__c = purchaseId,
            Product_Name__c = 'Line ' + key,
            Opportunity_Product_Id__c = key,
            Line_Key__c = purchaseId + '-' + key,
            Quantity__c = quantity,
            Unit_Price__c = unitPrice
        );
    }

    /** A standard user without any Order Desk permissions, or null when the org has no "Standard User" profile. */
    public static User createStandardUser() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (profiles.isEmpty()) {
            return null;
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User user = new User(
            Alias = 'odtest',
            Email = 'orderdesk.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profiles[0].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'orderdesk.' + unique + '@example.com'
        );
        // Setup objects and regular records must not be mixed in one transaction without runAs.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
        }
        return user;
    }
}
