import { hasBothKeys, noRate, directMedian } from "c/carrierLeadRules";

const STATS = {
  CAD: { count: 3, countNonZero: 2, median: 1950 },
  USD: { count: 1, countNonZero: 0, median: null }
};
const request = (originKey, destinationKey) =>
  JSON.stringify({ originKey, destinationKey, originPrecision: "CITY" });

describe("hasBothKeys", () => {
  it("is true only when both ends carry a place key", () => {
    expect(hasBothKeys(request("montreal|qc|ca", "toronto|on|ca"))).toBe(true);
    expect(hasBothKeys(request("montreal|qc|ca", null))).toBe(false);
    expect(hasBothKeys(request("  ", "toronto|on|ca"))).toBe(false);
    expect(
      hasBothKeys(JSON.stringify({ destinationKey: "toronto|on|ca" }))
    ).toBe(false);
  });
  it("is false for a blank or unreadable request", () => {
    expect(hasBothKeys(null)).toBe(false);
    expect(hasBothKeys(undefined)).toBe(false);
    expect(hasBothKeys("")).toBe(false);
    expect(hasBothKeys("{not json")).toBe(false);
    expect(hasBothKeys("null")).toBe(false);
  });
});

describe("noRate", () => {
  it("reads only the bucket of the currency it is given", () => {
    expect(noRate(STATS, "CAD")).toBe(false);
    // a bucket whose rows all have a 0 total, and a currency with no bucket
    expect(noRate(STATS, "USD")).toBe(true);
    expect(noRate(STATS, "MXN")).toBe(true);
  });
  it("looks at every bucket when no currency is given", () => {
    expect(noRate(STATS, null)).toBe(false);
    expect(noRate(STATS, "")).toBe(false);
    expect(noRate({ USD: { count: 2, countNonZero: 0 } }, undefined)).toBe(
      true
    );
  });
  it("counts missing statistics as no rate", () => {
    expect(noRate(null, "CAD")).toBe(true);
    expect(noRate(undefined, null)).toBe(true);
    expect(noRate({}, "CAD")).toBe(true);
    expect(noRate({}, null)).toBe(true);
  });
});

describe("directMedian", () => {
  it("gives the median of the priced bucket in that currency", () => {
    expect(directMedian(STATS, "CAD")).toBe(1950);
  });
  it("gives null without a priced bucket, a currency or statistics", () => {
    expect(directMedian(STATS, "USD")).toBeNull();
    expect(directMedian(STATS, "MXN")).toBeNull();
    expect(directMedian(STATS, null)).toBeNull();
    expect(directMedian(null, "CAD")).toBeNull();
  });
});
