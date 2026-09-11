export const MAX_ROWS = 2000;

const isEmptyRow = (r) => !r || r.every((c) => String(c ?? "").trim() === "");

export function parse(workbook, sheetToJson) {
  const name = workbook?.SheetNames?.[0];
  if (!name) throw new Error("The sheet is empty");
  const aoa =
    sheetToJson(workbook.Sheets[name], {
      header: 1,
      raw: false,
      defval: ""
    }) || [];
  const first = aoa.findIndex((r) => !isEmptyRow(r));
  if (first < 0) throw new Error("The sheet is empty");
  const headers = aoa[first].map((h) => String(h ?? "").trim());
  if (!headers.some((h) => h)) throw new Error("No header row");
  const rows = aoa
    .slice(first + 1)
    .map((r) => headers.map((_, i) => String(r?.[i] ?? "").trim()));
  while (rows.length && isEmptyRow(rows[rows.length - 1])) rows.pop();
  return { headers, rows };
}

const num = (v) => {
  const s = String(v ?? "").replace(/[$,\s]/g, "");
  if (s === "") return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
};
const flag = (v) =>
  /^(y|yes|true|1|x|incl|included)$/i.test(String(v ?? "").trim());

export function toImportRows(headers, rows, mapping, startRow = 1) {
  const idx = {};
  Object.keys(mapping || {}).forEach((k) => {
    const i = headers.indexOf(mapping[k]);
    if (i >= 0) idx[k] = i;
  });
  const pick = (r, k) => (k in idx ? String(r[idx[k]] ?? "").trim() : "");
  return rows.map((r, n) => {
    const raw = {};
    headers.forEach((h, i) => {
      if (h) raw[h] = r[i] ?? "";
    });
    const shipmentsPerYear = num(pick(r, "shipmentsPerYear"));
    return {
      rowNumber: startRow + n,
      origin: {
        city: pick(r, "originCity"),
        province: pick(r, "originProvince"),
        country: pick(r, "originCountry"),
        postal: pick(r, "originPostal")
      },
      destination: {
        city: pick(r, "destinationCity"),
        province: pick(r, "destinationProvince"),
        country: pick(r, "destinationCountry"),
        postal: pick(r, "destinationPostal")
      },
      mode: pick(r, "mode"),
      equipmentCategory: pick(r, "equipmentCategory"),
      equipmentType: pick(r, "equipmentType"),
      commodity: pick(r, "commodity"),
      quantity: num(pick(r, "quantity")),
      quantityUnit: pick(r, "quantityUnit"),
      shipmentsPerYear:
        shipmentsPerYear === null ? null : Math.round(shipmentsPerYear),
      fuelSurcharge: num(pick(r, "fuelSurcharge")),
      fscIncluded: flag(pick(r, "fscIncluded")),
      hazmat: flag(pick(r, "hazmat")),
      raw: JSON.stringify(raw)
    };
  });
}
