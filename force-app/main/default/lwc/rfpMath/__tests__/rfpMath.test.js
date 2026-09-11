import { bestBid, otherCurrencyCount } from "c/rfpMath";

describe("rfpMath", () => {
  const bids = [
    { Id: "a", Rate__c: 1200, CurrencyIsoCode: "CAD", Status__c: "Active" },
    { Id: "b", Rate__c: 900, CurrencyIsoCode: "CAD", Status__c: "Expired" },
    { Id: "c", Rate__c: 1000, CurrencyIsoCode: "CAD", Status__c: "Active" },
    { Id: "d", Rate__c: 500, CurrencyIsoCode: "USD", Status__c: "Active" }
  ];
  it("picks the lowest active bid in the project currency", () => {
    expect(bestBid(bids, "CAD").Id).toBe("c");
    expect(bestBid([], "CAD")).toBeNull();
    expect(otherCurrencyCount(bids, "CAD")).toBe(1);
  });
});
