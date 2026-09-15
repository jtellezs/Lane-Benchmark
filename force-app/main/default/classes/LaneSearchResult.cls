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
    // Phase 7: the quote's load (its Id and billed miles), initialized like carrier so bid rows
    // carry load.miles = null. loadId moved in here to keep Row at PMD's TooManyFields cap of 20.
    @AuraEnabled
    public LoadDetail load = new LoadDetail();
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
    // Phase 3: set only on rows that come from Benchmark_Rate__c (bids); null for loads. No
    // initializer, unlike carrier above, so the LWC can treat bid != null as "this is a bid".
    @AuraEnabled
    public BidDetail bid;
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

  // Phase 3: set only on rows that come from Benchmark_Rate__c (bids). Grouped, like CarrierDetail,
  // so Row stays under PMD's TooManyFields threshold; the LWC treats bid != null as "this is a bid".
  public class BidDetail {
    @AuraEnabled
    public Id rateId;
    @AuraEnabled
    public Date expiresOn;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal transitDays;
    @AuraEnabled
    public Decimal fuelSurcharge;
    @AuraEnabled
    public Boolean fscIncluded;
  }

  // Phase 7: the quote's load. Grouped, like CarrierDetail, so Row stays at PMD's TooManyFields
  // cap; bid rows keep both fields null.
  public class LoadDetail {
    @AuraEnabled
    public Id loadId;
    // rtms__Load__c.rtms__Distance_Miles__c: Revenova's billed miles (PC*Miler); null when blank.
    @AuraEnabled
    public Decimal miles;
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
    // Phase 7: median of carrierTotal / load.miles over this currency's rows with both above zero,
    // scale 2; null when no row has both (bids have no miles).
    @AuraEnabled
    public Decimal ratePerMileMedian;
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
  // Phase 7: TripMilesService.medianMiles over rows, one value per load with miles above zero,
  // scale 1; null when none.
  @AuraEnabled
  public Decimal medianMiles;
}
