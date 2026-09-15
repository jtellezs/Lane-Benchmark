import { createElement } from "lwc";
import Results from "c/laneBenchmarkResults";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const ROWS = [
  {
    quoteId: "q1",
    quoteName: "CQ-1",
    origin: "Montréal, Quebec",
    destination: "Toronto, Ontario",
    mode: "Truckload",
    equipment: "Dry Van 53'",
    carrierName: "Acme",
    contactName: "Jo Contact",
    carrier: {
      contactEmail: "jo@acme.test",
      contactPhone: "514-555-0100",
      risk: "Acceptable",
      loadCount: 42,
      attention: ""
    },
    currencyIsoCode: "CAD",
    carrierTotal: 1000,
    load: { loadId: "a0L000000000001", miles: 337.2 },
    quoteDate: "2026-09-01",
    createdDate: "2026-09-01T10:00:00.000Z",
    hazmat: false,
    accepted: true,
    loadStatus: "Delivered",
    opsComments: "Fast pickup"
  },
  {
    quoteId: "q2",
    quoteName: "CQ-2",
    origin: "Laval, Quebec",
    destination: "Toronto, Ontario",
    mode: "LTL",
    equipment: "Reefer 53'",
    carrierName: 'Beta "Cold"',
    contactName: null,
    carrier: {
      contactEmail: null,
      contactPhone: null,
      risk: "Moderate",
      loadCount: 3,
      attention: " THE CARRIER IS BLACK-LISTED "
    },
    currencyIsoCode: "USD",
    carrierTotal: 800,
    load: { loadId: "a0L000000000002", miles: null },
    quoteDate: "2026-08-30",
    createdDate: "2026-08-30T10:00:00.000Z",
    hazmat: true,
    accepted: false,
    loadStatus: "Quotes Received",
    opsComments: null
  },
  {
    quoteId: "b1",
    quoteName: "B-000001",
    origin: "Montréal, QC",
    destination: "Toronto, ON",
    mode: "Truckload",
    equipment: "Dry Van 53'",
    carrierName: "New Carrier Inc",
    contactName: "Sam Bid",
    carrier: {
      contactEmail: "sam@new.test",
      contactPhone: null,
      risk: null,
      loadCount: null,
      attention: ""
    },
    currencyIsoCode: "CAD",
    carrierTotal: 1200,
    load: { loadId: null, miles: null },
    quoteDate: "2026-09-10",
    createdDate: "2026-09-10T10:00:00.000Z",
    hazmat: false,
    accepted: null,
    loadStatus: "Bid",
    opsComments: null,
    bid: {
      rateId: "b1",
      expiresOn: "2026-10-10",
      status: "Active",
      transitDays: 2,
      fuelSurcharge: 100,
      fscIncluded: true
    }
  }
];

async function mount(rows = ROWS) {
  const el = createElement("c-lane-benchmark-results", { is: Results });
  el.rows = rows;
  el.originLabel = "Montréal, QC, CA";
  el.destinationLabel = "Toronto, ON, CA";
  document.body.appendChild(el);
  await flush();
  return el;
}

async function exportCsv(el) {
  const createUrl = jest.fn(() => "blob:x");
  global.URL.createObjectURL = createUrl;
  global.URL.revokeObjectURL = jest.fn();
  jest.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  jest.useFakeTimers();
  el.shadowRoot.querySelector('[data-id="export"]').click();
  await flush();
  jest.runOnlyPendingTimers();
  jest.useRealTimers();
  const blob = createUrl.mock.calls[0][0];
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });
}

describe("c-lane-benchmark-results", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("renders one row per quote with mode class and flags", async () => {
    const el = await mount();
    const rows = el.shadowRoot.querySelectorAll("tbody tr[data-index]");
    expect(rows.length).toBe(3);
    expect(rows[1].querySelector('[data-id="mode"]').className).toContain(
      "ltl-cell"
    );
    expect(rows[1].textContent).toContain("Hazmat");
    expect(rows[0].textContent).toContain("Accepted");
  });

  it("marks bid rows with a badge and their expiry instead of accepted/declined", async () => {
    const el = await mount();
    const rows = el.shadowRoot.querySelectorAll("tbody tr[data-index]");
    const bidRow = rows[2];
    expect(bidRow.querySelector('[data-id="bid-badge"]').textContent).toBe(
      "Bid"
    );
    expect(bidRow.querySelector('[data-id="flags"]').textContent).toContain(
      "Expires 2026-10-10"
    );
    expect(bidRow.querySelector('[data-id="flags"]').textContent).not.toContain(
      "Declined"
    );
    expect(rows[0].querySelector('[data-id="bid-badge"]')).toBeNull();
  });

  it("expands a row to show comments and opens/closes the carrier popup", async () => {
    const el = await mount();
    el.shadowRoot
      .querySelector('tbody tr[data-index="0"] [data-id="expand"]')
      .click();
    await flush();
    expect(
      el.shadowRoot.querySelector('tr[data-detail="0"]').textContent
    ).toContain("Fast pickup");
    el.shadowRoot
      .querySelector('tbody tr[data-index="1"] [data-id="carrier"]')
      .click();
    await flush();
    const dialog = el.shadowRoot.querySelector('section[role="dialog"]');
    expect(dialog).not.toBeNull();
    expect(dialog.textContent).toContain("BLACK-LISTED");
    expect(dialog.textContent).toContain("Moderate");
    dialog.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flush();
    expect(
      el.shadowRoot.querySelector('section[role="dialog"]')
    ).not.toBeNull();
    el.shadowRoot.querySelector('[data-id="close"]').click();
    await flush();
    expect(el.shadowRoot.querySelector('section[role="dialog"]')).toBeNull();
  });

  it("exports the visible rows as CSV", async () => {
    const el = await mount();
    const createUrl = jest.fn(() => "blob:x");
    const revoke = jest.fn();
    global.URL.createObjectURL = createUrl;
    global.URL.revokeObjectURL = revoke;
    const clicks = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    // handleExport defers URL.revokeObjectURL via setTimeout (Safari can drop the
    // download if the object URL is revoked synchronously); run that timer here.
    jest.useFakeTimers();
    el.shadowRoot.querySelector('[data-id="export"]').click();
    await flush();
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
    expect(createUrl).toHaveBeenCalledTimes(1);
    const blob = createUrl.mock.calls[0][0];
    expect(blob.size).toBeGreaterThan(0);
    // jsdom in this project has no global Response, so read the Blob via FileReader instead
    // (per the brief's fallback). FileReader/TextDecoder strips a leading UTF-8 BOM per the
    // WHATWG Encoding spec, so the BOM itself is covered by laneBenchmarkCsv's own toCsv tests
    // rather than re-asserted here.
    const textOf = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsText(blob);
    });
    expect(textOf.startsWith("Source,Origin,Destination,Carrier")).toBe(true);
    expect(textOf).toContain('"Beta ""Cold"""');
    expect(clicks).toHaveBeenCalledTimes(1);
    expect(revoke).toHaveBeenCalledWith("blob:x");
  });

  // The brief's illustrative assertions (`toMatch(/^"Source",/)`, `toContain('"Bid",')`)
  // assume every CSV cell is quoted. laneBenchmarkCsv's toCsv only quotes a cell that
  // contains a comma/quote/newline (see laneBenchmarkCsv.js), so plain values like
  // "Source", "Bid", "Load" and "Expires on" come through unquoted here; the
  // assertions below check for that actual, unquoted output instead.
  it("exports a Source column and the expiry", async () => {
    const el = await mount();
    const createUrl = jest.fn(() => "blob:x");
    const revoke = jest.fn();
    global.URL.createObjectURL = createUrl;
    global.URL.revokeObjectURL = revoke;
    jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    jest.useFakeTimers();
    el.shadowRoot.querySelector('[data-id="export"]').click();
    await flush();
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
    const blob = createUrl.mock.calls[0][0];
    const csv = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsText(blob);
    });
    const header = csv.split("\n")[0];
    expect(header.startsWith("Source,")).toBe(true);
    expect(csv).toContain("Bid,");
    expect(csv).toContain("Load,");
    expect(header.replace(/\r$/, "").endsWith("Expires on")).toBe(true);
  });

  it("shows nothing but a hint when there are no rows", async () => {
    const el = await mount([]);
    expect(el.shadowRoot.querySelectorAll("tbody tr[data-index]").length).toBe(
      0
    );
    expect(el.shadowRoot.querySelector('[data-id="export"]')).toBeNull();
    expect(el.shadowRoot.textContent).toContain(
      "No quotes match this lane and these filters."
    );
  });

  it("shows each load's miles, a dash for bids and loads without miles, and follows the unit", async () => {
    const el = await mount();
    const header = () =>
      el.shadowRoot
        .querySelector('[data-id="miles-header"]')
        .textContent.trim();
    const cells = () =>
      Array.from(
        el.shadowRoot.querySelectorAll('tbody tr[data-index] [data-id="miles"]')
      ).map((c) => c.textContent.trim());
    expect(header()).toBe("Miles");
    expect(cells()).toEqual(["337 mi", "—", "—"]);
    el.unit = "km";
    await flush();
    expect(header()).toBe("Km");
    expect(cells()).toEqual(["543 km", "—", "—"]);
  });

  it("exports raw miles right after the carrier total, blank for bids, whatever the unit", async () => {
    const el = await mount();
    el.unit = "km";
    await flush();
    const lines = (await exportCsv(el)).split("\r\n");
    expect(lines[0]).toContain("Carrier total,Miles,Quote date");
    expect(lines[1]).toContain(",CAD,1000,337.2,2026-09-01,");
    expect(lines[2]).toContain(",USD,800,,2026-08-30,");
    expect(lines[3]).toContain(",CAD,1200,,2026-09-10,");
  });
});
