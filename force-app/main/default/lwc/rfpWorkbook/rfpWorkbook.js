import { slug } from "c/laneBenchmarkCsv";
import { KM_PER_MILE, perDistance } from "c/distanceUnit";

export const OUR_COLUMNS = [
  "Cost",
  "Currency",
  "Cost source",
  "Margin %",
  "Sell",
  "Annual sell",
  "Sell source",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Miles",
  "Km",
  "Miles source",
  "Route hours",
  "Cost per mile",
  "Sell per mile",
  "Bid carrier",
  "History bids",
  "Notes"
];
const BID_HEADER = [
  "Lane row",
  "Carrier",
  "Contact",
  "Email",
  "Phone",
  "Rate",
  "Currency",
  "Fuel surcharge",
  "FSC included",
  "Transit days",
  "Valid from",
  "Expires on",
  "Status",
  "Notes"
];

const cell = (v) => (v === null || v === undefined ? "" : v);
const yesNo = (b) => (b ? "Yes" : "No");

const isNum = (v) => typeof v === "number" && Number.isFinite(v);
function annualSell(l) {
  return isNum(l.Sell__c) && isNum(l.Shipments_Per_Year__c)
    ? Math.round(l.Sell__c * l.Shipments_Per_Year__c * 100) / 100
    : "";
}
function sellSource(l) {
  if (l.Sell__c === null || l.Sell__c === undefined) return "";
  return l.Sell_Source__c === "Manual" ? "Manual" : "Margin";
}
const priced = (l) => isNum(l.Cost__c);

/** Bid, History median, Manual or Split; blank while the lane has no cost. */
function costSource(l) {
  return l.Cost__c === null || l.Cost__c === undefined || l.Cost__c === ""
    ? ""
    : cell(l.Cost_Source__c);
}

/** An amount per mile, or "" while the lane has no such amount. */
function perMile(amount, miles) {
  return isNum(amount) ? cell(perDistance(amount, miles, "mi")) : "";
}

/**
 * Miles, Km, Miles source, Route hours, Cost per mile, Sell per mile. The file
 * always carries both units, whatever the page shows, and the rates are per
 * mile. A lane without miles still says why (No route, No coordinates).
 */
function tripCells(l) {
  const source = cell(l.Miles_Source__c);
  if (!(isNum(l.Miles__c) && l.Miles__c > 0)) {
    return ["", "", source, "", "", ""];
  }
  return [
    l.Miles__c,
    Math.round(l.Miles__c * KM_PER_MILE * 10) / 10,
    source,
    cell(l.Route_Hours__c),
    perMile(l.Cost__c, l.Miles__c),
    perMile(l.Sell__c, l.Miles__c)
  ];
}

function summarySheet(ordered) {
  const rows = [
    ["Lanes", ordered.length],
    ["Priced lanes", ordered.filter(priced).length],
    ["Unpriced lanes", ordered.filter((l) => !priced(l)).length],
    [
      "No history match",
      ordered.filter((l) => l.Hist_Status__c === "No match").length
    ],
    [
      "Unresolved ends",
      ordered.filter((l) => !l.Origin_Resolved__c || !l.Destination_Resolved__c)
        .length
    ]
  ];
  const byCurrency = {};
  ordered.forEach((l) => {
    const a = annualSell(l);
    if (a !== "") {
      byCurrency[l.CurrencyIsoCode] = (byCurrency[l.CurrencyIsoCode] || 0) + a;
    }
  });
  Object.keys(byCurrency)
    .sort()
    .forEach((c) =>
      rows.push([
        `Total annual sell (${c})`,
        Math.round(byCurrency[c] * 100) / 100
      ])
    );
  const margins = ordered
    .filter((l) => priced(l) && isNum(l.Margin__c))
    .map((l) => l.Margin__c);
  rows.push([
    "Average margin %",
    margins.length
      ? Math.round(
          (margins.reduce((s, m) => s + m, 0) / margins.length) * 100
        ) / 100
      : ""
  ]);
  rows.push([]);
  rows.push(["Mode", "Lanes", "Priced", "Annual sell"]);
  const modes = {};
  ordered.forEach((l) => {
    const key = l.Mode__c || "(none)";
    const m = modes[key] || (modes[key] = { lanes: 0, priced: 0, annual: 0 });
    m.lanes++;
    if (priced(l)) m.priced++;
    const a = annualSell(l);
    if (a !== "") m.annual += a;
  });
  Object.keys(modes).forEach((k) =>
    rows.push([
      k,
      modes[k].lanes,
      modes[k].priced,
      Math.round(modes[k].annual * 100) / 100
    ])
  );
  return rows;
}

export function buildSheets(lanes, rawRows, bidsByLaneId) {
  const rawById = {};
  (rawRows || []).forEach((r) => {
    try {
      rawById[r.Id] = JSON.parse(r.Raw_Row__c || "{}");
    } catch {
      rawById[r.Id] = {};
    }
  });
  const ordered = [...(lanes || [])].sort(
    (a, b) => (a.Row_Number__c || 0) - (b.Row_Number__c || 0)
  );
  const headers = [];
  ordered.forEach((l) =>
    Object.keys(rawById[l.Id] || {}).forEach((h) => {
      if (!headers.includes(h)) headers.push(h);
    })
  );
  const laneSheet = [[...headers, ...OUR_COLUMNS]];
  const bidSheet = [BID_HEADER];
  ordered.forEach((l) => {
    const raw = rawById[l.Id] || {};
    const best = (bidsByLaneId?.[l.Id] || []).find(
      (b) => b.Id === l.Selected_Bid__c
    );
    laneSheet.push([
      ...headers.map((h) => cell(raw[h])),
      cell(l.Cost__c),
      l.Cost__c === null || l.Cost__c === undefined
        ? ""
        : cell(l.CurrencyIsoCode),
      costSource(l),
      cell(l.Margin__c),
      cell(l.Sell__c),
      annualSell(l),
      sellSource(l),
      cell(best?.Fuel_Surcharge__c),
      best ? yesNo(best.FSC_Included__c) : "",
      cell(best?.Transit_Days__c),
      ...tripCells(l),
      cell(l.Selected_Bid__r?.Carrier_Display__c),
      cell(l.Hist_Bid_Count__c),
      cell(l.Notes__c)
    ]);
    (bidsByLaneId?.[l.Id] || []).forEach((b) => {
      bidSheet.push([
        l.Row_Number__c,
        cell(b.Carrier_Display__c),
        cell(b.Contact_Name__c),
        cell(b.Contact_Email__c),
        cell(b.Contact_Phone__c),
        cell(b.Rate__c),
        cell(b.CurrencyIsoCode),
        cell(b.Fuel_Surcharge__c),
        yesNo(b.FSC_Included__c),
        cell(b.Transit_Days__c),
        cell(b.Valid_From__c),
        cell(b.Expires_On__c),
        cell(b.Status__c),
        cell(b.Notes__c)
      ]);
    });
  });
  return { lanes: laneSheet, bids: bidSheet, summary: summarySheet(ordered) };
}

export function exportFileName(customerName, projectName, date) {
  const d = date || new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  return `${slug(customerName)}-${slug(projectName)}-${ymd}.xlsx`;
}
