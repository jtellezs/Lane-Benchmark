import { createElement } from "lwc";
import RfpLaneTemplate from "c/rfpLaneTemplate";
import { TARGETS } from "c/rfpHeaderGuess";

jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount() {
  const el = createElement("c-rfp-lane-template", { is: RfpLaneTemplate });
  document.body.appendChild(el);
  return el;
}

describe("c-rfp-lane-template", () => {
  let aoa;

  beforeEach(() => {
    aoa = jest.fn(() => ({}));
    window.XLSX = {
      utils: {
        book_new: jest.fn(() => ({})),
        aoa_to_sheet: aoa,
        book_append_sheet: jest.fn()
      },
      write: jest.fn(() => new Uint8Array([1]))
    };
    URL.createObjectURL = jest.fn(() => "blob:x");
    URL.revokeObjectURL = jest.fn();
  });

  afterEach(() => {
    delete window.XLSX;
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("writes a sheet whose headers are the mapper's own labels", async () => {
    const el = mount();
    el.shadowRoot.querySelector('[data-id="template"]').click();
    await flush();
    await flush();
    const rows = aoa.mock.calls[0][0];
    // the guesser matches these strings, so a file filled in from the template needs no mapping
    expect(rows[0]).toEqual(TARGETS.map((t) => t.label));
    expect(rows[0]).toContain("Origin city");
    expect(rows[0]).toContain("Equipment type");
    // headers only: an example row would import as a real lane, not be skipped
    expect(rows).toHaveLength(1);
    expect(URL.createObjectURL).toHaveBeenCalled();
  });

  it("says so when the workbook cannot be built rather than failing silently", async () => {
    window.XLSX.utils.book_new = jest.fn(() => {
      throw new Error("sheetjs is unavailable");
    });
    const el = mount();
    el.shadowRoot.querySelector('[data-id="template"]').click();
    await flush();
    await flush();
    expect(
      el.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("sheetjs is unavailable");
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });

  it("takes a label so the page can name it in context", () => {
    const el = mount();
    el.label = "Download lane template";
    return Promise.resolve().then(() => {
      expect(el.shadowRoot.querySelector('[data-id="template"]').label).toBe(
        "Download lane template"
      );
    });
  });
});
