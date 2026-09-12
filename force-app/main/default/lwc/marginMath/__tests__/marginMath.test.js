import { parseMargin, suggestedSell, marginFor } from "c/marginMath";

describe("parseMargin", () => {
  it("accepts plain numbers, percent signs and whitespace", () => {
    expect(parseMargin("15")).toBe(15);
    expect(parseMargin("15%")).toBe(15);
    expect(parseMargin(" 20 ")).toBe(20);
    expect(parseMargin("12.5")).toBe(12.5);
  });
  it("rejects out-of-range and non-numeric input", () => {
    expect(parseMargin("-1")).toBeNull();
    expect(parseMargin("101")).toBeNull();
    expect(parseMargin("abc")).toBeNull();
    expect(parseMargin("")).toBeNull();
    expect(parseMargin(null)).toBeNull();
  });
});

describe("suggestedSell", () => {
  it("applies the margin and rounds to cents", () => {
    expect(suggestedSell(1000, 15)).toBe(1150);
    expect(suggestedSell(1234.56, 20)).toBe(1481.47);
    expect(suggestedSell(100, 0)).toBe(100);
    expect(suggestedSell(1234.56, 15)).toBe(1419.74);
  });
  it("returns null for missing or non-positive cost", () => {
    expect(suggestedSell(0, 15)).toBeNull();
    expect(suggestedSell(null, 15)).toBeNull();
    expect(suggestedSell(100, null)).toBeNull();
  });
});

describe("marginFor", () => {
  it("mirrors RfpPricingMath.marginFor", () => {
    expect(marginFor(1000, 1150)).toBe(15);
    expect(marginFor(1000, 900)).toBe(-10);
    expect(marginFor(3, 3.01)).toBe(0.33);
    expect(marginFor(1000, 1000)).toBe(0);
  });
  it("returns null without a positive cost, without a sell, or beyond ±999.99", () => {
    expect(marginFor(0, 100)).toBeNull();
    expect(marginFor(null, 100)).toBeNull();
    expect(marginFor(1000, null)).toBeNull();
    expect(marginFor(1, 100000)).toBeNull();
  });
});
