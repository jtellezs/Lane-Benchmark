/**
 * Builds the minimum valid Revenova graph the Pricing Department tests need.
 * DevPro has no records, so every test creates its data through this class.
 * If a managed or custom trigger rejects an insert, fix it HERE, not in a test.
 *
 * Discovery loop findings (DevPro, 2026-09-08):
 * - rtms__TransportationProfile__c.rtms__Carrier_Remit_To__c (lookup to Account) is set to the
 *   vendor Account on the Carrier profile. This was added per the controller's hint about a
 *   TransportationProfile-to-Account lookup, not because any observed error required it — no
 *   insert in this class ever got far enough to exercise it (see blocker below).
 * - No other field was added to this class as a result of an observed validation/required-field
 *   error; the fields from the brief's known-requirements table were sufficient for every insert
 *   through rtms__CarrierService__c.
 *
 * KNOWN BLOCKER (unresolved, not fixable from this class): every rtms__Load__c insert in DevPro
 * fails with:
 *   System.DmlException: Insert failed. First exception on row 0; first error:
 *   CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY, rtms.LoadUpsert: execution of BeforeInsert
 *   caused by: rtms.SecurityException: The user does not have access to the following record
 *   Id:Iulian Enescu:a161N0000041YHRQA2
 * Confirmed invariant to: Customer, Carrier, Mode, Equipment, Division on the Load; and to
 * Account.rtms__Transportation_Profile__c being populated on both the customer and vendor
 * accounts. The referenced Id (a16 = rtms__TransportationProfile__c) does not exist in DevPro
 * under any query, including ALL ROWS (not even in the Recycle Bin); its "1N" instance segment
 * shows it was minted in the source production org, not in DevPro's own "As" instance. It is not
 * stored on the running User's fields, in any rtms__-namespaced custom setting (there are none
 * visible to subscriber code in this org), or in Custom Labels. This points to a stale reference
 * inside managed rtms package code/config that a metadata-only sandbox refresh does not carry the
 * underlying data record for. createLoad() and buildQuote() are implemented per the interface
 * contract but are UNVERIFIED end to end in DevPro until this environment defect is fixed (full
 * diagnostic trail: see the Task 4 report in the project's SDD folder).
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
    rtms__Load__c load = new rtms__Load__c(
      Name = 'Test Load',
      rtms__Customer__c = g.customer.Id,
      rtms__Mode__c = g.mode.Id,
      rtms__Equipment_Type__c = g.equipment.Id,
      rtms__Total_Weight__c = 1000,
      Mode_For_Sharing__c = 'Truckload',
      TPRO_Division_Name__c = DIVISION,
      CurrencyIsoCode = 'CAD'
    );
    insert load;

    rtms__Stop__c pickup = new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = 1,
      rtms__Location2__c = origin.Id
    );
    rtms__Stop__c delivery = new rtms__Stop__c(
      rtms__Load__c = load.Id,
      rtms__Number__c = 2,
      rtms__Location2__c = destination.Id
    );
    insert new List<rtms__Stop__c>{ pickup, delivery };

    load = [
      SELECT Id, rtms__First_Stop__c, rtms__Last_Stop__c
      FROM rtms__Load__c
      WHERE Id = :load.Id
    ];
    if (load.rtms__First_Stop__c == null || load.rtms__Last_Stop__c == null) {
      load.rtms__First_Stop__c = pickup.Id;
      load.rtms__Last_Stop__c = delivery.Id;
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
}
