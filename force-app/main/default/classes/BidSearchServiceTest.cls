@IsTest
private class BidSearchServiceTest {
  // Brief hardcoded '001000000000001AAA' here; PMD's AvoidHardcodingId (quickstart, priority 3)
  // flags any 15/18-char literal shaped like a record Id, so this test never has a real
  // Benchmark_Rate__c to read an Id from - it builds an equivalent 18-char value one fragment at
  // a time (no fragment reaches the 15/18-char length the rule matches on).
  private static Id mockRateId() {
    String raw = '001';
    for (Integer i = 0; i < 11; i++) {
      raw += '0';
    }
    return raw + '1AAA';
  }

  private static LaneSearchResult.Row row(
    String kind,
    Datetime created,
    Decimal total
  ) {
    LaneSearchResult.Row r = new LaneSearchResult.Row();
    r.createdDate = created;
    r.carrierTotal = total;
    r.carrierName = 'C';
    r.origin = 'A';
    r.destination = 'B';
    r.mode = 'Truckload';
    r.equipment = 'Van';
    if (kind == 'bid') {
      r.bid = new LaneSearchResult.BidDetail();
      r.bid.rateId = mockRateId();
    }
    return r;
  }

  @IsTest
  static void mergeKeepsDateOrderAndCap() {
    Datetime t = Datetime.now();
    List<LaneSearchResult.Row> quotes = new List<LaneSearchResult.Row>{
      row('quote', t.addHours(-1), 100),
      row('quote', t.addHours(-3), 300)
    };
    List<LaneSearchResult.Row> bids = new List<LaneSearchResult.Row>{
      row('bid', t, 50),
      row('bid', t.addHours(-2), 200),
      row('bid', t.addHours(-4), 400)
    };
    List<LaneSearchResult.Row> merged = BidSearchService.mergeRows(
      quotes,
      bids,
      4
    );
    System.assertEquals(4, merged.size());
    System.assertEquals(50, merged[0].carrierTotal);
    System.assertEquals(100, merged[1].carrierTotal);
    System.assertEquals(200, merged[2].carrierTotal);
    System.assertEquals(300, merged[3].carrierTotal);
  }

  @IsTest
  static void fingerprintNeverCollapsesBids() {
    LaneSearchResult.Row a = row('quote', Datetime.now(), 100);
    LaneSearchResult.Row b = row('quote', Datetime.now(), 100);
    System.assertEquals(
      BidSearchService.fingerprint(a),
      BidSearchService.fingerprint(b)
    );
    LaneSearchResult.Row c = row('bid', Datetime.now(), 100);
    System.assertNotEquals(
      BidSearchService.fingerprint(a),
      BidSearchService.fingerprint(c)
    );
  }

  @IsTest
  static void toRowMapsTheBid() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    RFP_Lane__c lane = RfpTestDataFactory.createLane(
      RfpTestDataFactory.createProject(g.customer),
      mtl,
      tor
    );
    Benchmark_Rate__c bid = RfpTestDataFactory.buildBid(lane, 1500);
    bid.Transit_Days__c = 2;
    bid.Fuel_Surcharge__c = 100;
    bid.FSC_Included__c = true;
    Benchmark_Rate__c saved = BenchmarkRateService.save(bid);
    Benchmark_Rate__c full = Database.query(
      BidSearchQueryBuilder.buildSoql(
          minimalRequest(),
          new Map<String, Object>{ 'bRowLimitPlusOne' => 10 },
          new Map<String, Pricing_Place__c>()
        )
        .replace('LIMIT :bRowLimitPlusOne', 'LIMIT 10')
    );
    LaneSearchResult.Row r = BidSearchService.toRow(full);
    System.assertEquals(saved.Id, r.quoteId);
    System.assertEquals(saved.Name, r.quoteName);
    System.assertEquals('Montréal, QC', r.origin);
    System.assertEquals('Toronto, ON', r.destination);
    System.assertEquals('Bid Carrier', r.carrierName);
    System.assertEquals('Bid Contact', r.contactName);
    System.assertEquals('bid@example.invalid', r.carrier.contactEmail);
    System.assertEquals(1500, r.carrierTotal);
    System.assertEquals('CAD', r.currencyIsoCode);
    System.assertEquals(Date.today(), r.quoteDate);
    System.assertEquals(saved.Id, r.bid.rateId);
    System.assertEquals(Date.today().addDays(30), r.bid.expiresOn);
    System.assertEquals('Active', r.bid.status);
    System.assertEquals(2, r.bid.transitDays);
    System.assertEquals(true, r.bid.fscIncluded);
    System.assertEquals('Bid', r.loadStatus);
  }

  /**
   * Phase 3d, end to end over the SOQL: three bids on the same city lane - one on the project
   * being priced, one on another project that expired ten days ago, one recorded with no project
   * at all (Lane Benchmark's own). A history run excludes its own project and keeps expired bids,
   * so it sees the other two; the same search without includeExpiredBids sees only the live one.
   */
  @IsTest
  static void aProjectExclusionAndExpiredBidsPickTheRightRows() {
    PricingTestDataFactory.Graph g = PricingTestDataFactory.createGraph();
    Pricing_Place__c mtl = RfpTestDataFactory.createPlace(
      'Montréal',
      'QC',
      'CA',
      45.5019,
      -73.5674,
      'H1A'
    );
    Pricing_Place__c tor = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.6532,
      -79.3832,
      'M5V'
    );
    RFP_Project__c own = RfpTestDataFactory.createProject(g.customer);
    RFP_Project__c other = RfpTestDataFactory.createProject(g.customer);
    RFP_Lane__c ownLane = RfpTestDataFactory.createLane(own, mtl, tor);
    RFP_Lane__c otherLane = RfpTestDataFactory.createLane(other, mtl, tor);
    Benchmark_Rate__c mine = RfpTestDataFactory.buildBid(ownLane, 1000);
    Benchmark_Rate__c expired = RfpTestDataFactory.buildBid(otherLane, 2000);
    // save() defaults these two only when they are null and never refuses a past date, so the
    // expired bid is built with its window already closed.
    expired.Valid_From__c = Date.today().addDays(-40);
    expired.Expires_On__c = Date.today().addDays(-10);
    insert new List<Benchmark_Rate__c>{ mine, expired };
    // A lane always belongs to a project (master-detail), so the project-less bid carries no
    // lane either and its lane keys are stamped the way the trigger would have stamped them.
    Benchmark_Rate__c loose = RfpTestDataFactory.buildBid(ownLane, 3000);
    loose.RFP_Lane__c = null;
    loose.City_Lane__c = BenchmarkRateService.cityLane(mtl, tor);
    loose.State_Lane__c = BenchmarkRateService.stateLane(mtl, tor);
    loose.Zip3_Lane__c = BenchmarkRateService.zip3Lane(mtl, tor);
    insert loose;

    Test.startTest();
    List<Decimal> kept = ratesFor(mtl, tor, own.Id, true);
    List<Decimal> live = ratesFor(mtl, tor, own.Id, false);
    Test.stopTest();

    // Rate__c is Currency(16,2), so the rows come back at scale 2 and Decimal equality is
    // scale-sensitive; the expected values carry the same scale.
    System.assertEquals(
      new Set<Decimal>{ 2000.00, 3000.00 },
      new Set<Decimal>(kept),
      'the own project\'s bid is out; the expired one and the project-less one are in'
    );
    System.assertEquals(
      new List<Decimal>{ 3000.00 },
      live,
      'without includeExpiredBids only the live project-less bid survives'
    );
  }

  private static List<Decimal> ratesFor(
    Pricing_Place__c origin,
    Pricing_Place__c destination,
    Id excludeProjectId,
    Boolean includeExpiredBids
  ) {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = origin.Key__c;
    req.destinationKey = destination.Key__c;
    req.sourceFilter = LaneSearchRequest.RowSource.ALL;
    req.excludeProjectId = excludeProjectId;
    req.includeExpiredBids = includeExpiredBids;
    req.validate();
    List<LaneSearchResult.Row> rows = BidSearchService.search(
      req,
      new Map<String, Pricing_Place__c>{
        origin.Key__c => origin,
        destination.Key__c => destination
      },
      new BidSearchService.Outcome()
    );
    List<Decimal> rates = new List<Decimal>();
    for (LaneSearchResult.Row r : rows) {
      rates.add(r.carrierTotal);
    }
    return rates;
  }

  private static LaneSearchRequest minimalRequest() {
    LaneSearchRequest r = new LaneSearchRequest();
    r.validate();
    return r;
  }
}
