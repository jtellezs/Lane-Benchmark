jest.mock(
  "@salesforce/apex/RfpProjectController.attachFile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

// The SheetJS loader (c/rfpSheetLoader) caches its load promise in module scope,
// so every test takes a fresh copy of the module graph — and an unused loadScript
// mock — instead of inheriting whatever the test before it left cached.
let createElement;
let RfpUpload;
let loadScript;
let attachFile;
// Resetting the module registry also makes a new LWC engine, and jsdom's custom
// element registry is global, so each test mounts under its own tag name rather
// than trying to re-upgrade one the previous engine already claimed.
let tagSeq = 0;
let tagName;

function freshModules() {
  jest.resetModules();
  ({ createElement } = require("lwc"));
  RfpUpload = require("c/rfpUpload").default;
  ({ loadScript } = require("lightning/platformResourceLoader"));
  attachFile =
    require("@salesforce/apex/RfpProjectController.attachFile").default;
  tagName = `c-rfp-upload-${tagSeq++}`;
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
