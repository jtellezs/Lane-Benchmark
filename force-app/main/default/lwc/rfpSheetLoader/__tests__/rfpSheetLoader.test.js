jest.mock(
  "@salesforce/resourceUrl/sheetJs",
  () => ({ __esModule: true, default: "/sheetjs" }),
  { virtual: true }
);

// The loader caches its load promise in module scope, so every test starts from
// a fresh copy of the module (and a fresh loadScript mock with it).
function freshLoader() {
  jest.resetModules();
  return {
    ensureSheetJs: require("c/rfpSheetLoader").ensureSheetJs,
    loadScript: require("lightning/platformResourceLoader").loadScript
  };
}

describe("ensureSheetJs", () => {
  afterEach(() => {
    delete window.XLSX;
  });

  it("resolves without loading when XLSX is already on the window", async () => {
    const { ensureSheetJs, loadScript } = freshLoader();
    window.XLSX = { utils: {} };
    await ensureSheetJs({});
    expect(loadScript).not.toHaveBeenCalled();
  });

  it("loads the script once and caches the promise", async () => {
    const { ensureSheetJs, loadScript } = freshLoader();
    loadScript.mockResolvedValue(undefined);
    await Promise.all([ensureSheetJs({}), ensureSheetJs({})]);
    await ensureSheetJs({});
    expect(loadScript).toHaveBeenCalledTimes(1);
    expect(loadScript.mock.calls[0][1]).toBe("/sheetjs");
  });

  it("clears the cache on failure so the next call retries", async () => {
    const { ensureSheetJs, loadScript } = freshLoader();
    loadScript.mockRejectedValueOnce(new Error("network down"));
    await expect(ensureSheetJs({})).rejects.toThrow("network down");
    loadScript.mockResolvedValueOnce(undefined);
    await ensureSheetJs({});
    expect(loadScript).toHaveBeenCalledTimes(2);
  });

  it("passes the calling component through to loadScript", async () => {
    const { ensureSheetJs, loadScript } = freshLoader();
    loadScript.mockResolvedValue(undefined);
    const component = { tag: "c-rfp-export" };
    await ensureSheetJs(component);
    expect(loadScript.mock.calls[0][0]).toBe(component);
  });
});
