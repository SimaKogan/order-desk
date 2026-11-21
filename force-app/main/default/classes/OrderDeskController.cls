/**
 * Thin @AuraEnabled facade for the Order Desk Lightning components. Business rules live in OrderDeskService.
 * Rule violations are shown to the user as-is; anything unexpected is logged and replaced by a generic message.
 */
public with sharing class OrderDeskController {
    @AuraEnabled(cacheable=true)
    public static List<OrderDeskService.OpportunityOption> listOpportunities() {
        try {
            return OrderDeskService.listOpportunities(50);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OrderDeskService.DeskState getDeskState(Id opportunityId) {
        try {
            return OrderDeskService.getDeskState(opportunityId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OrderDeskService.DeskState addToCart(
        Id opportunityId,
        List<OrderDeskService.LineRequest> lines
    ) {
        try {
            OrderDeskService.addToCart(opportunityId, lines);
            return OrderDeskService.getDeskState(opportunityId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OrderDeskService.DeskState removeLine(Id opportunityId, Id lineId) {
        try {
            OrderDeskService.removeLine(lineId);
            return OrderDeskService.getDeskState(opportunityId);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static OrderDeskService.SubmitResult submitPurchase(Id purchaseId, String receiptEmail) {
        try {
            return OrderDeskService.submit(purchaseId, receiptEmail);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    private static AuraHandledException toAuraException(Exception e) {
        String message;
        if (e instanceof OrderDeskException) {
            message = e.getMessage();
        } else if (e instanceof NoAccessException) {
            message = 'You do not have permission to do this.';
        } else {
            System.debug(LoggingLevel.ERROR, e.getMessage() + '\n' + e.getStackTraceString());
            message = 'Something went wrong. Please try again or contact your administrator.';
        }
        AuraHandledException result = new AuraHandledException(message);
        result.setMessage(message);
        return result;
    }
}
