/**
 * What Carriers to ask returns (phase 8, spec section 3): the carriers that know a lane, by name,
 * with the lane's loads each moved and quoted, the day it was last seen there, where it was seen
 * (a carrier quote, a split leg), its blacklist flag and whether the user may open its account;
 * the stage that found them (the same lane, the state or province lane, or none); the state lane's
 * label for the stage 2 wording; and whether a cap or the query-row check cut the list. Names only:
 * no field here holds an amount (R106), and CarrierLeadServiceTest fails when a serialized key
 * appears that the spec does not list.
 */
public class CarrierLeadResult {
  public static final String SAME_LANE = 'Same lane';
  public static final String STATE_LANE = 'State lane';
  public static final String NONE = 'None';
  public static final String SOURCE_QUOTE = 'Quote';
  public static final String SOURCE_SPLIT_LEG = 'Split leg';

  /** One carrier. loadsMoved counts its accepted quote loads plus its split leg loads (R82). */
  public class Lead {
    @AuraEnabled
    public Id carrierId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer loadsMoved = 0;
    @AuraEnabled
    public Integer loadsQuoted = 0;
    @AuraEnabled
    public Date lastSeen;
    @AuraEnabled
    public List<String> sources = new List<String>();
    @AuraEnabled
    public Boolean blacklisted = false;
    @AuraEnabled
    public Boolean canOpen = false;
  }

  @AuraEnabled
  public List<Lead> leads = new List<Lead>();
  @AuraEnabled
  public String stage = NONE;
  @AuraEnabled
  public String stateLaneLabel;
  @AuraEnabled
  public Boolean truncated = false;
}
