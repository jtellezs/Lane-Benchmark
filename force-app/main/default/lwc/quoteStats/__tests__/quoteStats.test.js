import { calculateStats, shapeRows, modeOptionsFrom } from "c/quoteStats";

const q = (total, mode = "Truckload", id = "a") => ({
  Id: id,
  CAD_Quote_Total__c: total,
  Mode__c: mode
});

describe("calculateStats", () => {
  it("returns zeros for an empty list", () => {
    expect(calculateStats([])).toEqual({
      min: 0,
      max: 0,
      avg: 0,
      roundedAvg: "0.00",
      nbOfQuotes: 0,
      nbOfQuotesNotZero: 0
    });
  });

  it("ignores zero totals for min, max and average but counts them", () => {
    const s = calculateStats([q(0), q(100), q(300)]);
    expect(s.min).toBe(100);
    expect(s.max).toBe(300);
    expect(s.avg).toBe(200);
    expect(s.roundedAvg).toBe("200.00");
    expect(s.nbOfQuotes).toBe(3);
    expect(s.nbOfQuotesNotZero).toBe(2);
  });

  it("rounds the average to two decimals as a string", () => {
    expect(calculateStats([q(100), q(101), q(101)]).roundedAvg).toBe("100.67");
  });
});

describe("shapeRows", () => {
  it("numbers rows from 1 and assigns the mode cell class", () => {
    const rows = shapeRows([
      q(1, "LTL", "x"),
      q(2, "Truckload", "y"),
      q(3, "Freight Forwarding", "z"),
      q(4, "Drayage", "w")
    ]);
    expect(rows.map((r) => r.rowNumber)).toEqual([1, 2, 3, 4]);
    expect(rows.map((r) => r.cellModeClass)).toEqual([
      "ltl-cell",
      "ftl-cell",
      "freight-cell",
      ""
    ]);
    expect(rows[0].additionalContentKey).toBe("x-additional-content");
    expect(rows[0].showAdditionalContent).toBe(false);
  });

  it("does not mutate the input objects", () => {
    const input = [q(1)];
    shapeRows(input);
    expect(input[0].rowNumber).toBeUndefined();
  });
});

describe("modeOptionsFrom", () => {
  it("lists distinct modes after an All option", () => {
    expect(
      modeOptionsFrom([q(1, "LTL"), q(2, "Truckload"), q(3, "LTL")])
    ).toEqual([
      { label: "-- All --", value: "" },
      { label: "LTL", value: "LTL" },
      { label: "Truckload", value: "Truckload" }
    ]);
  });
});
