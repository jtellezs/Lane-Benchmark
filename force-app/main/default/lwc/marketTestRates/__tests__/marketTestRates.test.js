import { createElement } from "lwc";
import MarketTestRates from "c/marketTestRates";
import getRates from "@salesforce/apex/MarketTestController.getRates";
import saveRate from "@salesforce/apex/MarketTestController.saveRate";
import deleteRate from "@salesforce/apex/MarketTestController.deleteRate";

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
jest.mock("@salesforce/user/Id", () => ({ default: "005MINE" }), {
  virtual: true
});

const LANE = JSON.stringify({
  originKey: "toronto|on|ca",
  destinationKey: "montreal|qc|ca"
});

function rate(id, amount, owner = "005MINE") {
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

describe("c-market-test-rates", () => {
  let element;

  beforeEach(() => {
    getRates.mockResolvedValue([]);
    saveRate.mockResolvedValue({});
    deleteRate.mockResolvedValue();
    element = createElement("c-market-test-rates", { is: MarketTestRates });
    element.currencyCode = "CAD";
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("stays closed until a lane has been searched", async () => {
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(getRates).not.toHaveBeenCalled();
  });

  it("reads the lane out of the search request and loads its rates", async () => {
    document.body.appendChild(element);
    element.requestJson = LANE;
    await flush();
    expect(getRates).toHaveBeenCalledWith({
      originKey: "toronto|on|ca",
      destinationKey: "montreal|qc|ca"
    });
    expect(element.shadowRoot.querySelector(".add-rate")).not.toBeNull();
  });

  it("summarises the rates it lists", async () => {
    getRates.mockResolvedValue([
      rate("a", 2000),
      rate("b", 2400),
      rate("c", 3000)
    ]);
    document.body.appendChild(element);
    element.requestJson = LANE;
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("3");
    expect(text).toContain("2,400");
  });

  it("offers delete only on the rates this user recorded", async () => {
    getRates.mockResolvedValue([
      rate("mine", 2000),
      rate("theirs", 2500, "005OTHER")
    ]);
    document.body.appendChild(element);
    element.requestJson = LANE;
    await flush();
    const buttons = element.shadowRoot.querySelectorAll(".delete-rate");
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.id).toBe("mine");
  });

  it("saves against the searched lane in the card's currency", async () => {
    document.body.appendChild(element);
    element.requestJson = LANE;
    await flush();
    element.shadowRoot.querySelector(".add-rate").click();
    await flush();
    element.shadowRoot
      .querySelector("c-rfp-bid-form")
      .dispatchEvent(
        new CustomEvent("save", { detail: { bid: { Rate__c: 2500 } } })
      );
    await flush();
    const arg = saveRate.mock.calls[0][0];
    expect(arg.originKey).toBe("toronto|on|ca");
    expect(JSON.parse(arg.rateJson).CurrencyIsoCode).toBe("CAD");
  });

  it("survives a request it cannot parse", async () => {
    document.body.appendChild(element);
    element.requestJson = "{not json";
    await flush();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(getRates).not.toHaveBeenCalled();
  });
});
