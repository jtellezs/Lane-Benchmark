import { createElement } from "lwc";
import DistanceUnitToggle from "c/distanceUnitToggle";
import {
  APPLICATION_SCOPE,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import DISTANCE_UNIT from "@salesforce/messageChannel/Distance_Unit__c";

const flush = () => Promise.resolve().then(() => Promise.resolve());
const field = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`);
const pressed = (el, id) => field(el, id).getAttribute("aria-pressed");

let onMessage;

async function mount() {
  const el = createElement("c-distance-unit-toggle", {
    is: DistanceUnitToggle
  });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-distance-unit-toggle", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.localStorage.clear();
    onMessage = null;
    subscribe.mockImplementation((context, channel, handler) => {
      onMessage = handler;
      return { id: "sub-1" };
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("starts on miles and subscribes to the channel application-wide", async () => {
    const el = await mount();
    expect(pressed(el, "unit-mi")).toBe("true");
    expect(pressed(el, "unit-km")).toBe("false");
    expect(field(el, "unit-mi").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(field(el, "unit-km").className).toBe(
      "slds-button slds-button_neutral"
    );
    expect(subscribe).toHaveBeenCalledTimes(1);
    expect(subscribe.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(subscribe.mock.calls[0][3]).toEqual({ scope: APPLICATION_SCOPE });
  });

  it("starts from the unit this browser remembered", async () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    const el = await mount();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(pressed(el, "unit-mi")).toBe("false");
  });

  it("switches to km, remembers it and publishes the unit", async () => {
    const el = await mount();
    field(el, "unit-km").click();
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(pressed(el, "unit-mi")).toBe("false");
    expect(field(el, "unit-km").className).toBe(
      "slds-button slds-button_brand"
    );
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBe("km");
    expect(publish).toHaveBeenCalledTimes(1);
    expect(publish.mock.calls[0][1]).toBe(DISTANCE_UNIT);
    expect(publish.mock.calls[0][2]).toEqual({ unit: "km" });
  });

  it("does not publish when the active unit is clicked again", async () => {
    const el = await mount();
    field(el, "unit-mi").click();
    await flush();
    expect(publish).not.toHaveBeenCalled();
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBeNull();
  });

  it("follows a unit published elsewhere on the page without publishing back", async () => {
    const el = await mount();
    onMessage({ unit: "km" });
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    onMessage({ unit: "leagues" });
    onMessage(null);
    await flush();
    expect(pressed(el, "unit-km")).toBe("true");
    expect(publish).not.toHaveBeenCalled();
  });

  it("unsubscribes when removed from the page", async () => {
    const el = await mount();
    document.body.removeChild(el);
    expect(unsubscribe).toHaveBeenCalledWith({ id: "sub-1" });
  });
});
