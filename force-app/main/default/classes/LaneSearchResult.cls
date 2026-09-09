/** Typed output of LaneSearchService.search(). Plain data, no logic. */
public class LaneSearchResult {
  public class Row {
    public Id quoteId;
    public String quoteName;
    public Id loadId;
    public String origin;
    public String destination;
    public String mode;
    public String equipment;
    public String equipmentCategory;
    public String carrierName;
    public String contactName;
    public String currencyIsoCode;
    public Decimal carrierTotal;
    public Date quoteDate;
    public Boolean hazmat;
    public Boolean accepted;
    public String loadStatus;
    public String opsComments;
  }

  public class Stats {
    public Integer count = 0;
    public Integer countNonZero = 0;
    public Decimal min;
    public Decimal max;
    public Decimal avg;
    public Decimal median;
  }

  public List<Row> rows = new List<Row>();
  public Map<String, Stats> statsByCurrency = new Map<String, Stats>();
  public Boolean truncated = false;
  public Long elapsedMs = 0;
  public Integer dedupedCount = 0;
}
