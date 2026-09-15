import {
  UNIT_KEY,
  KM_PER_MILE,
  readUnit,
  writeUnit,
  formatDistance,
  perDistance
} from "c/distanceUnit";

describe("distanceUnit", () => {
  beforeEach(() => {
    try {
      window.localStorage.clear();
    } catch {
      // ignore
    }
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("names the storage key and the exact conversion", () => {
    expect(UNIT_KEY).toBe("tripMiles.unit.v1");
    expect(KM_PER_MILE).toBe(1.609344);
  });

  it("formats whole miles and kilometres the Canadian English way", () => {
    expect(formatDistance(1234, "mi")).toBe("1,234 mi");
    expect(formatDistance(1234, "km")).toBe("1,986 km");
    expect(formatDistance(1, "km")).toBe("2 km");
    expect(formatDistance(1234.6, "mi")).toBe("1,235 mi");
    expect(formatDistance("512.4", "mi")).toBe("512 mi");
    expect(formatDistance(0, "mi")).toBe("0 mi");
  });

  it("treats an unknown unit as miles and a missing distance as blank", () => {
    expect(formatDistance(100, "yards")).toBe("100 mi");
    expect(formatDistance(100, undefined)).toBe("100 mi");
    expect(formatDistance(null, "mi")).toBe("");
    expect(formatDistance(undefined, "km")).toBe("");
    expect(formatDistance("", "mi")).toBe("");
    expect(formatDistance("abc", "mi")).toBe("");
  });

  it("divides an amount by the distance in the chosen unit, to the cent", () => {
    expect(perDistance(2500, 1000, "mi")).toBe(2.5);
    expect(perDistance(1000, 3, "mi")).toBe(333.33);
    expect(perDistance(1609.344, 1, "km")).toBe(1000);
    expect(perDistance(1000, 1234, "km")).toBe(0.5);
    expect(perDistance(2345.67, 512.4, "mi")).toBe(4.58);
    expect(perDistance("2500", "1000", "km")).toBe(1.55);
  });

  it("returns null without a positive amount and distance", () => {
    expect(perDistance(1000, 0, "mi")).toBeNull();
    expect(perDistance(1000, -5, "mi")).toBeNull();
    expect(perDistance(0, 100, "mi")).toBeNull();
    expect(perDistance(null, 100, "mi")).toBeNull();
    expect(perDistance(1000, null, "km")).toBeNull();
    expect(perDistance("", 100, "mi")).toBeNull();
    expect(perDistance(1000, "abc", "mi")).toBeNull();
  });

  it("remembers the chosen unit and ignores anything else", () => {
    expect(readUnit()).toBe("mi");
    writeUnit("km");
    expect(readUnit()).toBe("km");
    expect(window.localStorage.getItem("tripMiles.unit.v1")).toBe("km");
    writeUnit("yards");
    expect(readUnit()).toBe("km");
    window.localStorage.setItem("tripMiles.unit.v1", "furlongs");
    expect(readUnit()).toBe("mi");
  });

  it("falls back to miles when storage throws on read", () => {
    window.localStorage.setItem("tripMiles.unit.v1", "km");
    jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(readUnit()).toBe("mi");
  });

  it("swallows a blocked write", () => {
    const spy = jest
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new Error("blocked");
      });
    expect(() => writeUnit("km")).not.toThrow();
    expect(spy).toHaveBeenCalledWith("tripMiles.unit.v1", "km");
    spy.mockRestore();
    expect(readUnit()).toBe("mi");
  });
});
