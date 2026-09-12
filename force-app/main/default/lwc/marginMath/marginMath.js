export function parseMargin(text) {
  if (text === null || text === undefined) return null;
  const cleaned = String(text).replace("%", "").trim();
  if (cleaned === "") return null;
  const n = Number(cleaned);
  if (!Number.isFinite(n) || n < 0 || n > 100) return null;
  return n;
}

export function suggestedSell(cost, marginPct) {
  if (typeof cost !== "number" || !(cost > 0)) return null;
  if (typeof marginPct !== "number" || !Number.isFinite(marginPct)) return null;
  return Math.round(cost * (1 + marginPct / 100) * 100) / 100;
}

/** Half-up on the absolute value, so -12.345 rounds to -12.35 like Apex HALF_UP. */
export function marginFor(cost, sell) {
  if (typeof cost !== "number" || !(cost > 0)) return null;
  if (typeof sell !== "number" || !Number.isFinite(sell)) return null;
  const raw = (sell / cost - 1) * 100;
  const rounded = Math.round(Math.abs(raw) * 100) / 100;
  const m = raw < 0 ? -rounded : rounded;
  if (Math.abs(m) > 999.99) return null;
  return m === 0 ? 0 : m;
}
