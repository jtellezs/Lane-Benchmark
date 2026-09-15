import { createElement } from "lwc";
import RfpToolbar from "c/rfpToolbar";

// c-rfp-export renders inside this bundle, so the Apex modules it imports are
// stubbed here too; babel-plugin-jest-hoist only hoists literal jest.mock calls.
jest.mock(
  "@salesforce/apex/RfpLaneController.getRawRows",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBidController.getBids",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/resourceUrl/sheetJs", () => "/sheetjs", {
  virtual: true
});

const PROJECT = { Id: "a0P1", Name: "Costco Q4" };
const LANES = [{ Id: "a0L1" }, { Id: "a0L2" }];

const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount(props = {}) {
  const el = createElement("c-rfp-toolbar", { is: RfpToolbar });
  Object.assign(el, {
    project: PROJECT,
    lanes: LANES,
    precision: "CITY",
    lookbackDays: 90,
    radius: 50,
    radiusUnit: "KM",
    includeBids: true,
    ...props
  });
  document.body.appendChild(el);
  return el;
}

/** Records one event by name and returns the handler's captured events. */
function listen(el, name) {
  const seen = [];
  el.addEventListener(name, (e) => seen.push(e));
  return seen;
}

describe("c-rfp-toolbar", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders every control with the values it was given", () => {
    const el = mount({
      precision: "RADIUS",
      lookbackDays: 30,
      radius: 150,
      radiusUnit: "MI"
    });
    expect(field(el, "back").label).toBe("All projects");
    expect(field(el, "upload-more").label).toBe("Upload a file");
    expect(field(el, "precision").value).toBe("RADIUS");
    expect(field(el, "precision").options.map((o) => o.value)).toEqual([
      "CITY",
      "PROVINCE",
      "RADIUS"
    ]);
    expect(field(el, "lookback").value).toBe(30);
    expect(field(el, "radius").value).toBe(150);
    expect(field(el, "radius-unit").value).toBe("MI");
    expect(field(el, "radius-unit").options.map((o) => o.value)).toEqual([
      "KM",
      "MI"
    ]);
    expect(field(el, "load-history").label).toBe("Load history");
    expect(field(el, "refresh-history").label).toBe("Refresh history");
    expect(field(el, "retry-failed").label).toBe("Retry failed");
  });

  it("renders the Include RFP bids checkbox after the unit, checked by default", () => {
    const el = mount();
    const toggle = field(el, "include-bids");
    expect(toggle.type).toBe("checkbox");
    expect(toggle.label).toBe("Include RFP bids");
    expect(toggle.checked).toBe(true);
    expect(
      mount({ includeBids: false }).shadowRoot.querySelector(
        '[data-id="include-bids"]'
      ).checked
    ).toBe(false);
  });

  it("puts the distance unit toggle in the column right after Include RFP bids", () => {
    const el = mount();
    const toggle = field(el, "distance-unit");
    expect(toggle).not.toBeNull();
    expect(toggle.tagName.toLowerCase()).toBe("c-distance-unit-toggle");
    // Every control has its own column, so the toggle's column is the one
    // straight after the checkbox's.
    const bidsColumn = field(el, "include-bids").parentElement;
    expect(bidsColumn.nextElementSibling.contains(toggle)).toBe(true);
  });

  it("hands the project, the lanes and its busy flag to the export", () => {
    const el = mount();
    const exporter = el.shadowRoot.querySelector("c-rfp-export");
    expect(exporter.project).toEqual(PROJECT);
    expect(exporter.lanes).toEqual(LANES);
    expect(exporter.parentBusy).toBe(false);
    expect(
      mount({ busy: true }).shadowRoot.querySelector("c-rfp-export").parentBusy
    ).toBe(true);
  });

  it("disables everything a run owns while busy, and nothing else", () => {
    const el = mount({ busy: true });
    [
      "upload-more",
      "include-bids",
      "load-history",
      "refresh-history",
      "retry-failed"
    ].forEach((id) => expect(field(el, id).disabled).toBe(true));
    expect(field(el, "back").disabled).toBeFalsy();
    const idle = mount();
    [
      "upload-more",
      "include-bids",
      "load-history",
      "refresh-history",
      "retry-failed"
    ].forEach((id) => expect(field(idle, id).disabled).toBe(false));
  });

  it("emits the navigation and history events with no payload", () => {
    const el = mount();
    const pairs = [
      ["back", "back"],
      ["upload-more", "uploadmore"],
      ["load-history", "loadhistory"],
      ["refresh-history", "refreshhistory"],
      ["retry-failed", "retryfailed"]
    ];
    pairs.forEach(([id, name]) => {
      const seen = listen(el, name);
      field(el, id).click();
      expect(seen.length).toBe(1);
      expect(seen[0].bubbles).toBe(false);
    });
  });

  it("reports each setting change as settingchange with the raw value", () => {
    const el = mount();
    const seen = listen(el, "settingchange");
    field(el, "precision").dispatchEvent(
      new CustomEvent("change", { detail: { value: "PROVINCE" } })
    );
    field(el, "lookback").dispatchEvent(
      new CustomEvent("change", { detail: { value: "30" } })
    );
    field(el, "radius").dispatchEvent(
      new CustomEvent("change", { detail: { value: "150" } })
    );
    field(el, "radius-unit").dispatchEvent(
      new CustomEvent("change", { detail: { value: "MI" } })
    );
    expect(seen.map((e) => e.detail)).toEqual([
      { name: "precision", value: "PROVINCE" },
      { name: "lookbackDays", value: "30" },
      { name: "radius", value: "150" },
      { name: "radiusUnit", value: "MI" }
    ]);
    expect(seen[0].bubbles).toBe(false);
  });

  it("reports the bids toggle as a boolean", () => {
    const el = mount();
    const seen = listen(el, "settingchange");
    field(el, "include-bids").dispatchEvent(
      new CustomEvent("change", { detail: { checked: false } })
    );
    field(el, "include-bids").dispatchEvent(
      new CustomEvent("change", { detail: { checked: true } })
    );
    expect(seen.map((e) => e.detail)).toEqual([
      { name: "includeBids", value: false },
      { name: "includeBids", value: true }
    ]);
  });
});
