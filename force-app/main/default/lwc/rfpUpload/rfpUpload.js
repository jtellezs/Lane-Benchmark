import { LightningElement, api } from "lwc";
import attachFile from "@salesforce/apex/RfpProjectController.attachFile";
import { parse, csvCodepage, MAX_ROWS } from "c/rfpSheet";
import { ensureSheetJs } from "c/rfpSheetLoader";

const MAX_BYTES = 3 * 1024 * 1024;
/** Text files SheetJS decodes with a codepage rather than reading as a zip. */
const TEXT_FILE = /\.(csv|txt)$/i;

export default class RfpUpload extends LightningElement {
  @api projectId;
  status = "";
  error = null;

  get accept() {
    return ".xlsx,.xlsm,.xls,.csv";
  }

  async handleFile(event) {
    const input = event.target;
    const file = input.files && input.files[0];
    if (!file) return;
    this.error = null;
    try {
      if (file.size > MAX_BYTES) {
        this.error =
          "The file is larger than 3 MB. Split it and upload the parts.";
        return;
      }
      this.status = "Reading…";
      const buffer = await this.readBuffer(file);
      await ensureSheetJs(this);
      const bytes = new Uint8Array(buffer);
      const workbook = window.XLSX.read(bytes, this.readOptions(file, bytes));
      const { headers, rows } = parse(
        workbook,
        window.XLSX.utils.sheet_to_json
      );
      if (rows.length > MAX_ROWS) {
        throw new Error("Split the file; the workbench handles 2,000 lanes");
      }
      // The rows go out first: a good parse is the point of the upload, and an
      // attach that fails (a storage limit, a file-permission error) must not
      // throw it away — the file is a convenience copy on the project record.
      this.status = `${file.name}: ${rows.length} rows`;
      this.dispatchEvent(
        new CustomEvent("parsed", {
          detail: { fileName: file.name, headers, rows }
        })
      );
      await this.attach(file.name, buffer);
    } catch (e) {
      this.status = "";
      this.error =
        e?.body?.message || e?.message || "The file could not be read.";
    } finally {
      // Reset so choosing the same file again still fires a change event.
      input.value = "";
    }
  }

  /**
   * Files the project keeps a copy of. A failure here is reported as a warning
   * and never rethrown, so the rows already on their way to the mapper stand.
   */
  async attach(fileName, buffer) {
    try {
      await attachFile({
        projectId: this.projectId,
        fileName,
        base64: toBase64(buffer)
      });
    } catch (e) {
      const why =
        e?.body?.message || e?.message || "the upload was not accepted.";
      this.error = `The file was read but could not be attached to the project: ${why}`;
    }
  }

  /**
   * A CSV has no encoding of its own, so SheetJS falls back to Windows-1252 and
   * mangles UTF-8 accents; the bytes are sniffed instead. Workbooks carry their
   * own encoding, so they are read exactly as before.
   */
  readOptions(file, bytes) {
    const options = { type: "array" };
    if (TEXT_FILE.test(file.name || "")) {
      options.codepage = csvCodepage(bytes);
    }
    return options;
  }

  readBuffer(file) {
    if (typeof file.arrayBuffer === "function") return file.arrayBuffer();
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new Error("The file could not be read."));
      reader.readAsArrayBuffer(file);
    });
  }
}

function toBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return window.btoa(binary);
}
