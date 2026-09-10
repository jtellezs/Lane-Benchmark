import { createElement } from "lwc";
import MapPreview from "c/laneBenchmarkMap";
const flush = () => Promise.resolve().then(() => Promise.resolve());

describe("c-lane-benchmark-map", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });
  it("renders the image only when a url is given", async () => {
    const el = createElement("c-lane-benchmark-map", { is: MapPreview });
    document.body.appendChild(el);
    await flush();
    expect(el.shadowRoot.querySelector("img")).toBeNull();
    el.previewUrl =
      "https://api.mapbox.com/styles/v1/x/static/auto/600x300?access_token=pk";
    await flush();
    expect(el.shadowRoot.querySelector("img").src).toContain("api.mapbox.com");
  });
});
