import { createElement } from "lwc";
import CarrierLeads from "c/carrierLeads";
import findCarrierLeads from "@salesforce/apex/CarrierLeadController.findCarrierLeads";

jest.mock(
  "@salesforce/apex/CarrierLeadController.findCarrierLeads",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());

const REQUEST = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "toronto|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});
const OTHER_REQUEST = JSON.stringify({
  originKey: "montreal|qc|ca",
  destinationKey: "ottawa|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});

const ACME = {
  carrierId: "001000000000001AAA",
  name: "Acme Transport",
  loadsMoved: 4,
  loadsQuoted: 9,
  lastSeen: "2026-07-30",
  sources: ["Quote", "Split leg"],
  blacklisted: false,
  canOpen: true
};
const FLETES = {
  carrierId: "001000000000002AAA",
  name: "Fletes Mex",
  loadsMoved: 0,
  loadsQuoted: 2,
  lastSeen: "2025-11-02",
  sources: ["Quote"],
  blacklisted: true,
  canOpen: false
};
/** A CarrierLeadResult as CarrierLeadController.findCarrierLeads returns it. */
const SAME_LANE = {
  leads: [ACME, FLETES],
  stage: "Same lane",
  stateLaneLabel: null,
  truncated: false
};

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const textOf = (el, id) => field(el, id).textContent.trim();
const rowsOf = (el) => el.shadowRoot.querySelectorAll('[data-id="lead-row"]');
const inRow = (row, id) => row.querySelector(`[data-id="${id}"]`);

async function mount(props = {}) {
  const el = createElement("c-carrier-leads", { is: CarrierLeads });
  Object.assign(el, { currencyCode: "CAD", requestJson: REQUEST, ...props });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-carrier-leads", () => {
  beforeEach(() => {
    findCarrierLeads.mockResolvedValue(SAME_LANE);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a spinner while it asks for the lane's carriers with attempt 0", async () => {
    findCarrierLeads.mockReturnValue(new Promise(() => {}));
    const el = await mount();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(findCarrierLeads).toHaveBeenCalledWith({
      requestJson: REQUEST,
      attempt: 0
    });
    expect(field(el, "leads-card").title).toBe("Carriers to ask");
    expect(field(el, "leads-loading")).not.toBeNull();
    expect(rowsOf(el).length).toBe(0);
    expect(field(el, "leads-empty")).toBeNull();
  });

  it("lists each carrier with its counts and sources, a link only when the account can be opened and a badge when blacklisted", async () => {
    const el = await mount();
    expect(field(el, "leads-loading")).toBeNull();
    expect(textOf(el, "leads-heading")).toBe(
      "No carrier rate on this lane in CAD. These carriers quoted or moved it before; amounts are not shown."
    );
    const rows = rowsOf(el);
    expect(rows.length).toBe(2);

    const link = inRow(rows[0], "lead-link");
    expect(link.textContent.trim()).toBe("Acme Transport");
    expect(link.getAttribute("href")).toBe(
      "/lightning/r/Account/001000000000001AAA/view"
    );
    expect(inRow(rows[0], "lead-name")).toBeNull();
    expect(inRow(rows[0], "lead-blacklisted")).toBeNull();
    expect(inRow(rows[0], "lead-counts").textContent.trim()).toBe(
      "4 moved · 9 quoted · last seen 2026-07-30"
    );
    expect(inRow(rows[0], "lead-sources").textContent.trim()).toBe(
      "Quote, Split leg"
    );

    // not readable by this user: the name as plain text, no link
    expect(inRow(rows[1], "lead-link")).toBeNull();
    expect(inRow(rows[1], "lead-name").textContent.trim()).toBe("Fletes Mex");
    expect(inRow(rows[1], "lead-blacklisted").textContent.trim()).toBe(
      "Blacklisted"
    );
    expect(inRow(rows[1], "lead-counts").textContent.trim()).toBe(
      "0 moved · 2 quoted · last seen 2025-11-02"
    );

    expect(field(el, "leads-stage2")).toBeNull();
    expect(field(el, "leads-empty")).toBeNull();
    expect(field(el, "leads-truncated")).toBeNull();
    expect(field(el, "leads-error")).toBeNull();
  });

  it("names no currency in the heading when the search had no currency filter", async () => {
    const el = await mount({ currencyCode: null });
    expect(textOf(el, "leads-heading")).toBe(
      "No carrier rate on this lane. These carriers quoted or moved it before; amounts are not shown."
    );
  });

  it("words a state lane answer as the top carriers on that lane", async () => {
    findCarrierLeads.mockResolvedValue({
      leads: [ACME],
      stage: "State lane",
      stateLaneLabel: "QC to ON",
      truncated: false
    });
    const el = await mount();
    expect(textOf(el, "leads-stage2")).toBe(
      "No carrier on this exact lane. Top carriers on QC to ON over the last year."
    );
    expect(field(el, "leads-heading")).toBeNull();
    expect(rowsOf(el).length).toBe(1);
  });

  it("says when no carrier was found, and when the list may be incomplete", async () => {
    findCarrierLeads.mockResolvedValue({
      leads: [],
      stage: "None",
      stateLaneLabel: null,
      truncated: true
    });
    const el = await mount();
    expect(textOf(el, "leads-empty")).toBe(
      "No carrier found on this lane or on its state or province lane."
    );
    expect(textOf(el, "leads-truncated")).toBe("The list may be incomplete.");
    expect(field(el, "leads-heading")).toBeNull();
    expect(field(el, "leads-stage2")).toBeNull();
    expect(rowsOf(el).length).toBe(0);
  });

  it("shows a failure with Retry, which asks again with the next attempt", async () => {
    findCarrierLeads
      .mockRejectedValueOnce({ body: { message: "Unknown place key" } })
      .mockRejectedValueOnce(new Error("Network down"))
      .mockResolvedValueOnce(SAME_LANE);
    const el = await mount();
    expect(textOf(el, "leads-error")).toBe("Unknown place key");
    expect(rowsOf(el).length).toBe(0);

    field(el, "leads-retry").click();
    await flush();
    expect(findCarrierLeads.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      attempt: 1
    });
    expect(textOf(el, "leads-error")).toBe(
      "The carriers to ask could not be loaded."
    );

    field(el, "leads-retry").click();
    await flush();
    expect(findCarrierLeads.mock.calls[2][0]).toEqual({
      requestJson: REQUEST,
      attempt: 2
    });
    expect(field(el, "leads-error")).toBeNull();
    expect(rowsOf(el).length).toBe(2);

    // another lane starts again from attempt 0, so it can use the cache
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(findCarrierLeads.mock.calls[3][0]).toEqual({
      requestJson: OTHER_REQUEST,
      attempt: 0
    });
  });

  it("drops an answer that lands after the request changed", async () => {
    let releaseFirst;
    findCarrierLeads
      .mockReturnValueOnce(
        new Promise((resolve) => {
          releaseFirst = resolve;
        })
      )
      .mockResolvedValueOnce({
        leads: [FLETES],
        stage: "State lane",
        stateLaneLabel: "QC to ON",
        truncated: false
      });
    const el = await mount();
    el.requestJson = OTHER_REQUEST;
    await flush();
    releaseFirst(SAME_LANE);
    await flush();
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(2);
    expect(findCarrierLeads.mock.calls[1][0].requestJson).toBe(OTHER_REQUEST);
    const rows = rowsOf(el);
    expect(rows.length).toBe(1);
    expect(inRow(rows[0], "lead-name").textContent.trim()).toBe("Fletes Mex");
    expect(field(el, "leads-stage2")).not.toBeNull();
  });

  it("asks again only when the request changes and is not blank", async () => {
    const el = await mount();
    el.requestJson = REQUEST;
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);

    el.requestJson = "";
    await flush();
    expect(findCarrierLeads).toHaveBeenCalledTimes(1);
    expect(rowsOf(el).length).toBe(0);
    expect(field(el, "leads-loading")).toBeNull();
  });
});
