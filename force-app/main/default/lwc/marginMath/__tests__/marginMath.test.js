import { parseMargin, suggestedSell } from "c/marginMath";

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
  });
  it("returns null for missing or non-positive cost", () => {
    expect(suggestedSell(0, 15)).toBeNull();
    expect(suggestedSell(null, 15)).toBeNull();
    expect(suggestedSell(100, null)).toBeNull();
  });
});
