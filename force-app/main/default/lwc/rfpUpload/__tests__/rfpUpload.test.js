jest.mock(
  "@salesforce/apex/RfpProjectController.attachFile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

// c/rfpSheet sniffs the CSV encoding with TextDecoder, which jsdom lacks and
// both the browser and LWS provide.
global.TextDecoder = require("util").TextDecoder;

// The SheetJS loader (c/rfpSheetLoader) caches its load promise in module scope,
// so every test takes a fresh copy of the module graph — and an unused loadScript
// mock — instead of inheriting whatever the test before it left cached.
//
// rfpUpload.html now mounts a real c/helpHint custom element, and jsdom's custom
// element registry is a single, file-wide instance that the LWC engine cannot
// re-register a tag name against. A full jest.resetModules() would reload
// "lwc" itself, giving each test its own empty upgradable-constructor cache and
// making the second and later mounts of <c-help-hint> collide with the first
// engine's registration. jest.isolateModules() keeps "lwc" pinned to the one
// instance loaded below (so the constructor cache — and its "c-help-hint" and
// "c-rfp-upload" entries — carries across tests) while still giving every test
// its own fresh copy of c/rfpUpload, c/rfpSheetLoader and the apex/loadScript
// mocks.
const lwc = require("lwc");
const { createElement } = lwc;
let RfpUpload;
let loadScript;
let attachFile;
const tagName = "c-rfp-upload";

function freshModules() {
  jest.isolateModules(() => {
    jest.doMock("lwc", () => lwc);
    RfpUpload = require("c/rfpUpload").default;
    ({ loadScript } = require("lightning/platformResourceLoader"));
    attachFile =
      require("@salesforce/apex/RfpProjectController.attachFile").default;
  });
}

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount(projectId) {
  const el = createElement(tagName, { is: RfpUpload });
  el.projectId = projectId;
  document.body.appendChild(el);
  return el;
}

// jsdom's File has no working arrayBuffer() and FileReader completes on a
// macrotask the microtask-only flush() below cannot wait for, so tests stub
// arrayBuffer() directly on the File instance (see task-6-report.md).
function fileWithBuffer(bytes, name) {
  const file = new File([new Uint8Array(bytes)], name);
  file.arrayBuffer = jest.fn().mockResolvedValue(new Uint8Array(bytes).buffer);
  return file;
}

const WB = { SheetNames: ["Sheet1"], Sheets: { Sheet1: {} } };
const AOA = [
  ["From", "To"],
  ["Montreal", "Toronto"]
];

describe("c-rfp-upload", () => {
  beforeEach(() => {
    freshModules();
    window.XLSX = {
      read: jest.fn(() => WB),
      utils: { sheet_to_json: jest.fn(() => AOA) }
    };
    attachFile.mockResolvedValue("069x");
  });

  afterEach(() => {
    delete window.XLSX;
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("parses a chosen file, attaches it and emits the rows", async () => {
    const el = mount("a0P1");
    const parsed = jest.fn();
    el.addEventListener("parsed", parsed);
    const input = el.shadowRoot.querySelector('input[type="file"]');
    const file = fileWithBuffer([1, 2, 3], "lanes.xlsx");
    Object.defineProperty(input, "files", { value: [file] });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(attachFile).toHaveBeenCalledWith(
      expect.objectContaining({ projectId: "a0P1", fileName: "lanes.xlsx" })
    );
    expect(parsed.mock.calls[0][0].detail.headers).toEqual(["From", "To"]);
    expect(parsed.mock.calls[0][0].detail.rows.length).toBe(1);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
  });

  it("keeps a good parse when the file cannot be attached", async () => {
    attachFile.mockRejectedValue({ body: { message: "storage limit" } });
    const el = mount("a0P1");
    const parsed = jest.fn();
    el.addEventListener("parsed", parsed);
    const input = el.shadowRoot.querySelector('input[type="file"]');
    Object.defineProperty(input, "files", {
      value: [fileWithBuffer([1, 2, 3], "lanes.xlsx")]
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();

    // The rows are dispatched before the attach is even attempted, so a failed
    // attach costs a warning and nothing else.
    expect(parsed).toHaveBeenCalledTimes(1);
    expect(parsed.mock.calls[0][0].detail.rows.length).toBe(1);
    const error = el.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toContain("could not be attached to the project");
    expect(error.textContent).toContain("storage limit");
    expect(
      el.shadowRoot.querySelector('[data-id="status"]').textContent
    ).toContain("lanes.xlsx: 1 rows");
  });

  it("reads a BOM-less UTF-8 CSV as codepage 65001", async () => {
    const el = mount("a0P1");
    const input = el.shadowRoot.querySelector('input[type="file"]');
    // "Rivi<e-grave>res" in UTF-8: SheetJS would otherwise decode it as 1252.
    const file = fileWithBuffer(
      [0x52, 0x69, 0x76, 0x69, 0xc3, 0xa8, 0x72, 0x65, 0x73],
      "lanes.csv"
    );
    Object.defineProperty(input, "files", { value: [file] });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(window.XLSX.read.mock.calls[0][1]).toEqual({
      type: "array",
      codepage: 65001
    });
  });

  it("reads a Windows-1252 CSV as codepage 1252", async () => {
    const el = mount("a0P1");
    const input = el.shadowRoot.querySelector('input[type="file"]');
    const file = fileWithBuffer(
      [0x52, 0x69, 0x76, 0x69, 0xe8, 0x72, 0x65, 0x73],
      "LANES.CSV"
    );
    Object.defineProperty(input, "files", { value: [file] });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(window.XLSX.read.mock.calls[0][1]).toEqual({
      type: "array",
      codepage: 1252
    });
  });

  it("asks for no codepage on a workbook, which carries its own encoding", async () => {
    const el = mount("a0P1");
    const input = el.shadowRoot.querySelector('input[type="file"]');
    Object.defineProperty(input, "files", {
      value: [fileWithBuffer([1, 2, 3], "lanes.xlsx")]
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(window.XLSX.read.mock.calls[0][1]).toEqual({ type: "array" });
  });

  it("refuses a file over 3 MB without calling Apex", async () => {
    const el = mount("a0P1");
    const input = el.shadowRoot.querySelector('input[type="file"]');
    Object.defineProperty(input, "files", {
      value: [{ name: "big.xlsx", size: 3 * 1024 * 1024 + 1 }]
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      el.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("3 MB");
    expect(attachFile).not.toHaveBeenCalled();
    expect(input.value).toBe("");
  });

  it("retries loading sheetjs after a failed load attempt", async () => {
    delete window.XLSX;
    loadScript.mockRejectedValueOnce(new Error("network down"));
    loadScript.mockImplementationOnce(() => {
      window.XLSX = {
        read: jest.fn(() => WB),
        utils: { sheet_to_json: jest.fn(() => AOA) }
      };
      return Promise.resolve();
    });
    const el = mount("a0P1");
    const input = el.shadowRoot.querySelector('input[type="file"]');

    Object.defineProperty(input, "files", {
      value: [fileWithBuffer([1, 2, 3], "lanes.xlsx")],
      configurable: true
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(loadScript).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();

    Object.defineProperty(input, "files", {
      value: [fileWithBuffer([1, 2, 3], "lanes2.xlsx")],
      configurable: true
    });
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();
    await flush();
    expect(loadScript).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
  });
});
