import { LightningElement, api } from "lwc";
import attachFile from "@salesforce/apex/RfpProjectController.attachFile";
import { parse, csvCodepage, MAX_ROWS } from "c/rfpSheet";
import { ensureSheetJs } from "c/rfpSheetLoader";
import { TARGETS } from "c/rfpHeaderGuess";

const MAX_BYTES = 3 * 1024 * 1024;
/** Text files SheetJS decodes with a codepage rather than reading as a zip. */
const TEXT_FILE = /\.(csv|txt)$/i;
const XLSX_MIME = "application/octet-stream";
/** One filled row so the shape is obvious; it resolves to no place, so an upload skips it. */
const EXAMPLE = {
  originCity: "Toronto",
  originProvince: "ON",
  originCountry: "CA",
  destinationCity: "Montreal",
  destinationProvince: "QC",
  destinationCountry: "CA",
  mode: "Truckload",
  equipmentCategory: "Van",
  equipmentType: "Dry Van 53'",
  shipmentsPerYear: 12
};

export default class RfpUpload extends LightningElement {
  @api projectId;
  status = "";
  error = null;

  get accept() {
    return ".xlsx,.xlsm,.xls,.csv";
  }

  /**
   * An empty workbook whose headers are the column mapper's own labels, so a file filled in
   * from it maps without a single column to match by hand. One example row shows the shape and
   * is ignored on upload, because its origin and destination resolve to nothing.
   */
  async handleTemplate() {
    this.error = null;
    try {
      this.status = "Building the template…";
      await ensureSheetJs(this);
      const XLSX = window.XLSX;
      const headers = TARGETS.map((t) => t.label);
      const example = TARGETS.map((t) => EXAMPLE[t.key] ?? "");
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(
        book,
        XLSX.utils.aoa_to_sheet([headers, example]),
        "Lanes"
      );
      const out = XLSX.write(book, { bookType: "xlsx", type: "array" });
      this.download(new Blob([out], { type: XLSX_MIME }), "lane-template.xlsx");
    } catch (e) {
      this.error =
        e?.body?.message || e?.message || "The template could not be built.";
    } finally {
      this.status = "";
    }
  }

  /** Safari drops the download unless the anchor is in the document when it is clicked. */
  download(blob, name) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // Safari drops the download if the object URL is revoked before it has started.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 0);
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
