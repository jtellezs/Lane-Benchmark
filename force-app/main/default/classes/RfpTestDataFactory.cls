/**
 * Test builders for the phase 3 RFP objects. Places mirror LaneSearchServiceTest.place();
 * projects/lanes/bids carry the minimum the services and Lane Benchmark need. The restricted users,
 * account shares and hidden carrier at the end serve the phase 6 sharing tests (RfpSecurityTest,
 * RfpBulkControllerTest).
 */
@IsTest
public class RfpTestDataFactory {
  public static Pricing_Place__c createPlace(
    String city,
    String prov,
    String country,
    Decimal lat,
    Decimal lng,
    String prefix
  ) {
    Pricing_Place__c p = new Pricing_Place__c(
      Name = city + ', ' + prov,
      Key__c = PlaceNormalizer.key(city, prov, country),
      City__c = city,
      Province__c = prov,
      Country__c = country,
      Geolocation__Latitude__s = lat,
      Geolocation__Longitude__s = lng,
      Postal_Prefix__c = prefix,
      Active__c = true,
      Source__c = 'Locations'
    );
    insert p;
    return p;
  }

  public static RFP_Project__c createProject(Account customer) {
    RFP_Project__c p = new RFP_Project__c(
      Name = 'Test RFP',
      Customer__c = customer.Id,
      Status__c = 'Draft',
      Default_Margin__c = 15,
      CurrencyIsoCode = 'CAD'
    );
    insert p;
    return p;
  }

  public static RFP_Lane__c createLane(
    RFP_Project__c project,
    Pricing_Place__c origin,
    Pricing_Place__c destination
  ) {
    RFP_Lane__c lane = new RFP_Lane__c(
      RFP_Project__c = project.Id,
      Row_Number__c = 1,
      Origin_City__c = origin.City__c,
      Origin_Province__c = origin.Province__c,
      Origin_Country__c = origin.Country__c,
      Origin_Postal__c = origin.Postal_Prefix__c,
      Origin_Place__c = origin.Id,
      Origin_Resolved__c = true,
      Destination_City__c = destination.City__c,
      Destination_Province__c = destination.Province__c,
      Destination_Country__c = destination.Country__c,
      Destination_Postal__c = destination.Postal_Prefix__c,
      Destination_Place__c = destination.Id,
      Destination_Resolved__c = true,
      Mode__c = 'Truckload',
      Equipment_Category__c = 'Van',
      Equipment_Type__c = 'Dry Van 53\'',
      Margin__c = 15,
      Hist_Status__c = 'Pending',
      CurrencyIsoCode = 'CAD'
    );
    insert lane;
    return lane;
  }

  public static Benchmark_Rate__c buildBid(RFP_Lane__c lane, Decimal rate) {
    return new Benchmark_Rate__c(
      RFP_Lane__c = lane.Id,
      Carrier_Name__c = 'Bid Carrier',
      Contact_Name__c = 'Bid Contact',
      Contact_Email__c = 'bid@example.invalid',
      Rate__c = rate,
      CurrencyIsoCode = 'CAD',
      Valid_From__c = Date.today(),
      Expires_On__c = Date.today().addDays(30)
    );
  }

  // ---- restricted users, account shares and a hidden carrier, for the phase 6 sharing tests ----

  /** Creates a user holding only the named permission set. Returns null when the org has no usable profile. */
  public static User restrictedUser(String permSetName) {
    return restrictedUser(new List<String>{ permSetName });
  }

  /** Creates a user holding only the named permission sets. Returns null when the org has no usable profile. */
  public static User restrictedUser(List<String> permSetNames) {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'Minimum Access - Salesforce')
      ORDER BY Name DESC
      LIMIT 1
    ];
    if (profiles.isEmpty()) {
      return null;
    }
    User u = new User(
      ProfileId = profiles[0].Id,
      Username = 'rfp.' +
        System.currentTimeMillis() +
        '.' +
        permSetNames.size() +
        '@example.invalid',
      Email = 'rfp@example.invalid',
      LastName = 'Rfp',
      Alias = 'rfp',
      TimeZoneSidKey = 'America/Toronto',
      LocaleSidKey = 'en_CA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permSetNames
    ];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      List<PermissionSetAssignment> psa = new List<PermissionSetAssignment>();
      for (PermissionSet ps : sets) {
        psa.add(
          new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
          )
        );
      }
      insert psa;
    }
    return u;
  }

  /**
   * Account is Private in this org and an RFP follows its account (phase 6): a manual share
   * on the customer is what lets a restricted user see, and with Read alone also work, the RFP.
   */
  public static void shareAccount(Account customer, User u, String level) {
    insert new AccountShare(
      AccountId = customer.Id,
      UserOrGroupId = u.Id,
      AccountAccessLevel = level,
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None',
      RowCause = 'Manual'
    );
  }

  /**
   * A carrier account the admin creates and a restricted user cannot read. In this org an ordinary
   * carrier is readable by every internal user: the flow Ownership_update_Carrier_and hands an
   * account whose TMS type contains "Carrier" and that is not blacklisted to the Public Accounts
   * user, whose owner-based rules share Edit with All Internal Users, and the criteria rule
   * Carrier_Sharing_Setting shares a carrier whose Company_Org__c is 'Trans-Pro Logistics Inc' (the
   * picklist default). So the graph's vendor will not do: this carrier is blacklisted (the flow
   * leaves its owner alone) and belongs to 'Trans-Pro Logistica' (no rule shares it). Where a
   * restricted user can read it anyway, the org configuration differs, not the code, and the tests
   * built on it skip (hiddenFrom, R68).
   */
  public static Account hiddenCarrier() {
    Account carrier = new Account(
      Name = 'Hidden Carrier',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Carrier')
        .getRecordTypeId(),
      rtms__TMS_Type__c = 'Carrier (Ground)',
      Company_Org__c = 'Trans-Pro Logistica',
      Black_List__c = true,
      CurrencyIsoCode = 'CAD'
    );
    insert carrier;
    return carrier;
  }

  /** The carrier's sharing inputs, for a skip message: who owns it and what the rules read. */
  public static String sharingInputs(Id accountId) {
    return String.valueOf(
      [
        SELECT OwnerId, Company_Org__c, rtms__TMS_Type__c, Black_List__c
        FROM Account
        WHERE Id = :accountId
      ]
    );
  }

  /**
   * Whether u cannot read the account in user mode: the precondition of every test built on
   * hiddenCarrier(). It holds in PostProduc; an org whose carrier flow or Account sharing rules
   * share that carrier makes those tests skip, like the no-usable-profile branch, instead of
   * failing a deploy on sharing configuration (R68).
   */
  public static Boolean hiddenFrom(User u, Id accountId) {
    Integer seen;
    System.runAs(u) {
      seen = [SELECT COUNT() FROM Account WHERE Id = :accountId WITH USER_MODE];
    }
    return seen == 0;
  }

  /** A second customer account, which the admin owns and no restricted user can read until shared. */
  public static Account secondCustomer() {
    Account second = new Account(
      Name = 'Second Customer',
      RecordTypeId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Customer')
        .getRecordTypeId(),
      rtms__TMS_Type__c = 'Customer',
      Industry = 'Other',
      BillingStreet = '2 Test St',
      BillingCity = 'Montreal',
      BillingState = 'Quebec',
      BillingPostalCode = 'H1A 1A1',
      BillingCountry = 'Canada',
      CurrencyIsoCode = 'CAD'
    );
    insert second;
    return second;
  }
}
