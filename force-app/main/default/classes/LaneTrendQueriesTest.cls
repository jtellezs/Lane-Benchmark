/**
 * Ruling 30: the trend's query shapes, asserted on the generated SOQL text.
 *
 * This exists because the quote half of the CreatedDate move is not reachable from data.
 * Quote_Date__c is the formula IF(!ISBLANK(Shipping_Date__c), Shipping_Date__c,
 * DATEVALUE(CreatedDate)), and Shipping_Date__c resolves through
 * rtms__Load__r.rtms__Expected_Ship_Date2__c, which is neither createable nor updateable. So in any
 * test Quote_Date__c collapses to DATEVALUE(CreatedDate) and no fixture can tell the two fields
 * apart. The whole-branch re-review pointed this out, and it was reproduced here before this class
 * was written: reverting LaneTrendQueries.quoteSoql and LaneTrendService.readQuoteSamples to
 * Quote_Date__c leaves all twenty LaneTrendServiceTest methods green (measured, not assumed - Apex
 * run 707As00001WimhM). The half that carried the measured bias (341 of 4,892 PostProduc quotes over
 * 30 days) was pinned by nothing. Asserting on the SOQL string is the pattern
 * LaneSearchQueryBuilderTest and BidSearchQueryBuilderTest already use for the WHERE halves these
 * methods borrow.
 *
 * Its own class rather than two more methods on LaneTrendServiceTest, because that class sits at
 * exactly 39 of PMD's 40-point cyclomatic-complexity total and any added method trips the rule - and
 * the project's standing ruling is that a class at the ceiling is split, not suppressed (the ruling
 * behind LaneSearchFilters, MarketTestFilter, LaneTrendQueries, LaneTrendScope and LaneTrendSummary).
 * The split lands where it should anyway: these assertions are about LaneTrendQueries, which had no
 * test class of its own.
 *
 * Pure: quoteSoql and bidSoql are string builders, the places live only in memory, and nothing is
 * inserted.
 */
@IsTest
private class LaneTrendQueriesTest {
  /**
   * The in-memory lane both tests ask about. The exclusion override stands in for the custom
   * metadata read that LaneSearchQueryBuilder.whereFor performs, exactly as
   * LaneSearchQueryBuilderTest does - custom metadata cannot be inserted in a test.
   */
  private static Map<String, Pricing_Place__c> places() {
    LaneSearchExclusions.excludedContactIdsOverride = new Set<String>();
    return new Map<String, Pricing_Place__c>{
      'montreal|qc|ca' => new Pricing_Place__c(
        Key__c = 'montreal|qc|ca',
        City__c = 'Montreal',
        Province__c = 'QC',
        Country__c = 'CA'
      ),
      'toronto|on|ca' => new Pricing_Place__c(
        Key__c = 'toronto|on|ca',
        City__c = 'Toronto',
        Province__c = 'ON',
        Country__c = 'CA'
      )
    };
  }

  private static LaneSearchRequest request() {
    LaneSearchRequest req = new LaneSearchRequest();
    req.originKey = 'montreal|qc|ca';
    req.destinationKey = 'toronto|on|ca';
    return req;
  }

  /**
   * The blanket "no Quote_Date__c anywhere" assertion is sound for quotes specifically: the only
   * Quote_Date__c in the search builder is in its SELECT_CLAUSE, which the trend does not borrow -
   * it borrows whereFor, and no condition whereFor can emit names that field.
   *
   * Mutations: revert the projection to Quote_Date__c and the first assertion goes red; revert
   * ORDER BY and the second does; either revert also trips the third.
   */
  @IsTest
  static void theQuoteQueryIsDatedAndOrderedByCreatedDate() {
    Map<String, Pricing_Place__c> lanePlaces = places();

    Test.startTest();
    String soql = LaneTrendQueries.quoteSoql(
      request(),
      new Map<String, Object>(),
      lanePlaces
    );
    Test.stopTest();

    System.assertEquals(
      true,
      soql.contains('SELECT CreatedDate,'),
      'the quote projection must read the same date the borrowed WHERE filters on: ' +
      soql
    );
    System.assertEquals(
      true,
      soql.contains('ORDER BY CreatedDate DESC'),
      'and order by it, so a truncated lane loses its oldest months rather than its newest: ' +
      soql
    );
    System.assertEquals(
      false,
      soql.contains('Quote_Date__c'),
      'Quote_Date__c is the future-dated formula the trend was moved off: ' +
      soql
    );
  }

  /**
   * The bid half - asserted for symmetry, and deliberately not asserted the same way.
   *
   * A blanket "no Valid_From__c anywhere" would be wrong here, and would fail for a reason that is
   * not a defect: the borrowed bid WHERE still filters Valid_From__c <= TODAY to decide whether a
   * bid is currently valid, which is correct and unchanged. Only the projection and the ORDER BY
   * moved, so only those two are asserted absent - and the validity condition is asserted present,
   * so a future edit cannot sweep it up in the move.
   *
   * Mutations: revert the projection and the first and third assertions go red; revert ORDER BY and
   * the second and fourth do.
   */
  @IsTest
  static void theBidQueryIsDatedAndOrderedByCreatedDate() {
    Map<String, Pricing_Place__c> lanePlaces = places();

    Test.startTest();
    String soql = LaneTrendQueries.bidSoql(
      request(),
      new Map<String, Object>(),
      lanePlaces
    );
    Test.stopTest();

    System.assertEquals(
      true,
      soql.contains('SELECT CreatedDate,'),
      'bids bucket on CreatedDate too, so one merged series has one axis: ' +
      soql
    );
    System.assertEquals(
      true,
      soql.contains('ORDER BY CreatedDate DESC'),
      'and the same ordering, for the same truncation reason as quotes: ' + soql
    );
    System.assertEquals(
      false,
      soql.contains('SELECT Valid_From__c'),
      'Valid_From__c dates a bid\'s validity period, not when the rate arrived: ' +
      soql
    );
    System.assertEquals(
      false,
      soql.contains('ORDER BY Valid_From__c'),
      'nor does it order the read: ' + soql
    );
    System.assertEquals(
      true,
      soql.contains('Valid_From__c <= TODAY'),
      'the WHERE\'s own validity check still uses it, and must not have been swept up in the move: ' +
      soql
    );
  }
}
