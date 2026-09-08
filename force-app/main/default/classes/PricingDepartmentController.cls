public without sharing class PricingDepartmentController {
    
    public class UniqueCarrierQuote {
        public rtms__CarrierQuote__c quote;

        public UniqueCarrierQuote(rtms__CarrierQuote__c quote) {
            this.quote = quote;
        }

        public Boolean equals(Object obj) {
            if (obj instanceof UniqueCarrierQuote) {
                UniqueCarrierQuote other = (UniqueCarrierQuote) obj; 
                return (
                    quote.CAD_Quote_Total__c == other.quote.CAD_Quote_Total__c &&
                    quote.Carrier_Name__c == other.quote.Carrier_Name__c &&
                    quote.Origin__c == other.quote.Origin__c &&
                    quote.Destination__c == other.quote.Destination__c &&
                    quote.Mode__c == other.quote.Mode__c &&
                    quote.Equipment_Type__c == other.quote.Equipment_Type__c
                );
            }
            return false;
        }

        public Integer hashCode() {
            return (
                decimalHashCode(quote.CAD_Quote_Total__c) ^
                (quote.Carrier_Name__c == null ? 0 : quote.Carrier_Name__c.hashCode()) ^
                (quote.Origin__c == null ? 0 : quote.Origin__c.hashCode()) ^
                (quote.Destination__c == null ? 0 : quote.Destination__c.hashCode()) ^
                (quote.Mode__c == null ? 0 : quote.Mode__c.hashCode()) ^
                (quote.Equipment_Type__c == null ? 0 : quote.Equipment_Type__c.hashCode())
            );
        }

        private Integer decimalHashCode(Decimal value) {
            return value == null ? 0 : value.toPlainString().hashCode();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<rtms__CarrierQuote__c> getCarrierQuotes(String originFilter, String destinationFilter, 
                                                               String modeFilter, String hazmatFilter, 
                                                               String priceDepFilter, String equipmentFilter, 
                                                               Integer dateRangeFilter, String acceptedQuotesFilter,
                                                               String declinedQuotesFilter) {
        String originFilterStr = createFilterString(originFilter);
        String destinationFilterStr = createFilterString(destinationFilter);
        String modeFilterStr = createFilterString(modeFilter);
        String hazmatFilterStr = createFilterString(hazmatFilter);
        String priceDepFilterStr = createFilterString(priceDepFilter);
        String equipmentFilterStr = createFilterString(equipmentFilter);
        String acceptedQuotesFilterStr = createFilterString(acceptedQuotesFilter);
        String declinedQuotesFilterStr = createFilterString(declinedQuotesFilter);
        Date startDate = Date.today().addDays(-dateRangeFilter);

        List<rtms__CarrierQuote__c> allCarrierQuotes = fetchCarrierQuotes(originFilterStr, destinationFilterStr, modeFilterStr, 
                                                                          hazmatFilterStr, priceDepFilterStr, equipmentFilterStr, 
                                                                          startDate, acceptedQuotesFilterStr, declinedQuotesFilterStr);

        Set<UniqueCarrierQuote> uniqueCarrierQuoteSet = new Set<UniqueCarrierQuote>();
        List<rtms__CarrierQuote__c> uniqueCarrierQuotes = new List<rtms__CarrierQuote__c>();

        for (rtms__CarrierQuote__c carrierQuote : allCarrierQuotes) {
            UniqueCarrierQuote uniqueCarrierQuote = new UniqueCarrierQuote(carrierQuote);
            if (!uniqueCarrierQuoteSet.contains(uniqueCarrierQuote)) {
                uniqueCarrierQuoteSet.add(uniqueCarrierQuote);
                uniqueCarrierQuotes.add(carrierQuote);
            }
        }

        return uniqueCarrierQuotes;
    }

    private static String createFilterString(String filter) {
        return '%' + filter + '%';
    }

    private static List<rtms__CarrierQuote__c> fetchCarrierQuotes(String originFilterStr, String destinationFilterStr, 
                                                                  String modeFilterStr, String hazmatFilterStr, 
                                                                  String priceDepFilterStr, String equipmentFilterStr, 
                                                                  Date startDate, String acceptedQuotesFilterStr, 
                                                                  String declinedQuotesFilterStr) {
        return [
            SELECT Id, 
                   CAD_Quote_Total__c, 
                   Carrier_Contact__c, 
                   Contact_Email__c, 
                   Destination__c, 
                   Contact_Phone__c, 
                   Equipment_Type__c, 
                   Mode__c,  
                   Nb_Of_Pallets__c, 
                   Ops_Comments__c, 
                   Ship_Date__c, 
                   rtms__Carrier_Service__c, 
                   Name,
                   rtms__Vendor__c,
                   rtms__Vendor__r.Name,
                   Contact_ID__c,
                   Carrier_Name__c,
                   Origin_Destination_Country__c, 
                   Hazmat__c,
                   Customer_Name__c,
                   Quote_Date__c,
                   Origin__c,
                   Load_Status__c, 
                   Accepted_quote__c,
                   Decline_Quotes__c,
                   rtms__Carrier_Total__c,
                   CurrencyIsoCode,
                   Carrier_Risk__c,
                   Nb_of_loads__c,
                   Carrier_Att__c,
                   rtms__Load__c
            FROM rtms__CarrierQuote__c
            WHERE (Origin__c LIKE :originFilterStr) AND
                  (Destination__c LIKE :destinationFilterStr) AND
                  (Mode__c LIKE :modeFilterStr) AND
                  (Hazmat__c LIKE :hazmatFilterStr) AND
                  (Customer_Name__c LIKE :priceDepFilterStr) AND
                  (Equipment_Type__c LIKE :equipmentFilterStr) AND
                  Quote_Date__c >= :startDate AND
                  (Accepted_quote__c LIKE :acceptedQuotesFilterStr) AND
                  (Decline_Quotes__c LIKE :declinedQuotesFilterStr) AND
                  Contact_ID__c != '0033l00002px9ja'
            ORDER BY Quote_Date__c DESC
            LIMIT 500
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getUniqueModeOptions(String originFilter, String destinationFilter) {
        String originFilterStr = createFilterString(originFilter);
        String destinationFilterStr = createFilterString(destinationFilter);

        List<rtms__CarrierQuote__c> quotes = [
            SELECT Mode__c
            FROM rtms__CarrierQuote__c
            WHERE (Origin__c LIKE :originFilterStr) AND
                  (Destination__c LIKE :destinationFilterStr) AND
                  Origin_Destination_Country__c != ' / ' AND
                  Contact_ID__c != '0033l00002px9ja'
        ];

        Set<String> uniqueModeOptionsSet = new Set<String>();
        for (rtms__CarrierQuote__c quote : quotes) {
            uniqueModeOptionsSet.add(quote.Mode__c);
        }

        return new List<String>(uniqueModeOptionsSet);
    }
}