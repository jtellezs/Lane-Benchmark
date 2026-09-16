/**
 * When Carriers to ask may run (spec §3, D2 and D3), decided from what the screen already has:
 * the request JSON its first search sent and that search's statsByCurrency. No Apex here.
 */

const filled = (value) => typeof value === "string" && value.trim() !== "";
const priced = (bucket) => !!bucket && bucket.countNonZero > 0;

/** True when the request names a place key on both ends; false for blank or unreadable JSON. */
export function hasBothKeys(requestJson) {
  if (!filled(requestJson)) {
    return false;
  }
  try {
    const request = JSON.parse(requestJson);
    return (
      !!request && filled(request.originKey) && filled(request.destinationKey)
    );
  } catch {
    return false;
  }
}

/**
 * True when the first search found no priced carrier rate (a total other than 0) in the pricing
 * currency (D2): that currency's bucket when a code is given, every bucket when it is blank.
 */
export function noRate(statsByCurrency, currencyCode) {
  if (!statsByCurrency) {
    return true;
  }
  if (filled(currencyCode)) {
    return !priced(statsByCurrency[currencyCode]);
  }
  return !Object.values(statsByCurrency).some((bucket) => priced(bucket));
}

/** The first search's median in that currency, or null when it has no priced rate there. */
export function directMedian(statsByCurrency, currencyCode) {
  const bucket =
    statsByCurrency && filled(currencyCode)
      ? statsByCurrency[currencyCode]
      : null;
  return priced(bucket) && bucket.median !== undefined ? bucket.median : null;
}
