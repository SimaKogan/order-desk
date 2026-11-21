/**
 * Business logic of the Order Desk.
 *
 * - reads the "desk" of an opportunity: its products, how many units are still available, and the open cart
 * - adds products to the cart (a Draft purchase) in bulk, merging quantities for products already in the cart
 * - removes cart lines and submits purchases (which sends the receipt)
 *
 * Opportunity products are never modified. Stock is tracked by reserving quantities on purchase lines, so
 * cancelling a purchase releases its units again. Every query and DML statement runs in user mode, so object
 * permissions, field-level security and sharing of the running user always apply.
 */
public with sharing class OrderDeskService {
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_CANCELLED = 'Cancelled';

    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$'
    );

    // ------------------------------------------------------------------ transfer objects

    public class OpportunityOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String accountName;
    }

    public class ProductLine {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal quantity;
        @AuraEnabled
        public Decimal unitPrice;
        @AuraEnabled
        public Decimal reserved;
        @AuraEnabled
        public Decimal available;
    }

    public class CartLine {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String productName;
        @AuraEnabled
        public Decimal quantity;
        @AuraEnabled
        public Decimal unitPrice;
        @AuraEnabled
        public Decimal lineTotal;
    }

    public class Cart {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String receiptEmail;
        @AuraEnabled
        public Decimal total;
        @AuraEnabled
        public List<CartLine> lines = new List<CartLine>();
    }

    public class DeskState {
        @AuraEnabled
        public Id opportunityId;
        @AuraEnabled
        public String opportunityName;
        @AuraEnabled
        public String accountName;
        @AuraEnabled
        public List<ProductLine> products = new List<ProductLine>();
        @AuraEnabled
        public Cart cart;
    }

    public class LineRequest {
        @AuraEnabled
        public Id lineId;
        @AuraEnabled
        public Integer quantity;
    }

    public class SubmitResult {
        @AuraEnabled
        public Id purchaseId;
        @AuraEnabled
        public String purchaseName;
        @AuraEnabled
        public Boolean receiptSent;
    }

    // ------------------------------------------------------------------ reading

    /** Open opportunities that have an account and at least one product, most recently changed first. */
    public static List<OpportunityOption> listOpportunities(Integer maxRows) {
        Integer rowLimit = (maxRows == null || maxRows < 1 || maxRows > 200) ? 50 : maxRows;
        List<OpportunityOption> options = new List<OpportunityOption>();
        for (Opportunity opp : [
            SELECT Id, Name, Account.Name
            FROM Opportunity
            WHERE AccountId != NULL AND HasOpportunityLineItem = TRUE AND IsClosed = FALSE
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT :rowLimit
        ]) {
            OpportunityOption option = new OpportunityOption();
            option.id = opp.Id;
            option.name = opp.Name;
            option.accountName = opp.Account.Name;
            options.add(option);
        }
        return options;
    }

    public static DeskState getDeskState(Id opportunityId) {
        Opportunity opp = loadOpportunity(opportunityId);
        Map<Id, Decimal> reserved = reservedByOpportunityProduct(opportunityId);

        DeskState state = new DeskState();
        state.opportunityId = opp.Id;
        state.opportunityName = opp.Name;
        state.accountName = opp.Account.Name;

        for (OpportunityLineItem item : [
            SELECT Id, Name, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            WITH USER_MODE
            ORDER BY CreatedDate, Id
        ]) {
            Decimal taken = reserved.containsKey(item.Id) ? reserved.get(item.Id) : 0;
            ProductLine line = new ProductLine();
            line.id = item.Id;
            line.name = item.Name;
            line.quantity = item.Quantity;
            line.unitPrice = item.UnitPrice;
            line.reserved = taken;
            line.available = remainingUnits(item.Quantity, taken);
            state.products.add(line);
        }

        Purchase__c draft = findDraft(opportunityId);
        state.cart = draft == null ? null : toCart(draft);
        return state;
    }

    // ------------------------------------------------------------------ cart

    /**
     * Adds the requested quantities to the open cart of the opportunity, creating the cart when needed.
     * Runs with a fixed number of queries and DML statements no matter how many products are requested.
     * @return the id of the draft purchase
     */
    public static Id addToCart(Id opportunityId, List<LineRequest> requests) {
        Map<Id, Integer> wanted = collapse(requests);
        if (wanted.isEmpty()) {
            throw new OrderDeskException('Choose at least one product with a quantity above zero.');
        }

        Opportunity opp = loadOpportunity(opportunityId);
        Set<Id> itemIds = wanted.keySet();
        Map<Id, OpportunityLineItem> items = new Map<Id, OpportunityLineItem>(
            [
                SELECT Id, Name, Product2Id, Quantity, UnitPrice
                FROM OpportunityLineItem
                WHERE OpportunityId = :opportunityId AND Id IN :itemIds
                WITH USER_MODE
            ]
        );
        Map<Id, Decimal> reserved = reservedByOpportunityProduct(opportunityId);

        for (Id itemId : wanted.keySet()) {
            OpportunityLineItem item = items.get(itemId);
            if (item == null) {
                throw new OrderDeskException('A selected product does not belong to this opportunity.');
            }
            Decimal taken = reserved.containsKey(itemId) ? reserved.get(itemId) : 0;
            Decimal available = remainingUnits(item.Quantity, taken);
            if (wanted.get(itemId) > available) {
                throw new OrderDeskException(
                    '"' + item.Name + '" has only ' + available.intValue() + ' unit(s) left.'
                );
            }
        }

        Purchase__c draft = findDraft(opportunityId);
        Map<String, Purchase_Line__c> existingByItem = new Map<String, Purchase_Line__c>();
        if (draft == null) {
            draft = new Purchase__c(
                Account__c = opp.AccountId,
                Opportunity__c = opp.Id,
                Status__c = STATUS_DRAFT
            );
            insert as user draft;
        } else {
            for (Purchase_Line__c line : draft.Lines__r) {
                existingByItem.put(line.Opportunity_Product_Id__c, line);
            }
        }

        List<Purchase_Line__c> toInsert = new List<Purchase_Line__c>();
        List<Purchase_Line__c> toUpdate = new List<Purchase_Line__c>();
        for (Id itemId : wanted.keySet()) {
            OpportunityLineItem item = items.get(itemId);
            Purchase_Line__c existing = existingByItem.get(String.valueOf(itemId));
            if (existing == null) {
                toInsert.add(
                    new Purchase_Line__c(
                        Purchase__c = draft.Id,
                        Product__c = item.Product2Id,
                        Product_Name__c = item.Name.abbreviate(255),
                        Opportunity_Product_Id__c = String.valueOf(itemId),
                        Line_Key__c = lineKey(draft.Id, itemId),
                        Quantity__c = wanted.get(itemId),
                        Unit_Price__c = item.UnitPrice
                    )
                );
            } else {
                existing.Quantity__c = existing.Quantity__c + wanted.get(itemId);
                toUpdate.add(existing);
            }
        }
        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update as user toUpdate;
        }
        return draft.Id;
    }

    public static void removeLine(Id lineId) {
        if (lineId == null) {
            throw new OrderDeskException('Choose a cart line to remove.');
        }
        List<Purchase_Line__c> lines = [
            SELECT Id, Purchase__r.Status__c
            FROM Purchase_Line__c
            WHERE Id = :lineId
            WITH USER_MODE
        ];
        if (lines.isEmpty()) {
            throw new OrderDeskException('The cart line was not found or you do not have access to it.');
        }
        if (lines[0].Purchase__r.Status__c != STATUS_DRAFT) {
            throw new OrderDeskException('Only lines of a draft purchase can be removed.');
        }
        delete as user lines;
    }

    // ------------------------------------------------------------------ checkout

    public static SubmitResult submit(Id purchaseId, String receiptEmail) {
        if (purchaseId == null) {
            throw new OrderDeskException('There is no cart to submit.');
        }
        return submitAll(new Map<Id, String>{ purchaseId => receiptEmail })[0];
    }

    /** Submits many draft purchases at once and sends one receipt per purchase. */
    public static List<SubmitResult> submitAll(Map<Id, String> emailByPurchase) {
        if (emailByPurchase == null || emailByPurchase.isEmpty()) {
            throw new OrderDeskException('There is nothing to submit.');
        }
        for (String email : emailByPurchase.values()) {
            if (String.isBlank(email) || !EMAIL_PATTERN.matcher(email.trim()).matches()) {
                throw new OrderDeskException('Enter a valid email address for the receipt.');
            }
        }

        Set<Id> purchaseIds = emailByPurchase.keySet();
        Map<Id, Purchase__c> purchases = new Map<Id, Purchase__c>(
            [SELECT Id, Name, Status__c FROM Purchase__c WHERE Id IN :purchaseIds WITH USER_MODE]
        );
        for (Id purchaseId : purchaseIds) {
            Purchase__c purchase = purchases.get(purchaseId);
            if (purchase == null) {
                throw new OrderDeskException('The purchase was not found or you do not have access to it.');
            }
            if (purchase.Status__c != STATUS_DRAFT) {
                throw new OrderDeskException(purchase.Name + ' has already been submitted or cancelled.');
            }
            purchase.Status__c = STATUS_SUBMITTED;
            purchase.Receipt_Email__c = emailByPurchase.get(purchaseId).trim();
        }

        List<Purchase__c> toUpdate = purchases.values();
        try {
            update as user toUpdate;
        } catch (DmlException e) {
            throw new OrderDeskException(e.getDmlMessage(0));
        }

        Set<Id> receiptsSent = ReceiptMailer.send(purchaseIds);
        List<SubmitResult> results = new List<SubmitResult>();
        for (Purchase__c purchase : toUpdate) {
            SubmitResult result = new SubmitResult();
            result.purchaseId = purchase.Id;
            result.purchaseName = purchase.Name;
            result.receiptSent = receiptsSent.contains(purchase.Id);
            results.add(result);
        }
        return results;
    }

    // ------------------------------------------------------------------ helpers

    private static Opportunity loadOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new OrderDeskException('Select an opportunity first.');
        }
        List<Opportunity> found = [
            SELECT Id, Name, AccountId, Account.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new OrderDeskException('The opportunity was not found or you do not have access to it.');
        }
        if (found[0].AccountId == null) {
            throw new OrderDeskException('Add an account to this opportunity before using the Order Desk.');
        }
        return found[0];
    }

    /** Units already taken from each opportunity product by Draft and Submitted purchases. */
    private static Map<Id, Decimal> reservedByOpportunityProduct(Id opportunityId) {
        Map<Id, Decimal> reserved = new Map<Id, Decimal>();
        for (AggregateResult result : [
            SELECT Opportunity_Product_Id__c itemId, SUM(Quantity__c) units
            FROM Purchase_Line__c
            WHERE Purchase__r.Opportunity__c = :opportunityId AND Purchase__r.Status__c != :STATUS_CANCELLED
            WITH USER_MODE
            GROUP BY Opportunity_Product_Id__c
        ]) {
            String itemId = (String) result.get('itemId');
            if (itemId != null) {
                reserved.put((Id) itemId, (Decimal) result.get('units'));
            }
        }
        return reserved;
    }

    private static Purchase__c findDraft(Id opportunityId) {
        List<Purchase__c> drafts = [
            SELECT
                Id,
                Name,
                Receipt_Email__c,
                Total_Amount__c,
                (
                    SELECT Id, Product_Name__c, Opportunity_Product_Id__c, Quantity__c, Unit_Price__c, Line_Total__c
                    FROM Lines__r
                    ORDER BY CreatedDate, Id
                )
            FROM Purchase__c
            WHERE Opportunity__c = :opportunityId AND Status__c = :STATUS_DRAFT
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return drafts.isEmpty() ? null : drafts[0];
    }

    private static Cart toCart(Purchase__c draft) {
        Cart cart = new Cart();
        cart.id = draft.Id;
        cart.name = draft.Name;
        cart.receiptEmail = draft.Receipt_Email__c;
        cart.total = draft.Total_Amount__c == null ? 0 : draft.Total_Amount__c;
        for (Purchase_Line__c line : draft.Lines__r) {
            CartLine view = new CartLine();
            view.id = line.Id;
            view.productName = line.Product_Name__c;
            view.quantity = line.Quantity__c;
            view.unitPrice = line.Unit_Price__c;
            view.lineTotal = line.Line_Total__c;
            cart.lines.add(view);
        }
        return cart;
    }

    /** Validates the request and sums quantities when the same product is listed more than once. */
    private static Map<Id, Integer> collapse(List<LineRequest> requests) {
        Map<Id, Integer> wanted = new Map<Id, Integer>();
        if (requests == null) {
            return wanted;
        }
        for (LineRequest request : requests) {
            if (request == null || request.lineId == null || request.quantity == null || request.quantity < 0) {
                throw new OrderDeskException('Every selected product needs a quantity of zero or more.');
            }
            if (request.quantity == 0) {
                continue;
            }
            Integer current = wanted.containsKey(request.lineId) ? wanted.get(request.lineId) : 0;
            wanted.put(request.lineId, current + request.quantity);
        }
        return wanted;
    }

    private static Decimal remainingUnits(Decimal ordered, Decimal taken) {
        Decimal remaining = ordered - taken;
        return remaining < 0 ? 0.0 : remaining;
    }

    private static String lineKey(Id purchaseId, Id itemId) {
        return String.valueOf(purchaseId) + '-' + String.valueOf(itemId);
    }
}
