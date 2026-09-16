import { createElement } from "lwc";
import SplitLaneOptions from "c/splitLaneOptions";
import splitOptions from "@salesforce/apex/SplitLaneController.splitOptions";

jest.mock(
  "@salesforce/apex/SplitLaneController.splitOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve().then(() => Promise.resolve());
const settle = () => flush().then(flush);

const REQUEST = JSON.stringify({
  originKey: "general escobedo|nl|mx",
  destinationKey: "saint-augustin-de-desmaures|qc|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});
const OTHER_REQUEST = JSON.stringify({
  originKey: "monterrey|nl|mx",
  destinationKey: "toronto|on|ca",
  originPrecision: "CITY",
  destinationPrecision: "CITY"
});

/** The first search's statistics: a priced CAD median, no priced USD row. */
const STATS = {
  CAD: { count: 5, countNonZero: 3, median: 5980 },
  USD: { count: 2, countNonZero: 0, median: null }
};

const carrier = (carrierId, name, legsMoved, blacklisted = false) => ({
  carrierId,
  name,
  legsMoved,
  blacklisted
});
const leg = (position, laneLabel, carriers, median, pricedCount) => ({
  position,
  laneLabel,
  carriers,
  median,
  pricedCount
});

/** SplitLaneResult with one history group, as SplitLaneController.splitOptions returns it. */
const historyResult = (currencyCode, [leg1Median, leg2Median, total]) => ({
  currencyCode,
  rateStartDate: currencyCode === "USD" ? "2026-08-11" : null,
  truncated: false,
  message: null,
  options: [
    {
      kind: "History",
      handoffLabel: "Laredo, TX · SFMN Park ITC Laredo yard",
      shipments: 34,
      legs: [
        leg(
          1,
          "General Escobedo, NL → Laredo, TX",
          [
            carrier("001000000000001AAA", "Q Transportes", 18),
            carrier("001000000000002AAA", "Fletes Mex", 9, true)
          ],
          leg1Median,
          27
        ),
        leg(
          2,
          "Laredo, TX → Saint-Augustin-de-Desmaures, QC",
          [carrier("001000000000003AAA", "Nordic Lines", 34)],
          leg2Median,
          31
        )
      ],
      medianTotal: total,
      pricedShipments: 31,
      extraDistancePct: null
    }
  ]
});
const HISTORY_CAD = historyResult("CAD", [1248.4, 5190, 6453.25]);
const HISTORY_USD = historyResult("USD", [903.72, 3757.04, 4671.51]);

/** Two estimates: Laredo with both legs priced, San Diego with an empty first leg. */
const estimateResult = (currencyCode, [leg1Median, leg2Median, total]) => ({
  currencyCode,
  rateStartDate: currencyCode === "USD" ? "2026-08-11" : null,
  truncated: false,
  message: null,
  options: [
    {
      kind: "Estimate",
      handoffLabel: "Laredo, TX",
      shipments: 0,
      legs: [
        leg(
          1,
          "Monterrey, NL → Laredo, TX",
          [carrier("001000000000001AAA", "Q Transportes", 12)],
          leg1Median,
          12
        ),
        leg(
          2,
          "Laredo, TX → Toronto, ON",
          [carrier("001000000000004AAA", "Maple Freight", 40)],
          leg2Median,
          40
        )
      ],
      medianTotal: total,
      pricedShipments: 0,
      extraDistancePct: 6
    },
    {
      kind: "Estimate",
      handoffLabel: "San Diego, CA",
      shipments: 0,
      legs: [
        leg(1, "Monterrey, NL → San Diego, CA", [], null, 0),
        leg(
          2,
          "San Diego, CA → Toronto, ON",
          [carrier("001000000000005AAA", "Pacific Haul", 3, true)],
          2100,
          3
        )
      ],
      medianTotal: null,
      pricedShipments: 0,
      extraDistancePct: 9
    }
  ]
});
const ESTIMATE_CAD = estimateResult("CAD", [900.1, 1500, 2400.1]);
const ESTIMATE_USD = estimateResult("USD", [651.58, 1085.85, 1737.43]);

const ESTIMATE_TITLES = [
  "Estimate via Laredo, TX · +6 % distance",
  "Estimate via San Diego, CA · +9 % distance"
];

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const all = (el, id) => [
  ...el.shadowRoot.querySelectorAll(`[data-id="${id}"]`)
];
const texts = (el, id) => all(el, id).map((n) => n.textContent.trim());
const inOption = (option, id) => option.querySelector(`[data-id="${id}"]`);
/** A leg line's words, without the Blacklisted badges that sit beside carriers. */
const legText = (line) =>
  [...line.querySelectorAll(".leg-text")].map((n) => n.textContent).join("");

async function mount(props = {}) {
  const el = createElement("c-split-lane-options", { is: SplitLaneOptions });
  Object.assign(el, {
    requestJson: REQUEST,
    startCurrency: "CAD",
    laneCurrency: "CAD",
    statsByCurrency: STATS,
    allowUseAsCost: true,
    ...props
  });
  document.body.appendChild(el);
  await flush();
  return el;
}

async function open(el) {
  field(el, "split-open").click();
  await settle();
}

function typeHandoff(option, value) {
  const input = inOption(option, "handoff-cost");
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

describe("c-split-lane-options", () => {
  beforeEach(() => {
    splitOptions.mockImplementation(({ currencyCode }) =>
      Promise.resolve(currencyCode === "USD" ? HISTORY_USD : HISTORY_CAD)
    );
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows only the Split-lane options button until it is clicked, then asks for the start currency", async () => {
    let release;
    splitOptions.mockReturnValueOnce(
      new Promise((resolve) => {
        release = resolve;
      })
    );
    const el = await mount();
    expect(field(el, "split-open").label).toBe("Split-lane options");
    expect(field(el, "split-card")).toBeNull();
    // Direct first (D1): nothing is asked before the click.
    expect(splitOptions).not.toHaveBeenCalled();

    field(el, "split-open").click();
    await flush();
    expect(field(el, "split-open")).toBeNull();
    expect(field(el, "split-card").title).toBe("Split-lane options");
    expect(field(el, "split-loading")).not.toBeNull();
    expect(splitOptions).toHaveBeenCalledTimes(1);
    expect(splitOptions).toHaveBeenCalledWith({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });

    release(HISTORY_CAD);
    await settle();
    expect(field(el, "split-loading")).toBeNull();
    expect(all(el, "option").length).toBe(1);
  });

  it("starts in the start currency, asks each currency once and reuses the kept answer", async () => {
    const el = await mount({ startCurrency: "USD", laneCurrency: "USD" });
    await open(el);
    expect(splitOptions.mock.calls.map((c) => c[0].currencyCode)).toEqual([
      "USD"
    ]);
    const usd = field(el, "split-currency-usd");
    const cad = field(el, "split-currency-cad");
    expect(usd.getAttribute("aria-pressed")).toBe("true");
    expect(cad.getAttribute("aria-pressed")).toBe("false");
    expect(usd.className).toBe("slds-button slds-button_brand");
    expect(cad.className).toBe("slds-button slds-button_neutral");
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 4,672 USD (31 shipments)"
    ]);

    cad.click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });
    expect(cad.getAttribute("aria-pressed")).toBe("true");
    expect(usd.getAttribute("aria-pressed")).toBe("false");
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 6,453 CAD (31 shipments)"
    ]);

    usd.click();
    await settle();
    // The USD answer is kept: no third call.
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(texts(el, "option-total")).toEqual([
      "Total per shipment, median 4,672 USD (31 shipments)"
    ]);

    // The currency already shown asks nothing either.
    usd.click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
  });

  it("names the USD rate date in USD only", async () => {
    const el = await mount();
    await open(el);
    expect(field(el, "split-rate-note")).toBeNull();
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "split-rate-note").textContent.trim()).toBe(
      "Converted at the USD rate of 2026-08-11."
    );
  });

  it("titles a history group by its handoff and shipments, and an estimate by its extra distance", async () => {
    const history = await mount();
    await open(history);
    expect(texts(history, "option-title")).toEqual([
      "Via Laredo, TX · SFMN Park ITC Laredo yard · 34 shipments"
    ]);
    // Only an estimate takes a handoff cost.
    expect(field(history, "handoff-cost")).toBeNull();

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    const estimate = await mount({ requestJson: OTHER_REQUEST });
    await open(estimate);
    expect(texts(estimate, "option-title")).toEqual(ESTIMATE_TITLES);
    expect(all(estimate, "handoff-cost").map((i) => i.label)).toEqual([
      "Handoff cost (CAD)",
      "Handoff cost (CAD)"
    ]);
  });

  it("lists each leg's carriers with legs moved, a Blacklisted badge and the median when there is one", async () => {
    const el = await mount();
    await open(el);
    const lines = all(el, "leg-line");
    expect(lines.map(legText)).toEqual([
      "Leg 1 General Escobedo, NL → Laredo, TX · Q Transportes (18), Fletes Mex (9) · median 1,248 CAD",
      "Leg 2 Laredo, TX → Saint-Augustin-de-Desmaures, QC · Nordic Lines (34) · median 5,190 CAD"
    ]);
    const badges = all(el, "leg-blacklisted");
    expect(badges.length).toBe(1);
    expect(badges[0].textContent.trim()).toBe("Blacklisted");
    expect(lines[0].contains(badges[0])).toBe(true);
    // Beside the carrier it belongs to.
    expect(badges[0].previousElementSibling.textContent).toBe("Fletes Mex (9)");

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    el.requestJson = OTHER_REQUEST;
    await flush();
    await open(el);
    expect(all(el, "leg-line").map(legText)).toEqual([
      "Leg 1 Monterrey, NL → Laredo, TX · Q Transportes (12) · median 900 CAD",
      "Leg 2 Laredo, TX → Toronto, ON · Maple Freight (40) · median 1,500 CAD",
      "Leg 1 Monterrey, NL → San Diego, CA · no carrier found",
      "Leg 2 San Diego, CA → Toronto, ON · Pacific Haul (3) · median 2,100 CAD"
    ]);
    expect(all(el, "leg-blacklisted").length).toBe(1);
  });

  it("adds the typed handoff cost to an estimate: 0 counts, a blank or negative cost does not", async () => {
    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    const el = await mount();
    await open(el);
    const [laredo, sanDiego] = all(el, "option");
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    typeHandoff(laredo, "250");
    await flush();
    expect(inOption(laredo, "option-total").textContent.trim()).toBe(
      "Estimate total 2,650 CAD"
    );
    expect(inOption(laredo, "use-as-cost")).not.toBeNull();

    typeHandoff(laredo, "0");
    await flush();
    expect(inOption(laredo, "option-total").textContent.trim()).toBe(
      "Estimate total 2,400 CAD"
    );
    expect(inOption(laredo, "use-as-cost")).not.toBeNull();

    typeHandoff(laredo, "");
    await flush();
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    typeHandoff(laredo, "-5");
    await flush();
    expect(inOption(laredo, "option-total")).toBeNull();
    expect(inOption(laredo, "use-as-cost")).toBeNull();

    // A leg without a median leaves its estimate without a total, whatever is typed.
    typeHandoff(sanDiego, "100");
    await flush();
    expect(inOption(sanDiego, "option-total")).toBeNull();
    expect(inOption(sanDiego, "use-as-cost")).toBeNull();
  });

  it("sends the option's total, rounded to cents, with the card's currency on Use as cost", async () => {
    const el = await mount();
    const handler = jest.fn();
    el.addEventListener("useascost", handler);
    await open(el);
    // Every button reads "Use as cost"; its title names the option it uses.
    expect(inOption(all(el, "option")[0], "use-as-cost").title).toBe(
      "Use Via Laredo, TX · SFMN Park ITC Laredo yard as cost"
    );
    inOption(all(el, "option")[0], "use-as-cost").click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      cost: 6453.25,
      currencyCode: "CAD"
    });

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    el.requestJson = OTHER_REQUEST;
    await flush();
    await open(el);
    const laredo = all(el, "option")[0];
    typeHandoff(laredo, "99.999");
    await flush();
    expect(inOption(laredo, "use-as-cost").title).toBe(
      "Use Estimate via Laredo, TX as cost"
    );
    inOption(laredo, "use-as-cost").click();
    // 2400.10 + 99.999 = 2500.099, sent as 2500.10
    expect(handler.mock.calls[1][0].detail).toEqual({
      cost: 2500.1,
      currencyCode: "CAD"
    });
  });

  it("turns Use as cost off with a note while the card shows another currency than the lane's", async () => {
    const el = await mount();
    await open(el);
    expect(all(el, "use-as-cost").length).toBe(1);
    expect(field(el, "use-as-cost-off")).toBeNull();

    field(el, "split-currency-usd").click();
    await settle();
    expect(all(el, "use-as-cost").length).toBe(0);
    expect(field(el, "use-as-cost-off").textContent.trim()).toBe(
      "Switch to CAD to use a split cost."
    );

    field(el, "split-currency-cad").click();
    await settle();
    expect(all(el, "use-as-cost").length).toBe(1);
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("offers no Use as cost where the host does not allow it", async () => {
    // A CAD lane and a CAD answer with a total: only allowUseAsCost keeps the button away.
    splitOptions.mockResolvedValueOnce(HISTORY_CAD);
    const el = await mount({
      allowUseAsCost: false,
      startCurrency: "CAD",
      laneCurrency: "CAD"
    });
    await open(el);
    expect(all(el, "option").length).toBe(1);
    expect(field(el, "option-total")).not.toBeNull();
    expect(all(el, "use-as-cost").length).toBe(0);
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("clears a typed handoff cost when the currency switches", async () => {
    splitOptions.mockImplementation(({ currencyCode }) =>
      Promise.resolve(currencyCode === "USD" ? ESTIMATE_USD : ESTIMATE_CAD)
    );
    const el = await mount();
    await open(el);
    typeHandoff(all(el, "option")[0], "250");
    await flush();
    expect(texts(el, "option-total")).toEqual(["Estimate total 2,650 CAD"]);

    field(el, "split-currency-usd").click();
    await settle();
    expect(all(el, "handoff-cost").map((i) => i.value)).toEqual(["", ""]);
    expect(all(el, "handoff-cost")[0].label).toBe("Handoff cost (USD)");
    expect(field(el, "option-total")).toBeNull();

    field(el, "split-currency-cad").click();
    await settle();
    expect(all(el, "handoff-cost").map((i) => i.value)).toEqual(["", ""]);
    expect(field(el, "option-total")).toBeNull();
  });

  it("shows the first search's direct median in the card's currency, and nothing without one", async () => {
    const el = await mount();
    await open(el);
    expect(texts(el, "direct-median")).toEqual(["Direct median 5,980 CAD"]);
    field(el, "split-currency-usd").click();
    await settle();
    // The first search has no priced USD row.
    expect(all(el, "direct-median").length).toBe(0);

    // The lane panel's statistics are empty until its history search answers.
    const noStats = await mount({
      statsByCurrency: null,
      requestJson: OTHER_REQUEST
    });
    await open(noStats);
    expect(all(noStats, "option").length).toBe(1);
    expect(all(noStats, "direct-median").length).toBe(0);
  });

  it("shows the Apex message and retries with the next attempt", async () => {
    splitOptions.mockRejectedValueOnce({
      body: { message: "The lane could not be read right now." }
    });
    const el = await mount();
    await open(el);
    expect(field(el, "split-error").textContent.trim()).toBe(
      "The lane could not be read right now."
    );
    expect(field(el, "split-loading")).toBeNull();
    expect(all(el, "option").length).toBe(0);

    field(el, "split-retry").click();
    await settle();
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: REQUEST,
      currencyCode: "CAD",
      attempt: 1
    });
    expect(field(el, "split-error")).toBeNull();
    expect(field(el, "split-retry")).toBeNull();
    expect(all(el, "option").length).toBe(1);

    splitOptions.mockRejectedValueOnce(new Error("offline"));
    field(el, "split-currency-usd").click();
    await settle();
    expect(field(el, "split-error").textContent.trim()).toBe(
      "The split-lane options could not be loaded."
    );
  });

  it("shows the service message and the incomplete-list note", async () => {
    const message =
      "No split shipment on this lane in the last 12 months, and no handoff point is close enough for an estimate.";
    splitOptions.mockResolvedValueOnce({
      currencyCode: "CAD",
      rateStartDate: null,
      options: [],
      truncated: true,
      message
    });
    const el = await mount();
    await open(el);
    expect(field(el, "split-message").textContent.trim()).toBe(message);
    expect(field(el, "split-truncated").textContent.trim()).toBe(
      "The list may be incomplete."
    );
    expect(all(el, "option").length).toBe(0);
    expect(field(el, "use-as-cost-off")).toBeNull();
  });

  it("closes again for a new request and drops an answer that belongs to the old one", async () => {
    let release;
    splitOptions.mockReturnValueOnce(
      new Promise((resolve) => {
        release = resolve;
      })
    );
    const el = await mount();
    field(el, "split-open").click();
    await flush();
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(field(el, "split-card")).toBeNull();
    expect(field(el, "split-open")).not.toBeNull();

    splitOptions.mockResolvedValueOnce(ESTIMATE_CAD);
    await open(el);
    expect(splitOptions).toHaveBeenCalledTimes(2);
    expect(splitOptions.mock.calls[1][0]).toEqual({
      requestJson: OTHER_REQUEST,
      currencyCode: "CAD",
      attempt: 0
    });
    // The first lane's answer lands late: it must not replace this lane's.
    release(HISTORY_CAD);
    await settle();
    expect(texts(el, "option-title")).toEqual(ESTIMATE_TITLES);

    // The same request again changes nothing.
    el.requestJson = OTHER_REQUEST;
    await flush();
    expect(field(el, "split-card")).not.toBeNull();
  });
});
