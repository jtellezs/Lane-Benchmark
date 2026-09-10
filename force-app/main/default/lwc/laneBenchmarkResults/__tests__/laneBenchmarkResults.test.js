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
    quoteDate: "2026-08-30",
    createdDate: "2026-08-30T10:00:00.000Z",
    hazmat: true,
    accepted: false,
    loadStatus: "Quotes Received",
    opsComments: null
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

describe("c-lane-benchmark-results", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.restoreAllMocks();
  });

  it("renders one row per quote with mode class and flags", async () => {
    const el = await mount();
    const rows = el.shadowRoot.querySelectorAll("tbody tr[data-index]");
    expect(rows.length).toBe(2);
    expect(rows[1].querySelector('[data-id="mode"]').className).toContain(
      "ltl-cell"
    );
    expect(rows[1].textContent).toContain("Hazmat");
    expect(rows[0].textContent).toContain("Accepted");
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
    expect(textOf.startsWith("Origin,Destination,Carrier")).toBe(true);
    expect(textOf).toContain('"Beta ""Cold"""');
    expect(clicks).toHaveBeenCalledTimes(1);
    expect(revoke).toHaveBeenCalledWith("blob:x");
  });

  it("shows nothing but a hint when there are no rows", async () => {
    const el = await mount([]);
    expect(el.shadowRoot.querySelectorAll("tbody tr[data-index]").length).toBe(
      0
    );
    expect(el.shadowRoot.querySelector('[data-id="export"]')).toBeNull();
  });
});
