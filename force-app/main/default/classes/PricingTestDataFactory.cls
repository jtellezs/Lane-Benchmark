/**
 * Builds the minimum valid Revenova graph the Pricing Department tests need: customer and vendor
 * Accounts, geocoded location Accounts, quote Contact, transportation profile, mode, equipment
 * type, carrier service, loads with stops, and carrier quotes. Tests create their own data through
 * this class instead of relying on org records. If a managed or custom trigger rejects an insert,
 * fix it HERE, not in a test.
 *
 * Two PostProduc constraints shape the interface:
 * - Load automation (LoadTrigger plus the "UAT - Load Updated" flow) is not bulkified, so a test
 *   that creates two or more loads wraps the later createLoad() calls in Test.startTest() to get a
 *   fresh governor-limit set; otherwise the 100 synchronous SOQL query limit is exceeded.
 * - Hazmat, customer and mode are set at insert through the overloads below rather than by a
 *   post-insert update: Mode_For_Sharing__c is re-derived from the rtms__Mode__c lookup on every
 *   save, so writing it directly is silently overwritten, and the extra Load DML would trip the
 *   same limit.
 * - Load lane keys (rtms__City_Lane__c/State_Lane__c/Zip3_Lane__c) survive stop insertion
 *   unchanged, but the managed rtms__StopUpsert trigger blanks a Stop's own
 *   rtms__City__c/rtms__Postal_Code__c/geolocation fields on every save WHEN that stop has
 *   rtms__Location2__c - see buildStop()'s doc comment for the full discovery. Read
 *   city/postal/geolocation off rtms__Location2__r (the account) for such stops, never off the
 *   stop directly. A stop with no rtms__Location2__c (see createLoadWithAdHocOrigin()) is not
 *   touched by that trigger and keeps its own city/postal/geolocation fields as written.
 *
 * The graph is verified end to end in PostProduc: deploy request 0AfbZ00000CnJYrSAN,
 * PricingDepartmentControllerTest 12/12 passing.
 */
@IsTest
public class PricingTestDataFactory {
  public static final String DIVISION = 'Trans-Pro Logistics Inc';

  public class Graph {
    public Account customer;
    public Account vendor;
    public Account originLocation;
    public Account destinationLocation;
    public Contact quoteContact;
    public rtms__TransportationProfile__c profile;
    public rtms__Mode__c mode;
    public rtms__EquipmentType__c equipment;
    public rtms__CarrierService__c carrierService;
  }

  private static Id recordTypeId(String sobjectName, String developerName) {
    return Schema.getGlobalDescribe()
      .get(sobjectName)
      .getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  public static Graph createGraph() {
    Graph g = new Graph();

    g.customer = new Account(
      Name = 'Test Customer',
      RecordTypeId = recordTypeId('Account', 'Customer'),
      rtms__TMS_Type__c = 'Customer',
      Industry = 'Other',
      BillingStreet = '1 Test St',
      BillingCity = 'Montreal',
      BillingState = 'Quebec',
      BillingPostalCode = 'H1A 1A1',
      BillingCountry = 'Canada',
      CurrencyIsoCode = 'CAD'
    );
    g.vendor = new Account(
      Name = 'Test Carrier',
      RecordTypeId = recordTypeId('Account', 'Carrier'),
      rtms__TMS_Type__c = 'Carrier (Ground)',
      CurrencyIsoCode = 'CAD'
    );
    g.originLocation = location(
      'Origin Co',
      'Montreal',
      'Quebec',
      'Canada',
      45.5019,
      -73.5674
    );
    g.destinationLocation = location(
      'Destination Co',
      'Toronto',
      'Ontario',
      'Canada',
      43.6532,
      -79.3832
    );
    insert new List<Account>{
      g.customer,
      g.vendor,
      g.originLocation,
      g.destinationLocation
    };

    g.quoteContact = new Contact(
      FirstName = 'Quote',
      LastName = 'Contact',
      AccountId = g.vendor.Id,
      Email = 'quote.contact@example.invalid',
      Phone = '514-555-0100'
    );
    insert g.quoteContact;

    g.profile = new rtms__TransportationProfile__c(
      Name = 'Test Carrier Profile',
      RecordTypeId = recordTypeId('rtms__TransportationProfile__c', 'Carrier'),
      rtms__Company_Risk__c = 'Acceptable',
      rtms__Carrier_Remit_To__c = g.vendor.Id
    );
    insert g.profile;

    g.mode = new rtms__Mode__c(
      Name = 'Truckload',
      rtms__Order__c = 1,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert g.mode;

    g.equipment = new rtms__EquipmentType__c(
      Name = 'Dry Van 53\'',
      rtms__Max_Weight__c = 45000,
      rtms__Mode__c = 'Truckload',
      rtms__Category__c = 'Van',
      rtms__Enabled__c = true
    );
    insert g.equipment;

    g.carrierService = new rtms__CarrierService__c(
      Name = 'Test Carrier Service',
      rtms__Carrier__c = g.vendor.Id,
      rtms__Mode__c = g.mode.Id,
      rtms__Transportation_Profile__c = g.profile.Id,
      rtms__Quote_Contact__c = g.quoteContact.Id,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert g.carrierService;
    return g;
  }

  public static Account createLocation(
    String name,
    String city,
    String province,
    String country,
    String postalCode,
    Decimal lat,
    Decimal lng
  ) {
    Account a = new Account(
      Name = name,
      RecordTypeId = recordTypeId('Account', 'Shipper_Consignee'),
      rtms__TMS_Type__c = 'Shipper/Consignee',
      ShippingStreet = '1 Dock Rd',
      ShippingCity = city,
      ShippingState = province,
      ShippingPostalCode = postalCode,
      ShippingCountry = country,
      ShippingLatitude = lat,
      ShippingLongitude = lng,
      CurrencyIsoCode = 'CAD'
    );
    insert a;
    return a;
  }

  public static rtms__EquipmentType__c createEquipment(
    String name,
    String category
  ) {
    rtms__EquipmentType__c e = new rtms__EquipmentType__c(
      Name = name,
      rtms__Max_Weight__c = 45000,
      rtms__Mode__c = 'Truckload',
      rtms__Category__c = category,
      rtms__Enabled__c = true
    );
    insert e;
    return e;
  }

  public static rtms__Mode__c createMode(String name) {
    rtms__Mode__c m = new rtms__Mode__c(
      Name = name,
      rtms__Order__c = 2,
      rtms__Minimum_Weight__c = 0,
      rtms__Maximum_Weight__c = 100000
    );
    insert m;
    return m;
  }

  private static Account location(
    String name,
    String city,
    String state,
    String country,
    Decimal lat,
    Decimal lng
  ) {
    return new Account(
      Name = name,
      RecordTypeId = recordTypeId('Account', 'Shipper_Consignee'),
      rtms__TMS_Type__c = 'Shipper/Consignee',
      ShippingStreet = '1 Dock Rd',
      ShippingCity = city,
      ShippingState = state,
      ShippingPostalCode = 'A1A 1A1',
      ShippingCountry = country,
      ShippingLatitude = lat,
      ShippingLongitude = lng,
      CurrencyIsoCode = 'CAD'
    );
  }

  /** Inserts a load with a pickup at the origin location and a delivery at the destination location. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination
  ) {
    return createLoad(g, origin, destination, false);
  }

  /** Sets rtms__Hazardous_Materials__c at insert; the 3-argument overload delegates here with false. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Boolean hazmat
  ) {
    return createLoad(g, origin, destination, hazmat, g.customer, g.mode);
  }

  /** Sets a customer other than the graph's at insert, for the market-test filter scenario. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Account customer
  ) {
    return createLoad(g, origin, destination, false, customer, g.mode);
  }

  /** Points the load at a different rtms__Mode__c record, the only way a mode change sticks. */
  public static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    rtms__Mode__c mode
  ) {
    return createLoad(g, origin, destination, false, g.customer, mode);
  }

  /**
   * Returns an uninserted Load with the fields every load in this factory shares (customer, mode,
   * equipment, weight, division, currency, hazmat). Shared by createLoad() and
   * createLoadWithAdHocOrigin() so that field list exists once.
   */
  private static rtms__Load__c newLoad(
    Graph g,
    Account customer,
    rtms__Mode__c mode,
    Boolean hazmat
  ) {
    return new rtms__Load__c(
      Name = 'Test Load',
      rtms__Customer__c = customer.Id,
      rtms__Mode__c = mode.Id,
      rtms__Equipment_Type__c = g.equipment.Id,
      rtms__Total_Weight__c = 1000,
      Mode_For_Sharing__c = mode.Name,
      TPRO_Division_Name__c = DIVISION,
      CurrencyIsoCode = 'CAD',
      rtms__Hazardous_Materials__c = hazmat
    );
  }

  private static rtms__Load__c createLoad(
    Graph g,
    Account origin,
    Account destination,
    Boolean hazmat,
    Account customer,
    rtms__Mode__c mode
  ) {
    rtms__Load__c load = newLoad(g, customer, mode, hazmat);
    applyLaneKeys(load, origin, destination);
    String expectedCityLane = load.rtms__City_Lane__c;
    String expectedStateLane = load.rtms__State_Lane__c;
    String expectedZip3Lane = load.rtms__Zip3_Lane__c;
    insert load;

    rtms__Stop__c pickup = buildStop(load, 1, origin);
    rtms__Stop__c delivery = buildStop(load, 2, destination);
    insert new List<rtms__Stop__c>{ pickup, delivery };

    return backfillFirstLastStopAndLaneKeys(
      load,
      pickup,
      delivery,
      expectedCityLane,
      expectedStateLane,
      expectedZip3Lane
    );
  }

  /**
   * Inserts a load like createLoad(), but the origin stop is ad hoc: no rtms__Location2__c, just
   * city/postal/geolocation written directly onto the stop. Models a lane whose origin was
   * captured by hand rather than tied to an Account, so the RADIUS search's stop-geolocation
   * fallback (Task 6) has an account-less stop to match against. Revenova's managed
   * rtms__StopUpsert trigger only blanks a stop's own City/Postal Code/geolocation fields when the
   * stop HAS rtms__Location2__c (see buildStop()'s doc comment) - this stop deliberately has none,
   * so those fields should survive.
   */
  public static rtms__Load__c createLoadWithAdHocOrigin(
    Graph g,
    String city,
    String province,
    String postal,
    Decimal lat,
    Decimal lng,
    Account destination
  ) {
    rtms__Load__c load = newLoad(g, g.customer, g.mode, false);
    String oProv = PlaceNormalizer.provinceCode(province);
    String dProv = PlaceNormalizer.provinceCode(destination.ShippingState);
    load.rtms__City_Lane__c =
      PlaceNormalizer.cityLaneSide(city, oProv) +
      ':' +
      PlaceNormalizer.cityLaneSide(destination.ShippingCity, dProv);
    load.rtms__State_Lane__c = oProv + ':' + dProv;
    load.rtms__Zip3_Lane__c =
      first3(postal) +
      ':' +
      first3(destination.ShippingPostalCode);
    String expectedCityLane = load.rtms__City_Lane__c;
    String expectedStateLane = load.rtms__State_Lane__c;
    String expectedZip3Lane = load.rtms__Zip3_Lane__c;
    insert load;

    rtms__Stop__c pickup = new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = 1,
      rtms__City__c = city,
      rtms__Postal_Code__c = postal,
      rtms__Geolocation__Latitude__s = lat,
      rtms__Geolocation__Longitude__s = lng
    );
    rtms__Stop__c delivery = buildStop(load, 2, destination);
    insert new List<rtms__Stop__c>{ pickup, delivery };

    return backfillFirstLastStopAndLaneKeys(
      load,
      pickup,
      delivery,
      expectedCityLane,
      expectedStateLane,
      expectedZip3Lane
    );
  }

  /**
   * Re-queries the Load after its stops are inserted and fixes up rtms__First_Stop__c/
   * rtms__Last_Stop__c and the three lane keys if Revenova's automation touched them. Shared by
   * createLoad() and createLoadWithAdHocOrigin() so the backfill logic exists once.
   */
  private static rtms__Load__c backfillFirstLastStopAndLaneKeys(
    rtms__Load__c load,
    rtms__Stop__c pickup,
    rtms__Stop__c delivery,
    String expectedCityLane,
    String expectedStateLane,
    String expectedZip3Lane
  ) {
    load = [
      SELECT
        Id,
        rtms__First_Stop__c,
        rtms__Last_Stop__c,
        rtms__City_Lane__c,
        rtms__State_Lane__c,
        rtms__Zip3_Lane__c
      FROM rtms__Load__c
      WHERE Id = :load.Id
    ];
    Boolean needsUpdate = false;
    if (load.rtms__First_Stop__c == null || load.rtms__Last_Stop__c == null) {
      load.rtms__First_Stop__c = pickup.Id;
      load.rtms__Last_Stop__c = delivery.Id;
      needsUpdate = true;
    }
    // Discovery (2026-09-09, PostProduc sandbox): inserting the two stops does not disturb the
    // Load's own lane keys - rtms__City_Lane__c/State_Lane__c/Zip3_Lane__c still hold exactly what
    // was written before insert. This re-check is kept anyway so the factory stays correct if that
    // ever changes.
    if (
      load.rtms__City_Lane__c != expectedCityLane ||
      load.rtms__State_Lane__c != expectedStateLane ||
      load.rtms__Zip3_Lane__c != expectedZip3Lane
    ) {
      load.rtms__City_Lane__c = expectedCityLane;
      load.rtms__State_Lane__c = expectedStateLane;
      load.rtms__Zip3_Lane__c = expectedZip3Lane;
      needsUpdate = true;
    }
    if (needsUpdate) {
      update load;
    }
    return load;
  }

  /** Returns an uninserted carrier quote on the graph's carrier service. Tests tweak fields, then insert. */
  public static rtms__CarrierQuote__c buildQuote(
    Graph g,
    rtms__Load__c load,
    Decimal cadTotal
  ) {
    return new rtms__CarrierQuote__c(
      rtms__Load__c = load.Id,
      rtms__Carrier_Service__c = g.carrierService.Id,
      rtms__Vendor__c = g.vendor.Id,
      rtms__Quote_Contact__c = g.quoteContact.Id,
      rtms__Carrier_Total__c = cadTotal,
      CurrencyIsoCode = 'CAD'
    );
  }

  /** Same as buildQuote(Graph, Load, Decimal) but in the given currency (e.g. 'USD'); still uninserted. */
  public static rtms__CarrierQuote__c buildQuote(
    Graph g,
    rtms__Load__c load,
    Decimal total,
    String currencyIsoCode
  ) {
    rtms__CarrierQuote__c q = buildQuote(g, load, total);
    q.CurrencyIsoCode = currencyIsoCode;
    return q;
  }

  private static String first3(String postal) {
    return postal == null ? '' : postal.replace(' ', '').left(3).toUpperCase();
  }

  /** Lane keys the way Revenova writes them: "City, ST:City, ST", "ST:ST", "H7P:L1J". */
  private static void applyLaneKeys(
    rtms__Load__c load,
    Account origin,
    Account destination
  ) {
    String oProv = PlaceNormalizer.provinceCode(origin.ShippingState);
    String dProv = PlaceNormalizer.provinceCode(destination.ShippingState);
    load.rtms__City_Lane__c =
      PlaceNormalizer.cityLaneSide(origin.ShippingCity, oProv) +
      ':' +
      PlaceNormalizer.cityLaneSide(destination.ShippingCity, dProv);
    load.rtms__State_Lane__c = oProv + ':' + dProv;
    load.rtms__Zip3_Lane__c =
      first3(origin.ShippingPostalCode) +
      ':' +
      first3(destination.ShippingPostalCode);
  }

  /**
   * Builds an uninserted stop. rtms__City__c, rtms__Postal_Code__c and both geolocation fields are
   * deliberately NOT set here (deviation from the original plan - see Discovery below).
   * rtms__State_Province__c is also left unset: it is a picklist whose valid values are unknown in
   * this org. rtms__Location2__c is enough: it points at the account createLocation()/location()
   * built, and that account still carries city, postal code and coordinates - the Load's lane keys
   * (applyLaneKeys) are what the pricing service reads, not these stop fields.
   *
   * Discovery (2026-09-09, PostProduc sandbox): PostProduc has an org-local, non-namespaced
   * ApexTrigger "StopTrigger" (before insert/update) that only touches USD_Conversion_Rate__c and
   * is not the cause. The actual cause is the managed trigger "rtms__StopUpsert" (before
   * insert/update, body hidden - namespaced/managed code can't be read from this org): it blanks
   * rtms__City__c, rtms__Postal_Code__c, rtms__Geolocation__Latitude__s/Longitude__s on every Stop
   * save that has rtms__Location2__c set, regardless of what is assigned. Confirmed with anonymous
   * Apex directly against rtms__Stop__c outside any test context and outside this factory, so it is
   * not a test-only or factory-only artifact; re-updating the stop after the first null-out gets
   * nulled again the same way. Setting additional candidate source fields on the Account
   * (rtms__Posting_City__c, Geoloc__Latitude__s/Longitude__s) made no difference. The org's own
   * formula fields on Stop (City_Stop__c = rtms__Location2__r.ShippingCity, State_Stop__c =
   * rtms__Location2__r.ShippingState) DO resolve correctly in the same test, proving
   * rtms__Location2__c and the account's Shipping* fields are intact - only the four raw Stop fields
   * are wiped. Confirmed (Task 6) that a stop with NO rtms__Location2__c is untouched by this
   * trigger and keeps those same four fields as written - see createLoadWithAdHocOrigin(). Per the
   * task's fallback for this exact situation, those fields are dropped from this
   * method rather than written and silently lost.
   */
  private static rtms__Stop__c buildStop(
    rtms__Load__c load,
    Integer stopNumber,
    Account location
  ) {
    return new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = stopNumber,
      rtms__Location2__c = location.Id
    );
  }
}
