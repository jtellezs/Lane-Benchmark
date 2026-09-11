import { createElement } from "lwc";
import RfpExport from "c/rfpExport";
import getRawRows from "@salesforce/apex/RfpLaneController.getRawRows";

jest.mock(
  "@salesforce/apex/RfpLaneController.getRawRows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

const flush = () => Promise.resolve().then(() => Promise.resolve());

const PROJECT = {
  Id: "a0P1",
  Name: "Costco Q4",
  Customer__r: { Name: "Costco Wholesale" }
};

const LANES = [
  {
    Id: "a0L1",
    Row_Number__c: 1,
    Cost__c: 1200,
    CurrencyIsoCode: "CAD",
    Margin__c: 15,
    Sell__c: 1411.76,
    Selected_Bid__c: "a0B1"
  },
  { Id: "a0L2", Row_Number__c: 2 }
];

const rawPage = (count, from) =>
  Array.from({ length: count }, (_, i) => ({
    Id: `a0L${from + i}`,
    Row_Number__c: from + i,
    Raw_Row__c: JSON.stringify({ From: "Montreal", To: "Toronto" })
  }));

function mount(lanes = LANES, bidsByLaneId = {}) {
  const el = createElement("c-rfp-export", { is: RfpExport });
  el.project = PROJECT;
  el.lanes = lanes;
  el.bidsByLaneId = bidsByLaneId;
  document.body.appendChild(el);
  return el;
}

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

/** Clicks a button, drains the awaited Apex/loader promises and runs the deferred revoke. */
async function clickAndSettle(el, id) {
  field(el, id).click();
  // Chained rather than looped: the ESLint config forbids `await` inside a loop.
  await Array.from({ length: 8 }).reduce(
    (p) => p.then(flush),
    Promise.resolve()
  );
  jest.runOnlyPendingTimers();
}

describe("c-rfp-export", () => {
  let createUrl;
  let revoke;
  let clicks;
  let downloadName;

  beforeEach(() => {
    window.XLSX = {
      utils: {
        book_new: jest.fn(() => ({ Sheets: {}, SheetNames: [] })),
        aoa_to_sheet: jest.fn((aoa) => ({ aoa })),
        book_append_sheet: jest.fn()
      },
      write: jest.fn(() => new Uint8Array(2))
    };
    createUrl = jest.fn(() => "blob:x");
    revoke = jest.fn();
    global.URL.createObjectURL = createUrl;
    global.URL.revokeObjectURL = revoke;
    downloadName = null;
    clicks = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(function anchorClick() {
        downloadName = this.download;
      });
    // The download defers URL.revokeObjectURL through setTimeout (Safari can drop
    // the download if the object URL is revoked synchronously); run that timer.
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
    jest.clearAllMocks();
    delete window.XLSX;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("pages getRawRows 500 at a time and downloads the workbook", async () => {
    getRawRows
      .mockResolvedValueOnce(rawPage(500, 1))
      .mockResolvedValueOnce(rawPage(3, 501));
    const el = mount();
    await clickAndSettle(el, "export");

    expect(getRawRows).toHaveBeenCalledTimes(2);
    expect(getRawRows.mock.calls[0][0]).toEqual({
      projectId: "a0P1",
      offset: 0
    });
    expect(getRawRows.mock.calls[1][0]).toEqual({
      projectId: "a0P1",
      offset: 500
    });

    expect(
      window.XLSX.utils.book_append_sheet.mock.calls.map((c) => c[2])
    ).toEqual(["Lanes", "Bids"]);
    expect(window.XLSX.write.mock.calls[0][1]).toEqual({
      bookType: "xlsx",
      type: "array"
    });
    expect(createUrl).toHaveBeenCalledTimes(1);
    const blob = createUrl.mock.calls[0][0];
    expect(blob.type).toBe(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    expect(clicks).toHaveBeenCalledTimes(1);
    expect(downloadName).toMatch(/^costco-wholesale-costco-q4-\d{8}\.xlsx$/);
    expect(revoke).toHaveBeenCalledWith("blob:x");
  });

  it("stops paging when a single short page comes back", async () => {
    getRawRows.mockResolvedValueOnce(rawPage(2, 1));
    const el = mount();
    await clickAndSettle(el, "export");
    expect(getRawRows).toHaveBeenCalledTimes(1);
    expect(createUrl).toHaveBeenCalledTimes(1);
  });

  it("asks to confirm when no lane has a cost, then exports anyway", async () => {
    getRawRows.mockResolvedValue([]);
    const el = mount([{ Id: "a0L2", Row_Number__c: 2 }]);
    await clickAndSettle(el, "export");
    expect(getRawRows).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("No lane has a cost yet");
    expect(field(el, "export-anyway")).not.toBeNull();

    await clickAndSettle(el, "export-anyway");
    expect(getRawRows).toHaveBeenCalledTimes(1);
    expect(clicks).toHaveBeenCalledTimes(1);
  });

  it("shows the Apex message and downloads nothing when the rows fail", async () => {
    getRawRows.mockRejectedValue({ body: { message: "rows are gone" } });
    const el = mount();
    await clickAndSettle(el, "export");
    expect(field(el, "error").textContent).toContain("rows are gone");
    expect(createUrl).not.toHaveBeenCalled();
  });
});
