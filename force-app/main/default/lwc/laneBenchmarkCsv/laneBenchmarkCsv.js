function cell(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") return String(value);
  // Neutralize CSV/spreadsheet formula injection: a leading =, +, -, @, tab or CR
  // makes some spreadsheet apps evaluate the cell as a formula. Escaping with a
  // leading single quote (RFC 4180 quoting still applies after this) defuses that
  // without changing what a human sees when the cell is opened as text.
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function valueAt(row, field) {
  return field
    .split(".")
    .reduce((v, key) => (v === null || v === undefined ? v : v[key]), row);
}

export function toCsv(rows, columns) {
  const header = columns.map((c) => cell(c.label)).join(",");
  const body = rows.map((r) =>
    columns.map((c) => cell(valueAt(r, c.field))).join(",")
  );
  // eslint-disable-next-line no-irregular-whitespace
  return `﻿${[header, ...body].join("\r\n")}`;
}

export function slug(label) {
  const s = String(label || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return s || "any";
}

export function fileName(originLabel, destinationLabel, date) {
  const d = date || new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  return `lane-benchmark-${slug(originLabel)}-${slug(destinationLabel)}-${ymd}.csv`;
}
