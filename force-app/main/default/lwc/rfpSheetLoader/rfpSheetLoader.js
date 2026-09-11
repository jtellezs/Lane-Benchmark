import { loadScript } from "lightning/platformResourceLoader";
import sheetJs from "@salesforce/resourceUrl/sheetJs";

/**
 * The in-flight (or finished) load, shared by every component that needs SheetJS
 * so the upload and the export never fetch the static resource twice. A failed
 * load clears it, so the next attempt retries instead of replaying the rejection.
 */
let loading = null;

/** Resolves once `window.XLSX` is available; `component` is the caller, for loadScript. */
export function ensureSheetJs(component) {
  if (window.XLSX) {
    return Promise.resolve();
  }
  if (!loading) {
    loading = loadScript(component, sheetJs).catch((e) => {
      loading = null;
      throw e;
    });
  }
  return loading;
}
