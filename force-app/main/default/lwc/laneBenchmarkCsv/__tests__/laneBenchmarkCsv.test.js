import { toCsv, fileName } from "c/laneBenchmarkCsv";

const columns = [
  { label: "Origin", field: "origin" },
  { label: "Carrier", field: "carrierName" },
  { label: "Total", field: "carrierTotal" }
];

describe("toCsv", () => {
  it("quotes commas, quotes and newlines, and starts with a BOM", () => {
    const csv = toCsv(
      [
        {
          origin: "Montréal, QC",
          carrierName: 'Acme "Fast" Inc',
          carrierTotal: 1000
        },
        { origin: "Laval", carrierName: "Line1\nLine2", carrierTotal: null }
      ],
      columns
    );
    const lines = csv.split("\r\n");
    expect(lines[0]).toBe("﻿Origin,Carrier,Total");
    expect(lines[1]).toBe('"Montréal, QC","Acme ""Fast"" Inc",1000');
    expect(lines[2]).toBe('Laval,"Line1\nLine2",');
  });
  it("handles an empty row list", () => {
    expect(toCsv([], columns)).toBe("﻿Origin,Carrier,Total");
  });
});

describe("fileName", () => {
  it("slugs labels and formats the date", () => {
    expect(
      fileName("Montréal, QC, CA", "Toronto, ON, CA", new Date(2026, 8, 9))
    ).toBe("lane-benchmark-montreal-qc-ca-toronto-on-ca-20260909.csv");
    expect(fileName("", null, new Date(2026, 0, 1))).toBe(
      "lane-benchmark-any-any-20260101.csv"
    );
  });
});
