/**
 * Returns the active bid with the lowest Rate__c in the given currency, or
 * null when there is none. `Status__c` is a two-value formula field
 * (Active/Expired), so filtering with `!== "Expired"` is exact — there is no
 * third status a bid can be in.
 */
export function bestBid(bids, currency) {
  const active = (bids || []).filter(
    (b) =>
      b.Status__c !== "Expired" &&
      b.CurrencyIsoCode === currency &&
      b.Rate__c !== null &&
      b.Rate__c !== undefined
  );
  if (!active.length) return null;
  return active.reduce((best, b) => {
    return Number(b.Rate__c) < Number(best.Rate__c) ? b : best;
  });
}

export function otherCurrencyCount(bids, currency) {
  return (bids || []).filter((b) => b.CurrencyIsoCode !== currency).length;
}
