/**
 * Typed output of LaneSearchService.search(). Plain data, no logic. Every public field carries
 * @AuraEnabled so phase 2's LWC can consume this object (and its Row/Stats members) straight out
 * of an @AuraEnabled controller method with no DTO in between.
 */
public class LaneSearchResult {
  public class Row {
    @AuraEnabled
    public Id quoteId;
    @AuraEnabled
    public String quoteName;
    @AuraEnabled
    public Id loadId;
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public String destination;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String equipment;
    @AuraEnabled
    public String equipmentCategory;
    @AuraEnabled
    public String carrierName;
    @AuraEnabled
    public String contactName;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal carrierTotal;
    @AuraEnabled
    public Date quoteDate;
    @AuraEnabled
    public Boolean hazmat;
    @AuraEnabled
    public Boolean accepted;
    @AuraEnabled
    public String loadStatus;
    @AuraEnabled
    public String opsComments;
    // The quote's own CreatedDate, which is what rows are ordered by (Quote_Date__c is a formula
    // and can be blank); phase 2 shows it as the row's age.
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public CarrierDetail carrier = new CarrierDetail();
  }

  // Grouped off Row (Task 3 review ruling) to keep Row under PMD's TooManyFields threshold:
  // contactEmail/contactPhone/risk/loadCount/attention all describe the carrier on the quote.
  public class CarrierDetail {
    @AuraEnabled
    public String contactEmail;
    @AuraEnabled
    public String contactPhone;
    @AuraEnabled
    public String risk;
    @AuraEnabled
    public Decimal loadCount;
    @AuraEnabled
    public String attention;
  }

  public class Stats {
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Integer countNonZero = 0;
    @AuraEnabled
    public Decimal min;
    @AuraEnabled
    public Decimal max;
    @AuraEnabled
    public Decimal avg;
    @AuraEnabled
    public Decimal median;
  }

  @AuraEnabled
  public List<Row> rows = new List<Row>();
  @AuraEnabled
  public Map<String, Stats> statsByCurrency = new Map<String, Stats>();
  @AuraEnabled
  public Boolean truncated = false;
  // Integer, not Long: LWC receives a Long as a string once it exceeds 2^53, and a query time in
  // milliseconds never comes close to Integer's range.
  @AuraEnabled
  public Integer elapsedMs = 0;
  @AuraEnabled
  public Integer dedupedCount = 0;
}
