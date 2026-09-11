import { parse, toImportRows, csvCodepage, MAX_ROWS } from "c/rfpSheet";

// jsdom has no TextDecoder of its own; the browser and LWS both do.
global.TextDecoder = require("util").TextDecoder;

const wb = (aoa) => ({ SheetNames: ["Lanes"], Sheets: { Lanes: aoa } });
const sheetToJson = (ws) => ws;

describe("rfpSheet", () => {
  it("parses headers and rows, dropping empty trailing rows", () => {
    const { headers, rows } = parse(
      wb([
        [],
        ["From", "To", "Qty"],
        ["Montreal", "Toronto", "2"],
        ["", "", ""]
      ]),
      sheetToJson
    );
    expect(headers).toEqual(["From", "To", "Qty"]);
    expect(rows).toEqual([["Montreal", "Toronto", "2"]]);
  });
  it("throws on an empty sheet", () => {
    expect(() => parse(wb([]), sheetToJson)).toThrow("empty");
  });
  it("builds import rows with nested ends, numbers and flags", () => {
    const rows = toImportRows(
      ["From", "From ST", "To", "Qty", "FSC incl", "Haz"],
      [["Montreal", "QC", "Toronto", "2.5", "Yes", "x"]],
      {
        originCity: "From",
        originProvince: "From ST",
        destinationCity: "To",
        quantity: "Qty",
        fscIncluded: "FSC incl",
        hazmat: "Haz"
      }
    );
    expect(rows[0]).toEqual({
      rowNumber: 1,
      origin: { city: "Montreal", province: "QC", country: "", postal: "" },
      destination: { city: "Toronto", province: "", country: "", postal: "" },
      mode: "",
      equipmentCategory: "",
      equipmentType: "",
      commodity: "",
      quantity: 2.5,
      quantityUnit: "",
      shipmentsPerYear: null,
      fuelSurcharge: null,
      fscIncluded: true,
      hazmat: true,
      raw: JSON.stringify({
        From: "Montreal",
        "From ST": "QC",
        To: "Toronto",
        Qty: "2.5",
        "FSC incl": "Yes",
        Haz: "x"
      })
    });
    expect(MAX_ROWS).toBe(2000);
  });

  // "Trois-Rivieres" with an e-grave, in each encoding. SheetJS reads a BOM-less
  // CSV as Windows-1252 unless it is told otherwise.
  const UTF8_BYTES = new Uint8Array([
    0x54, 0x72, 0x6f, 0x69, 0x73, 0x2d, 0x52, 0x69, 0x76, 0x69, 0xc3, 0xa8,
    0x72, 0x65, 0x73
  ]);
  const CP1252_BYTES = new Uint8Array([
    0x54, 0x72, 0x6f, 0x69, 0x73, 0x2d, 0x52, 0x69, 0x76, 0x69, 0xe8, 0x72,
    0x65, 0x73
  ]);

  it("reads UTF-8 bytes as codepage 65001", () => {
    expect(csvCodepage(UTF8_BYTES)).toBe(65001);
  });
  it("falls back to codepage 1252 for bytes that are not UTF-8", () => {
    expect(csvCodepage(CP1252_BYTES)).toBe(1252);
  });
  it("treats plain ASCII as UTF-8", () => {
    expect(csvCodepage(new Uint8Array([0x46, 0x72, 0x6f, 0x6d]))).toBe(65001);
  });
});
