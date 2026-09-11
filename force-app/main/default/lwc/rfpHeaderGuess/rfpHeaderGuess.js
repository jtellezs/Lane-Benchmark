export const TARGETS = [
  { key: "originCity", label: "Origin city" },
  { key: "originProvince", label: "Origin state/province" },
  { key: "originCountry", label: "Origin country" },
  { key: "originPostal", label: "Origin postal" },
  { key: "destinationCity", label: "Destination city" },
  { key: "destinationProvince", label: "Destination state/province" },
  { key: "destinationCountry", label: "Destination country" },
  { key: "destinationPostal", label: "Destination postal" },
  { key: "mode", label: "Mode" },
  { key: "equipmentCategory", label: "Equipment category" },
  { key: "equipmentType", label: "Equipment type" },
  { key: "commodity", label: "Commodity" },
  { key: "quantity", label: "Quantity" },
  { key: "quantityUnit", label: "Quantity unit" },
  { key: "shipmentsPerYear", label: "Shipments per year" },
  { key: "fuelSurcharge", label: "Fuel surcharge" },
  { key: "fscIncluded", label: "FSC included" },
  { key: "hazmat", label: "Hazmat" }
];

const ORIGIN = /^(origin|orig|o|from|pickup|pu|ship ?from|shipper)\b/;
const DEST = /^(destination|dest|d|to|delivery|del|ship ?to|consignee|cons)\b/;
const norm = (h) =>
  String(h || "")
    .toLowerCase()
    .replace(/[._-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

function endTarget(h, side) {
  const rest = h.replace(side === "origin" ? ORIGIN : DEST, "").trim();
  if (/^(city|town)?$/.test(rest) || /\bcity\b/.test(rest))
    return `${side}City`;
  if (/\b(state|province|prov|st)\b/.test(rest)) return `${side}Province`;
  if (/\bcountry\b/.test(rest)) return `${side}Country`;
  if (/\b(zip|postal|post code|postcode|pc)\b/.test(rest))
    return `${side}Postal`;
  return null;
}

function targetFor(header) {
  const h = norm(header);
  if (!h) return null;
  if (/^(fsc|fuel) (incl|included)/.test(h) || /^fsc included/.test(h))
    return "fscIncluded";
  if (/^(fsc|fuel surcharge|fuel)$/.test(h)) return "fuelSurcharge";
  if (/^haz/.test(h)) return "hazmat";
  if (/^(mode|service|transport mode)$/.test(h)) return "mode";
  if (/equipment category|equip category|category/.test(h))
    return "equipmentCategory";
  if (/^(equipment|equip|equipment type|trailer)$/.test(h))
    return "equipmentType";
  if (/^(commodity|product|goods)$/.test(h)) return "commodity";
  if (/^(qty|quantity|volume|pallets|weight)$/.test(h)) return "quantity";
  if (/^(unit|uom|qty unit|quantity unit)$/.test(h)) return "quantityUnit";
  if (/(annual|yearly|per year|shipments|loads)/.test(h))
    return "shipmentsPerYear";
  if (ORIGIN.test(h)) return endTarget(h, "origin");
  if (DEST.test(h)) return endTarget(h, "destination");
  return null;
}

export function guess(headers) {
  const mapping = {};
  (headers || []).forEach((header) => {
    const t = targetFor(header);
    if (t && !mapping[t]) mapping[t] = header;
  });
  return mapping;
}

export function missingRequired(mapping) {
  const m = mapping || {};
  if (m.originCity && m.destinationCity) return [];
  if (m.originPostal && m.destinationPostal) return [];
  const out = [];
  if (!m.originCity) out.push("originCity");
  if (!m.destinationCity) out.push("destinationCity");
  return out;
}
