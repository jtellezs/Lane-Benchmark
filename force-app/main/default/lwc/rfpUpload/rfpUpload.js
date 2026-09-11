import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import sheetJs from "@salesforce/resourceUrl/sheetJs";
import attachFile from "@salesforce/apex/RfpProjectController.attachFile";
import { parse, MAX_ROWS } from "c/rfpSheet";

const MAX_BYTES = 3 * 1024 * 1024;

export default class RfpUpload extends LightningElement {
  @api projectId;
  status = "";
  error = null;
  sheetReady = null;

  get accept() {
    return ".xlsx,.xlsm,.xls,.csv";
  }

  async handleFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) return;
    this.error = null;
    if (file.size > MAX_BYTES) {
      this.error =
        "The file is larger than 3 MB. Split it and upload the parts.";
      return;
    }
    try {
      this.status = "Reading…";
      const buffer = await this.readBuffer(file);
      await this.ensureSheetJs();
      const workbook = window.XLSX.read(new Uint8Array(buffer), {
        type: "array"
      });
      const { headers, rows } = parse(
        workbook,
        window.XLSX.utils.sheet_to_json
      );
      if (rows.length > MAX_ROWS) {
        throw new Error("Split the file; the workbench handles 2,000 lanes");
      }
      this.status = "Attaching…";
      await attachFile({
        projectId: this.projectId,
        fileName: file.name,
        base64: toBase64(buffer)
      });
      this.status = `${file.name}: ${rows.length} rows`;
      this.dispatchEvent(
        new CustomEvent("parsed", {
          detail: { fileName: file.name, headers, rows }
        })
      );
    } catch (e) {
      this.status = "";
      this.error =
        e?.body?.message || e?.message || "The file could not be read.";
    }
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

  ensureSheetJs() {
    if (window.XLSX) return Promise.resolve();
    if (!this.sheetReady) this.sheetReady = loadScript(this, sheetJs);
    return this.sheetReady;
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
