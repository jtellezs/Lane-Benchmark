import { load, save, clear, STORAGE_KEY } from "c/laneBenchmarkStorage";

describe("laneBenchmarkStorage", () => {
  beforeEach(() => window.localStorage.clear());

  it("round-trips a request", () => {
    save({ originKey: "montreal|qc|ca", lookbackDays: 90 });
    expect(load()).toEqual({ originKey: "montreal|qc|ca", lookbackDays: 90 });
    expect(STORAGE_KEY).toBe("laneBenchmark.request.v1");
  });
  it("returns null when nothing is saved or the value is corrupt", () => {
    expect(load()).toBeNull();
    window.localStorage.setItem(STORAGE_KEY, "{not json");
    expect(load()).toBeNull();
  });
  it("clear removes the entry", () => {
    save({ a: 1 });
    clear();
    expect(load()).toBeNull();
  });
  it("never throws when storage is unavailable", () => {
    const original = window.localStorage.setItem;
    window.localStorage.setItem = () => {
      throw new Error("quota");
    };
    expect(() => save({ a: 1 })).not.toThrow();
    window.localStorage.setItem = original;
  });
});
