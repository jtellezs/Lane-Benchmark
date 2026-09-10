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
