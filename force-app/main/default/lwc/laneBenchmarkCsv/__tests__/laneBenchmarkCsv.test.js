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
  it("resolves a dotted field against a nested object", () => {
    const nestedColumns = [
      { label: "Origin", field: "origin" },
      { label: "Email", field: "carrier.contactEmail" }
    ];
    const csv = toCsv(
      [
        { origin: "Laval", carrier: { contactEmail: "jo@acme.test" } },
        { origin: "Laval", carrier: null }
      ],
      nestedColumns
    );
    const lines = csv.split("\r\n");
    expect(lines[1]).toBe("Laval,jo@acme.test");
    expect(lines[2]).toBe("Laval,");
  });
  it("neutralizes formula-injection prefixes but leaves numbers untouched", () => {
    const valueColumn = [{ label: "Value", field: "carrierName" }];
    expect(
      toCsv([{ carrierName: '=HYPERLINK("http://x")' }], valueColumn).split(
        "\r\n"
      )[1]
    ).toBe(`"'=HYPERLINK(""http://x"")"`);
    expect(toCsv([{ carrierName: "+1" }], valueColumn).split("\r\n")[1]).toBe(
      "'+1"
    );
    expect(toCsv([{ carrierName: "-1" }], valueColumn).split("\r\n")[1]).toBe(
      "'-1"
    );
    expect(toCsv([{ carrierName: "@x" }], valueColumn).split("\r\n")[1]).toBe(
      "'@x"
    );
    expect(
      toCsv(
        [{ carrierTotal: -5 }],
        [{ label: "Total", field: "carrierTotal" }]
      ).split("\r\n")[1]
    ).toBe("-5");
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
