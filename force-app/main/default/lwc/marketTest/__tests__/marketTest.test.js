import { createElement } from "lwc";
import MarketTest from "c/marketTest";
import getRates from "@salesforce/apex/MarketTestController.getRates";
import saveRate from "@salesforce/apex/MarketTestController.saveRate";
import deleteRate from "@salesforce/apex/MarketTestController.deleteRate";
import search from "@salesforce/apex/LaneBenchmarkController.search";

jest.mock(
  "@salesforce/apex/MarketTestController.getRates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MarketTestController.saveRate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MarketTestController.deleteRate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LaneBenchmarkController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/user/Id", () => ({ default: "005MINE" }), {
  virtual: true
});

const MINE = "005MINE";

function rate(id, amount, owner = MINE) {
  return {
    Id: id,
    Rate__c: amount,
    CurrencyIsoCode: "CAD",
    Carrier_Name__c: "Carrier " + id,
    OwnerId: owner
  };
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

describe("c-market-test", () => {
  let element;

  beforeEach(() => {
    getRates.mockResolvedValue([]);
    search.mockResolvedValue({ statsByCurrency: {} });
    saveRate.mockResolvedValue({});
    deleteRate.mockResolvedValue();
    element = createElement("c-market-test", { is: MarketTest });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function pickLane() {
    const pickers = element.shadowRoot.querySelectorAll(
      "c-lane-benchmark-place-picker"
    );
    pickers[0].dispatchEvent(
      new CustomEvent("placechange", {
        detail: { key: "toronto|on|ca", label: "Toronto, ON" }
      })
    );
    pickers[1].dispatchEvent(
      new CustomEvent("placechange", {
        detail: { key: "montreal|qc|ca", label: "Montreal, QC" }
      })
    );
  }

  it("offers two place pickers and no rate list before a lane is picked", () => {
    document.body.appendChild(element);
    expect(
      element.shadowRoot.querySelectorAll("c-lane-benchmark-place-picker")
    ).toHaveLength(2);
    expect(element.shadowRoot.querySelector(".add-rate")).toBeNull();
  });

  it("loads the lane's rates and its history once both ends are picked", async () => {
    document.body.appendChild(element);
    pickLane();
    await flush();
    expect(getRates).toHaveBeenCalledWith({
      originKey: "toronto|on|ca",
      destinationKey: "montreal|qc|ca"
    });
    expect(search).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".add-rate")).not.toBeNull();
  });

  it("summarises the rates it lists", async () => {
    getRates.mockResolvedValue([
      rate("a", 2000),
      rate("b", 2400),
      rate("c", 3000)
    ]);
    document.body.appendChild(element);
    pickLane();
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("3 rates");
    expect(text).toContain("2,400");
  });

  it("offers delete only on the rates this user recorded", async () => {
    getRates.mockResolvedValue([
      rate("mine", 2000),
      rate("theirs", 2500, "005OTHER")
    ]);
    document.body.appendChild(element);
    pickLane();
    await flush();
    const buttons = element.shadowRoot.querySelectorAll(".delete-rate");
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.id).toBe("mine");
  });

  it("saves a rate with the lane and the chosen currency, then reloads", async () => {
    document.body.appendChild(element);
    pickLane();
    await flush();
    element.shadowRoot.querySelector(".add-rate").click();
    await flush();
    const form = element.shadowRoot.querySelector("c-rfp-bid-form");
    form.dispatchEvent(
      new CustomEvent("save", { detail: { bid: { Rate__c: 2500 } } })
    );
    await flush();
    expect(saveRate).toHaveBeenCalled();
    const arg = saveRate.mock.calls[0][0];
    expect(arg.originKey).toBe("toronto|on|ca");
    expect(JSON.parse(arg.rateJson).CurrencyIsoCode).toBe("CAD");
  });
});
