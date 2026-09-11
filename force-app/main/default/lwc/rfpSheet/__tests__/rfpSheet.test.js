import { parse, toImportRows, MAX_ROWS } from "c/rfpSheet";

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
});
