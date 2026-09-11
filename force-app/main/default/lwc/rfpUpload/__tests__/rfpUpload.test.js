import { createElement } from "lwc";
import RfpUpload from "c/rfpUpload";
import attachFile from "@salesforce/apex/RfpProjectController.attachFile";

jest.mock(
  "@salesforce/apex/RfpProjectController.attachFile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount(projectId) {
  const el = createElement("c-rfp-upload", { is: RfpUpload });
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
  });
});
