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
