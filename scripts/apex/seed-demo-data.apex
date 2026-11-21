// Demo data for the Order Desk. Run with:
//   sf apex run --file scripts/apex/seed-demo-data.apex
// All names are fictional.
Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;

Account account = new Account(Name = 'Northwind Traders');
insert account;

String[] names = new String[]{ 'Trail Backpack 30L', 'Insulated Bottle 750ml', 'Headlamp Pro', 'Camp Stove Mini', 'Merino Socks' };
Decimal[] prices = new Decimal[]{ 89.00, 24.50, 39.90, 54.00, 16.00 };
Integer[] quantities = new Integer[]{ 6, 20, 10, 4, 30 };

List<Product2> products = new List<Product2>();
for (String name : names) {
    products.add(new Product2(Name = name, IsActive = true));
}
insert products;

List<PricebookEntry> entries = new List<PricebookEntry>();
for (Integer i = 0; i < products.size(); i++) {
    entries.add(new PricebookEntry(Pricebook2Id = standardPricebookId, Product2Id = products[i].Id, UnitPrice = prices[i], IsActive = true));
}
insert entries;

Opportunity opp = new Opportunity(
    Name = 'Northwind spring outfitting',
    AccountId = account.Id,
    StageName = 'Proposal/Price Quote',
    CloseDate = Date.today().addDays(45),
    Pricebook2Id = standardPricebookId
);
insert opp;

List<OpportunityLineItem> items = new List<OpportunityLineItem>();
for (Integer i = 0; i < entries.size(); i++) {
    items.add(new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = entries[i].Id, Quantity = quantities[i], UnitPrice = prices[i]));
}
insert items;

System.debug('Demo opportunity: ' + opp.Id);
