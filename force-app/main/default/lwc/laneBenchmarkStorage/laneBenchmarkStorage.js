export const STORAGE_KEY = "laneBenchmark.request.v1";

export function load() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (
    e // eslint-disable-line no-unused-vars
  ) {
    return null;
  }
}

export function save(request) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(request));
  } catch (
    e // eslint-disable-line no-unused-vars
  ) {
    // storage unavailable (private mode, quota): remembering filters is a convenience only
    return undefined;
  }
  return undefined;
}

export function clear() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch (
    e // eslint-disable-line no-unused-vars
  ) {
    // same as above
    return undefined;
  }
  return undefined;
}
