/**
 * One definition of "market test" for both halves of the Lane Benchmark control.
 *
 * Lane Benchmark merges quote rows and bid rows into one result set, and Include / Exclude / Only
 * is one control over both. The two halves therefore have to agree, and they did not: the bid half
 * resolves the house account by id from Pricing_Department_Setting__mdt, while the quote half
 * matched the literal '%Market Test%' - so renaming the account left Exclude still dropping quotes
 * by the old name while the bid half followed the new one (phase 12 review, finding #3).
 *
 * They cannot match on the same thing: rtms__CarrierQuote__c carries only Customer_Name__c and has
 * no account lookup, so the quote half has nothing but a name to match on. The fix is to take that
 * name from the account the setting points at rather than from a literal, so both halves move when
 * the account is renamed. With nothing configured the literal is still the answer, because a quote
 * has no marker to fall back to and an id-only condition would match nothing.
 *
 * Split out of BidSearchQueryBuilder and LaneSearchFilters per the Task 7 ruling that a class over
 * PMD's 40 total cyclomatic complexity is split rather than suppressed: BidSearchQueryBuilder
 * reached 41 when phase 12 added its half. Keeping both halves here is what makes their agreement
 * checkable in one place.
 */
public with sharing class MarketTestFilter {
  /**
   * The quote half. Matched on the house account's current name, since the quote carries a name
   * and no account. The NOT is parenthesised because this condition is never first in the join.
   */
  public static void forQuotes(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.marketTestFilter == LaneSearchRequest.MarketTest.INCLUDE) {
      return;
    }
    binds.put('marketTest', '%' + MarketTestSetting.accountName() + '%');
    conditions.add(
      req.marketTestFilter == LaneSearchRequest.MarketTest.ONLY
        ? 'Customer_Name__c LIKE :marketTest'
        : '(NOT Customer_Name__c LIKE :marketTest)'
    );
  }

  /**
   * The bid half. A bid is market test when it carries the phase 9 marker, or when it sits on a
   * project of the Market Test account - the two ways a rate is recorded without a customer.
   *
   * The NOT has to be parenthesised: this condition is never first (CreatedDate is), so the join
   * produces "... AND NOT ..." which SOQL rejects with "unexpected token: 'NOT'". Choosing Exclude
   * threw QueryException in both branches before the phase 12 review caught it.
   */
  public static void forBids(
    LaneSearchRequest req,
    List<String> conditions,
    Map<String, Object> binds
  ) {
    if (req.marketTestFilter == LaneSearchRequest.MarketTest.INCLUDE) {
      return;
    }
    Id house = MarketTestSetting.accountId();
    binds.put('bMarketTestAccount', house);
    String isMarketTest = house == null
      ? 'Market_Test__c = true'
      : '(Market_Test__c = true OR RFP_Project__r.Customer__c = :bMarketTestAccount)';
    conditions.add(
      req.marketTestFilter == LaneSearchRequest.MarketTest.ONLY
        ? isMarketTest
        : '(NOT ' + isMarketTest + ')'
    );
  }
}
