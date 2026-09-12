import {
  SOURCES,
  money,
  costFor,
  bidOptions,
  bidRows,
  bestBidHint,
  otherCurrencyNote,
  pricingDetail,
  historyKey,
  historyRequest,
  parseRadius,
  inlineEdit,
  recompute,
  pricingFingerprint,
  parseMoney
} from "c/rfpPricing";

const LANE = {
  Id: "a0L1",
  Hist_Median__c: 2000,
  Hist_Precision__c: "CITY",
  Origin_Place__r: { Key__c: "montreal|qc|ca" },
  Destination_Place__r: { Key__c: "toronto|on|ca" },
  Cost__c: 1000,
  Cost_Source__c: "History median",
  Selected_Bid__c: null,
  Margin__c: 15,
  Sell__c: 1150,
  Sell_Source__c: "Margin",
  Notes__c: "n"
};

const ACTIVE = {
  Id: "a0B1",
  Carrier_Display__c: "Acme Transport",
  Rate__c: 1800,
  CurrencyIsoCode: "CAD",
  Status__c: "Active"
};
const EXPIRED = {
  Id: "a0B2",
  Carrier_Display__c: "Old Lines",
  Rate__c: 1200,
  CurrencyIsoCode: "CAD",
  Status__c: "Expired"
};
const USD = {
  Id: "a0B3",
  Carrier_Display__c: "Border Freight",
  Rate__c: 900,
  CurrencyIsoCode: "USD",
  Status__c: "Active"
};

describe("rfpPricing", () => {
  it("offers the three cost sources the lane field accepts", () => {
    expect(SOURCES.map((s) => s.value)).toEqual([
      "Bid",
      "History median",
      "Manual"
    ]);
  });

  it("formats money with two decimals and blanks the empties", () => {
    expect(money(1900)).toBe("1900.00");
    expect(money("2000.5")).toBe("2000.50");
    expect(money(null)).toBe("");
    expect(money(undefined)).toBe("");
    expect(money("")).toBe("");
    expect(money("n/a")).toBe("");
  });

  it("reads the cost from the chosen source", () => {
    const state = {
      lane: LANE,
      bids: [ACTIVE, EXPIRED],
      selectedBidId: "a0B1",
      manualCost: "1750.25"
    };
    expect(costFor("Bid", state)).toBe(1800);
    expect(costFor("History median", state)).toBe(2000);
    expect(costFor("Manual", state)).toBe(1750.25);
    expect(costFor("Bid", { ...state, selectedBidId: null })).toBeNull();
    expect(costFor("Manual", { ...state, manualCost: "" })).toBeNull();
    expect(costFor("Manual", { ...state, manualCost: "abc" })).toBeNull();
    expect(
      costFor("History median", { ...state, lane: { Id: "a0L1" } })
    ).toBeNull();
  });

  it("labels bid options with the carrier, rate and expiry", () => {
    expect(bidOptions([ACTIVE, EXPIRED])).toEqual([
      { label: "Acme Transport — 1800.00 CAD", value: "a0B1" },
      { label: "Old Lines — 1200.00 CAD (expired)", value: "a0B2" }
    ]);
  });

  it("greys out expired bids in the list and spells out the rate", () => {
    const [active, expired] = bidRows([ACTIVE, EXPIRED]);
    expect(active.rateText).toBe("1800.00 CAD");
    expect(active.rowClass).toBe("");
    expect(expired.rateText).toBe("1200.00 CAD");
    expect(expired.rowClass).toBe("slds-text-color_weak");
    expect(expired.Carrier_Display__c).toBe("Old Lines");
    expect(active.buttonClass).toBe("slds-button slds-button_reset bid-row");
    expect(expired.buttonClass).toContain("slds-text-color_weak");
  });

  it("hints at the best bid only when it beats a real cost", () => {
    expect(bestBidHint([ACTIVE], "CAD", 2000)).toContain("Acme Transport");
    expect(bestBidHint([ACTIVE], "CAD", 2000)).toContain("1800.00");
    expect(bestBidHint([ACTIVE], "CAD", 1500)).toBeNull();
    expect(bestBidHint([ACTIVE], "CAD", null)).toBeNull();
    // the cheaper bid is expired, so it is not offered
    expect(bestBidHint([EXPIRED], "CAD", 2000)).toBeNull();
  });

  it("counts the bids left out of the comparison by currency", () => {
    expect(otherCurrencyNote([ACTIVE], "CAD")).toBeNull();
    expect(otherCurrencyNote([ACTIVE, USD], "CAD")).toBe(
      "1 bid in another currency is not compared"
    );
    expect(otherCurrencyNote([USD, { ...USD, Id: "a0B4" }], "CAD")).toBe(
      "2 bids in another currency are not compared"
    );
  });

  it("builds the whitelisted pricing payload and only keeps a bid id for Bid", () => {
    expect(
      pricingDetail({
        laneId: "a0L1",
        source: "Bid",
        selectedBidId: "a0B1",
        cost: 1800,
        marginText: "20%",
        notes: "Renewal"
      })
    ).toEqual({
      laneId: "a0L1",
      Cost__c: 1800,
      Cost_Source__c: "Bid",
      Selected_Bid__c: "a0B1",
      Margin__c: 20,
      Sell__c: 2160,
      Sell_Source__c: "Margin",
      Notes__c: "Renewal"
    });

    expect(
      pricingDetail({
        laneId: "a0L1",
        source: "Manual",
        selectedBidId: "a0B1",
        cost: 1000,
        marginText: "",
        notes: ""
      })
    ).toEqual({
      laneId: "a0L1",
      Cost__c: 1000,
      Cost_Source__c: "Manual",
      Selected_Bid__c: null,
      Margin__c: null,
      Sell__c: null,
      Sell_Source__c: "Margin",
      Notes__c: null
    });
  });

  it("keys the history search on the places, precision and lookback", () => {
    expect(historyKey(null)).toBeNull();
    expect(
      historyKey({ Origin_Place__r: { Key__c: "montreal|qc|ca" } })
    ).toBeNull();
    expect(historyKey(LANE)).toBe(historyKey({ ...LANE, Id: "other" }));
    expect(historyKey(LANE)).not.toBe(
      historyKey({ ...LANE, Hist_Lookback_Days__c: 180 })
    );
  });

  it("asks for loads on both keys, widening to 50 km on a radius fallback", () => {
    expect(JSON.parse(historyRequest(LANE))).toEqual({
      originKey: "montreal|qc|ca",
      destinationKey: "toronto|on|ca",
      originPrecision: "CITY",
      destinationPrecision: "CITY",
      originRadius: null,
      destinationRadius: null,
      radiusUnit: "KM",
      lookbackDays: 90,
      sourceFilter: "LOADS",
      rowLimit: 500,
      includeStopGeolocation: true
    });

    const wide = JSON.parse(
      historyRequest({
        ...LANE,
        Hist_Precision__c: "RADIUS-50KM",
        Hist_Lookback_Days__c: 180
      })
    );
    expect(wide.originPrecision).toBe("RADIUS");
    expect(wide.destinationPrecision).toBe("RADIUS");
    expect(wide.originRadius).toBe(50);
    expect(wide.destinationRadius).toBe(50);
    expect(wide.lookbackDays).toBe(180);
  });
});

describe("parseRadius", () => {
  it("reads the radius and unit out of the precision stamp", () => {
    expect(parseRadius("RADIUS-50KM")).toEqual({ radius: 50, unit: "KM" });
    expect(parseRadius("RADIUS-120MI")).toEqual({ radius: 120, unit: "MI" });
  });
  it("is null for city, province, blanks and junk", () => {
    expect(parseRadius("CITY")).toBeNull();
    expect(parseRadius("PROVINCE")).toBeNull();
    expect(parseRadius(null)).toBeNull();
    expect(parseRadius("RADIUS-KM")).toBeNull();
  });
});

describe("historyRequest with a stamped radius", () => {
  it("searches at the radius the snapshot used", () => {
    const req = JSON.parse(
      historyRequest({
        Origin_Place__r: { Key__c: "a" },
        Destination_Place__r: { Key__c: "b" },
        Hist_Precision__c: "RADIUS-150MI",
        Hist_Lookback_Days__c: 60
      })
    );
    expect(req.originPrecision).toBe("RADIUS");
    expect(req.originRadius).toBe(150);
    expect(req.destinationRadius).toBe(150);
    expect(req.radiusUnit).toBe("MI");
  });
});

describe("pricingDetail with a sell source", () => {
  it("derives the sell from the margin when the margin drives", () => {
    const d = pricingDetail({
      laneId: "a0L1",
      source: "Manual",
      cost: 1000,
      marginText: "20",
      notes: "",
      sellSource: "Margin",
      sellText: "999"
    });
    expect(d).toMatchObject({
      Margin__c: 20,
      Sell__c: 1200,
      Sell_Source__c: "Margin"
    });
  });
  it("keeps the typed sell and derives the margin when the sell drives", () => {
    const d = pricingDetail({
      laneId: "a0L1",
      source: "Manual",
      cost: 1000,
      marginText: "20",
      notes: "",
      sellSource: "Manual",
      sellText: "1500"
    });
    expect(d).toMatchObject({
      Margin__c: 50,
      Sell__c: 1500,
      Sell_Source__c: "Manual"
    });
  });
});

describe("inlineEdit", () => {
  it("a typed margin recomputes the sell", () => {
    expect(inlineEdit(LANE, "margin", "20", 15)).toMatchObject({
      laneId: "a0L1",
      Margin__c: 20,
      Sell__c: 1200,
      Sell_Source__c: "Margin",
      Cost__c: 1000,
      Notes__c: "n"
    });
  });
  it("a typed sell flips the lane to Manual and derives the margin", () => {
    expect(inlineEdit(LANE, "sell", "900", 15)).toMatchObject({
      Sell__c: 900,
      Sell_Source__c: "Manual",
      Margin__c: -10
    });
  });
  it("a typed cost becomes a manual cost and follows the sell source", () => {
    expect(inlineEdit(LANE, "cost", "2000", 15)).toMatchObject({
      Cost__c: 2000,
      Cost_Source__c: "Manual",
      Selected_Bid__c: null,
      Sell__c: 2300,
      Margin__c: 15
    });
    const manual = { ...LANE, Sell_Source__c: "Manual", Sell__c: 1500 };
    expect(inlineEdit(manual, "cost", "2000", 15)).toMatchObject({
      Cost__c: 2000,
      Sell__c: 1500,
      Margin__c: -25,
      Sell_Source__c: "Manual"
    });
  });
  it("uses the project default margin when the lane has none", () => {
    expect(inlineEdit({ Id: "a0L2" }, "cost", "100", 12)).toMatchObject({
      Margin__c: 12,
      Sell__c: 112
    });
  });
  it("rejects blanks, junk, non-positive money and out-of-range margins", () => {
    expect(inlineEdit(LANE, "cost", "", 15)).toBeNull();
    expect(inlineEdit(LANE, "cost", "abc", 15)).toBeNull();
    expect(inlineEdit(LANE, "sell", "0", 15)).toBeNull();
    expect(inlineEdit(LANE, "margin", "101", 15)).toBeNull();
    expect(inlineEdit(LANE, "notes", "x", 15)).toBeNull();
  });
});

describe("recompute / fingerprint / parseMoney", () => {
  it("recompute mirrors RfpPricingMath.recompute", () => {
    expect(
      recompute(
        { Cost__c: 2000, Margin__c: null, Sell__c: null, Sell_Source__c: null },
        15
      )
    ).toMatchObject({ Margin__c: 15, Sell__c: 2300, Sell_Source__c: "Margin" });
  });
  it("fingerprint changes with any of the six pricing fields", () => {
    const a = pricingFingerprint(LANE);
    expect(pricingFingerprint({ ...LANE, Notes__c: "other" })).toBe(a);
    expect(pricingFingerprint({ ...LANE, Sell__c: 1151 })).not.toBe(a);
    expect(pricingFingerprint(null)).toBe(pricingFingerprint(undefined));
  });
  it("parseMoney", () => {
    expect(parseMoney("12.5")).toBe(12.5);
    expect(parseMoney(" 7 ")).toBe(7);
    expect(parseMoney("0")).toBeNull();
    expect(parseMoney("")).toBeNull();
    expect(parseMoney(null)).toBeNull();
  });
});
