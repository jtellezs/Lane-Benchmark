export const UNIT_KEY = "tripMiles.unit.v1";
export const KM_PER_MILE = 1.609344;

const UNITS = ["mi", "km"];
const WHOLE = new Intl.NumberFormat("en-CA", { maximumFractionDigits: 0 });

function known(unit) {
  return unit === "km" ? "km" : "mi";
}

function toNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Half-up on the absolute value, like marginMath and Apex HALF_UP. */
function cents(value) {
  const rounded = Math.round(Math.abs(value) * 100) / 100;
  return value < 0 ? -rounded : rounded;
}

/** The unit this browser last chose; miles when nothing (or nothing usable) is stored. */
export function readUnit() {
  try {
    return known(window.localStorage.getItem(UNIT_KEY));
  } catch {
    return "mi";
  }
}

export function writeUnit(unit) {
  if (!UNITS.includes(unit)) {
    return;
  }
  try {
    window.localStorage.setItem(UNIT_KEY, unit);
  } catch {
    // private window or blocked storage: the choice just is not remembered
  }
}

/** "1,234 mi" or "1,986 km" from a distance in miles; "" when there is no distance. */
export function formatDistance(miles, unit) {
  const n = toNumber(miles);
  if (n === null) {
    return "";
  }
  const u = known(unit);
  const value = u === "km" ? n * KM_PER_MILE : n;
  return `${WHOLE.format(value)} ${u}`;
}

/** An amount per mile or per km, to the cent; null without a positive amount and distance. */
export function perDistance(amount, miles, unit) {
  const a = toNumber(amount);
  const m = toNumber(miles);
  if (a === null || m === null || !(a > 0) || !(m > 0)) {
    return null;
  }
  const distance = known(unit) === "km" ? m * KM_PER_MILE : m;
  return cents(a / distance);
}
