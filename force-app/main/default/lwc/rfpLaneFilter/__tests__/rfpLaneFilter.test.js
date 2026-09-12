import { STATUS_FILTERS, applyFilter, siblings } from "c/rfpLaneFilter";

const lane = (over) => ({
  Id: over.Id,
  Origin_City__c: "Montreal",
  Origin_Province__c: "QC",
  Origin_Postal__c: "H1A",
  Origin_Resolved__c: true,
  Origin_Place__c: "p1",
  Destination_City__c: "Toronto",
  Destination_Province__c: "ON",
  Destination_Postal__c: "M5V",
  Destination_Resolved__c: true,
  Destination_Place__c: "p2",
  Mode__c: "Truckload",
  Equipment_Type__c: "Dry Van 53'",
  Hist_Status__c: "Done",
  Cost__c: 1000,
  ...over
});

const L = [
  lane({ Id: "1" }),
  lane({ Id: "2", Cost__c: null, Hist_Status__c: "No match" }),
  lane({
    Id: "3",
    Destination_Resolved__c: false,
    Destination_Place__c: null,
    Destination_City__c: "Nowhere",
    Destination_Postal__c: null,
    Hist_Status__c: "Unresolved",
    Cost__c: null
  }),
  lane({ Id: "4", Cost_Source__c: "Manual" }),
  lane({ Id: "5", Sell_Source__c: "Manual", Equipment_Type__c: "Reefer" })
];

describe("applyFilter", () => {
  it("offers the six statuses in order", () => {
    expect(STATUS_FILTERS.map((o) => o.value)).toEqual([
      "all",
      "unpriced",
      "nomatch",
      "unresolved",
      "manual",
      "selected"
    ]);
  });
  it("filters by status", () => {
    const ids = (f) => applyFilter(L, f).map((l) => l.Id);
    expect(ids({ status: "all" })).toEqual(["1", "2", "3", "4", "5"]);
    expect(ids({ status: "unpriced" })).toEqual(["2", "3"]);
    expect(ids({ status: "nomatch" })).toEqual(["2"]);
    expect(ids({ status: "unresolved" })).toEqual(["3"]);
    expect(ids({ status: "manual" })).toEqual(["4", "5"]);
    expect(ids({ status: "selected", selectedIds: ["5", "1"] })).toEqual([
      "1",
      "5"
    ]);
  });
  it("searches places and equipment, case-insensitively", () => {
    const ids = (text) =>
      applyFilter(L, { status: "all", text }).map((l) => l.Id);
    expect(ids("nowhere")).toEqual(["3"]);
    expect(ids("REEFER")).toEqual(["5"]);
    expect(ids("m5v")).toEqual(["1", "2", "4", "5"]);
    expect(ids("  ")).toHaveLength(5);
  });
  it("tolerates missing lanes and options", () => {
    expect(applyFilter(null)).toEqual([]);
    expect(applyFilter(L, {})).toHaveLength(5);
  });
});

describe("siblings", () => {
  it("finds unpriced lanes with the same places, mode and equipment", () => {
    const twins = [
      lane({ Id: "a" }),
      lane({ Id: "b", Cost__c: null }),
      lane({ Id: "c", Cost__c: null, Mode__c: "LTL" }),
      lane({
        Id: "d",
        Cost__c: null,
        Equipment_Type__c: null,
        Equipment_Category__c: "Dry Van 53'"
      }),
      lane({ Id: "e", Cost__c: null, Destination_Place__c: "p9" })
    ];
    expect(siblings(twins, twins[0]).map((l) => l.Id)).toEqual(["b", "d"]);
  });
  it("never matches from or to an unresolved lane", () => {
    expect(siblings(L, L[2])).toEqual([]);
    expect(siblings(null, L[0])).toEqual([]);
  });
  it("offers nothing when the lane just saved has no cost of its own", () => {
    const twins = [
      lane({ Id: "a", Cost__c: null }),
      lane({ Id: "b", Cost__c: null })
    ];
    expect(siblings(twins, twins[0])).toEqual([]);
  });
});
