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
      Hist_Bid_Count__c: 3,
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
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Sell")]).toBe(1150);
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Bid carrier")]).toBe("Acme");
    // typed string cell, no apostrophe
    expect(sheet[1][2 + OUR_COLUMNS.indexOf("Notes")]).toBe("=SUM(A1)");

    // Phase 3d: how much of the lane's history came from other RFPs' bids.
    const bidCountIdx = 2 + OUR_COLUMNS.indexOf("History bids");
    expect(OUR_COLUMNS[OUR_COLUMNS.indexOf("History bids") - 1]).toBe(
      "Bid carrier"
    );
    expect(sheet[1][bidCountIdx]).toBe(3);
    // A lane that has never run carries no count, so its cell stays blank.
    expect(sheet[2][bidCountIdx]).toBe("");
    expect(sheet[2][2]).toBe("");
    expect(sheet[2][2 + OUR_COLUMNS.indexOf("Sell")]).toBe("");
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
  it("puts the cost source right after Currency, blank while the lane has no cost", () => {
    const sourced = [
      {
        Id: "c1",
        Row_Number__c: 1,
        Cost__c: 6453.25,
        Cost_Source__c: "Split",
        CurrencyIsoCode: "USD"
      },
      {
        Id: "c2",
        Row_Number__c: 2,
        Cost__c: 1800,
        Cost_Source__c: "Bid",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c3",
        Row_Number__c: 3,
        Cost__c: 2000,
        Cost_Source__c: "History median",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c4",
        Row_Number__c: 4,
        Cost__c: 900,
        Cost_Source__c: "Manual",
        CurrencyIsoCode: "CAD"
      },
      // A source left on a lane without a cost says nothing.
      {
        Id: "c5",
        Row_Number__c: 5,
        Cost__c: null,
        Cost_Source__c: "Manual",
        CurrencyIsoCode: "CAD"
      },
      {
        Id: "c6",
        Row_Number__c: 6,
        Cost__c: "",
        Cost_Source__c: "Split",
        CurrencyIsoCode: "CAD"
      },
      { Id: "c7", Row_Number__c: 7, CurrencyIsoCode: "CAD" }
    ];
    const { lanes: sheet } = buildSheets(sourced, [], {});
    const header = sheet[0];
    const at = header.indexOf("Currency");
    expect(header.slice(at - 1, at + 3)).toEqual([
      "Cost",
      "Currency",
      "Cost source",
      "Margin %"
    ]);
    expect(OUR_COLUMNS.length).toBe(19);
    expect(sheet.slice(1).map((row) => row[at + 1])).toEqual([
      "Split",
      "Bid",
      "History median",
      "Manual",
      "",
      "",
      ""
    ]);
    expect(sheet[1].slice(at - 1, at + 1)).toEqual([6453.25, "USD"]);
  });

  it("names the file from customer, project and date", () => {
    expect(
      exportFileName("Costco Canada", "Q4 Lanes", new Date(2026, 8, 11))
    ).toBe("costco-canada-q4-lanes-20260911.xlsx");
  });

  it("takes the fuel surcharge, FSC and transit days from the selected bid, not just any bid on the lane", () => {
    const selectedLanes = [
      {
        Id: "l9",
        Row_Number__c: 1,
        Cost__c: 800,
        Sell__c: 900,
        Margin__c: 12.5,
        CurrencyIsoCode: "CAD",
        Notes__c: "",
        Selected_Bid__c: "b2",
        Selected_Bid__r: { Carrier_Display__c: "Beta" }
      },
      {
        Id: "l10",
        Row_Number__c: 2,
        Cost__c: null,
        Sell__c: null,
        Margin__c: null,
        CurrencyIsoCode: "CAD",
        Notes__c: "",
        Selected_Bid__c: null
      }
    ];
    const selectedRaw = [
      {
        Id: "l9",
        Row_Number__c: 1,
        Raw_Row__c: JSON.stringify({ From: "Montreal", To: "Toronto" })
      },
      {
        Id: "l10",
        Row_Number__c: 2,
        Raw_Row__c: JSON.stringify({ From: "Laval", To: "Ottawa" })
      }
    ];
    const selectedBids = {
      l9: [
        {
          Id: "b1",
          Rate__c: 700,
          Fuel_Surcharge__c: 10,
          FSC_Included__c: true,
          Transit_Days__c: 5
        },
        {
          Id: "b2",
          Rate__c: 800,
          Fuel_Surcharge__c: 25,
          FSC_Included__c: false,
          Transit_Days__c: 3
        }
      ],
      // l10 has bids on file, but none is selected — the lane row must
      // still show blank fuel surcharge/FSC/transit-days cells rather than
      // picking one anyway.
      l10: [
        {
          Id: "b3",
          Rate__c: 500,
          Fuel_Surcharge__c: 40,
          FSC_Included__c: true,
          Transit_Days__c: 1
        }
      ]
    };
    const { lanes: sheet } = buildSheets(
      selectedLanes,
      selectedRaw,
      selectedBids
    );
    const headerCount = sheet[0].length - OUR_COLUMNS.length;
    const fuelIdx = headerCount + OUR_COLUMNS.indexOf("Fuel surcharge");
    const fscIdx = headerCount + OUR_COLUMNS.indexOf("FSC included");
    const transitIdx = headerCount + OUR_COLUMNS.indexOf("Transit days");

    expect(sheet[1][fuelIdx]).toBe(25);
    expect(sheet[1][fscIdx]).toBe("No");
    expect(sheet[1][transitIdx]).toBe(3);

    expect(sheet[2][fuelIdx]).toBe("");
    expect(sheet[2][fscIdx]).toBe("");
    expect(sheet[2][transitIdx]).toBe("");
  });

  it("carries the trip in miles and km after Transit days, with the rate per mile", () => {
    const tripLanes = [
      {
        Id: "t1",
        Row_Number__c: 1,
        Cost__c: 1500,
        Sell__c: 1800,
        CurrencyIsoCode: "CAD",
        Miles__c: 1234,
        Miles_Source__c: "Truck route",
        Route_Hours__c: 21.5
      },
      {
        Id: "t2",
        Row_Number__c: 2,
        Cost__c: null,
        Sell__c: null,
        CurrencyIsoCode: "CAD",
        Miles__c: 410.5,
        Miles_Source__c: "History",
        Route_Hours__c: null
      },
      {
        Id: "t3",
        Row_Number__c: 3,
        Cost__c: 900,
        Sell__c: 1000,
        CurrencyIsoCode: "CAD",
        Miles__c: null,
        Miles_Source__c: "No route",
        Route_Hours__c: null
      },
      // never run: no trip fields at all
      {
        Id: "t4",
        Row_Number__c: 4,
        Cost__c: 900,
        Sell__c: 1000,
        CurrencyIsoCode: "CAD"
      }
    ];
    const { lanes: sheet } = buildSheets(tripLanes, [], {});
    const header = sheet[0];
    const at = header.indexOf("Transit days");
    expect(header.slice(at, at + 8)).toEqual([
      "Transit days",
      "Miles",
      "Km",
      "Miles source",
      "Route hours",
      "Cost per mile",
      "Sell per mile",
      "Bid carrier"
    ]);
    const trip = (i) => sheet[i].slice(at + 1, at + 7);
    // 1234 mi = 1985.93 km; 1500 / 1234 = 1.2156; 1800 / 1234 = 1.4587
    expect(trip(1)).toEqual([1234, 1985.9, "Truck route", 21.5, 1.22, 1.46]);
    // miles without a price: the per-mile cells stay empty
    expect(trip(2)).toEqual([410.5, 660.6, "History", "", "", ""]);
    // no miles, but the reason still travels
    expect(trip(3)).toEqual(["", "", "No route", "", "", ""]);
    expect(trip(4)).toEqual(["", "", "", "", "", ""]);
  });
});

describe("annual sell and summary", () => {
  const lanes = [
    {
      Id: "1",
      Row_Number__c: 1,
      Mode__c: "Truckload",
      Cost__c: 1000,
      Margin__c: 15,
      Sell__c: 1150,
      Sell_Source__c: "Margin",
      Shipments_Per_Year__c: 52,
      CurrencyIsoCode: "CAD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: true,
      Hist_Status__c: "Done"
    },
    {
      Id: "2",
      Row_Number__c: 2,
      Mode__c: "Truckload",
      Cost__c: 2000,
      Margin__c: 25,
      Sell__c: 2500,
      Sell_Source__c: "Manual",
      Shipments_Per_Year__c: 10,
      CurrencyIsoCode: "USD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: true,
      Hist_Status__c: "Done"
    },
    {
      Id: "3",
      Row_Number__c: 3,
      Mode__c: "",
      Cost__c: null,
      Sell__c: null,
      Shipments_Per_Year__c: 4,
      CurrencyIsoCode: "CAD",
      Origin_Resolved__c: true,
      Destination_Resolved__c: false,
      Hist_Status__c: "No match"
    }
  ];
  const raw = lanes.map((l) => ({
    Id: l.Id,
    Raw_Row__c: JSON.stringify({ Lane: l.Id })
  }));

  it("adds Annual sell and Sell source after Sell", () => {
    const { lanes: sheet } = buildSheets(lanes, raw, {});
    const header = sheet[0];
    expect(
      header.slice(header.indexOf("Sell"), header.indexOf("Sell") + 3)
    ).toEqual(["Sell", "Annual sell", "Sell source"]);
    const row = (i) =>
      Object.fromEntries(header.map((h, j) => [h, sheet[i][j]]));
    expect(row(1)["Annual sell"]).toBe(59800);
    expect(row(1)["Sell source"]).toBe("Margin");
    expect(row(2)["Sell source"]).toBe("Manual");
    expect(row(3)["Annual sell"]).toBe("");
    expect(row(3)["Sell source"]).toBe("");
  });

  it("builds the summary sheet", () => {
    const { summary } = buildSheets(lanes, raw, {});
    expect(summary).toEqual([
      ["Lanes", 3],
      ["Priced lanes", 2],
      ["Unpriced lanes", 1],
      ["No history match", 1],
      ["Unresolved ends", 1],
      ["Total annual sell (CAD)", 59800],
      ["Total annual sell (USD)", 25000],
      ["Average margin %", 20],
      [],
      ["Mode", "Lanes", "Priced", "Annual sell"],
      ["Truckload", 2, 2, 84800],
      ["(none)", 1, 0, 0]
    ]);
  });
});
