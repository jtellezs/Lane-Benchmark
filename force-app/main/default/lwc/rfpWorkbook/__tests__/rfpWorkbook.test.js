import { buildSheets, OUR_COLUMNS, exportFileName } from "c/rfpWorkbook";

describe("rfpWorkbook", () => {
  const lanes = [
    {
      Id: "l2",
      Row_Number__c: 2,
      Cost__c: null,
      Sell__c: null,
      Margin__c: 15,
      CurrencyIsoCode: "CAD",
      Notes__c: ""
    },
    {
      Id: "l1",
      Row_Number__c: 1,
      Cost__c: 1000,
      Sell__c: 1150,
      Margin__c: 15,
      CurrencyIsoCode: "CAD",
      Notes__c: "=SUM(A1)",
      Selected_Bid__r: { Carrier_Display__c: "Acme" }
    }
  ];
  const raw = [
    {
      Id: "l1",
      Row_Number__c: 1,
      Raw_Row__c: JSON.stringify({ From: "Montreal", To: "Toronto" })
    },
    {
      Id: "l2",
      Row_Number__c: 2,
      Raw_Row__c: JSON.stringify({ From: "Laval", To: "Ottawa" })
    }
  ];
  const bids = {
    l1: [
      {
        Carrier_Display__c: "Acme",
        Contact_Name__c: "Jo",
        Contact_Email__c: "j@a.test",
        Contact_Phone__c: null,
        Rate__c: 1000,
        CurrencyIsoCode: "CAD",
        Fuel_Surcharge__c: 50,
        FSC_Included__c: false,
        Transit_Days__c: 2,
        Valid_From__c: "2026-09-11",
        Expires_On__c: "2026-10-11",
        Status__c: "Active",
        Notes__c: null
      }
    ]
  };

  it("keeps the customer's order and columns, appends ours, leaves unpriced cells empty", () => {
    const { lanes: sheet, bids: bidSheet } = buildSheets(lanes, raw, bids);
    expect(sheet[0]).toEqual(["From", "To", ...OUR_COLUMNS]);
    expect(sheet[1].slice(0, 2)).toEqual(["Montreal", "Toronto"]);
    expect(sheet[1][2]).toBe(1000);
    expect(sheet[1][5]).toBe(1150);
    expect(sheet[1][9]).toBe("Acme");
    expect(sheet[1][10]).toBe("=SUM(A1)"); // typed string cell, no apostrophe
    expect(sheet[2][2]).toBe("");
    expect(sheet[2][5]).toBe("");
    expect(bidSheet[0][0]).toBe("Lane row");
    expect(bidSheet[1]).toEqual([
      1,
      "Acme",
      "Jo",
      "j@a.test",
      "",
      1000,
      "CAD",
      50,
      "No",
      2,
      "2026-09-11",
      "2026-10-11",
      "Active",
      ""
    ]);
  });
  it("names the file from customer, project and date", () => {
    expect(
      exportFileName("Costco Canada", "Q4 Lanes", new Date(2026, 8, 11))
    ).toBe("costco-canada-q4-lanes-20260911.xlsx");
  });
});
