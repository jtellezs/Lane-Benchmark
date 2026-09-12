// Every "?" in the app points at a section that exists, and every area the
// spec lists has its "?". Reads the templates and the built index from disk.
const fs = require("fs");
const path = require("path");

const LWC = path.resolve(__dirname, "..", "..");
const INDEX = path.resolve(
  LWC,
  "..",
  "staticresources",
  "helpCenter",
  "index.json"
);
const EXPECTED = {
  laneBenchmark: "lb-lane",
  laneBenchmarkFilters: "lb-filters",
  laneBenchmarkStats: "lb-stats",
  laneBenchmarkResults: "lb-results",
  rfpProjectList: "rfp-projects",
  rfpUpload: "rfp-upload",
  rfpColumnMapper: "rfp-upload",
  rfpToolbar: "rfp-history",
  rfpBulkBar: "rfp-bulk",
  rfpLaneTable: "rfp-inline",
  rfpLanePanel: "rfp-pricing",
  rfpBidForm: "rfp-bids"
};

function topicsIn(bundle) {
  const html = fs.readFileSync(
    path.join(LWC, bundle, `${bundle}.html`),
    "utf8"
  );
  return [...html.matchAll(/<c-help-hint[^>]*\btopic="([^"]+)"/g)].map(
    (m) => m[1]
  );
}

describe("help hint placement", () => {
  const slugs = new Set(
    JSON.parse(fs.readFileSync(INDEX, "utf8")).sections.map((s) => s.slug)
  );

  it("puts the expected topic in each host template", () => {
    Object.entries(EXPECTED).forEach(([bundle, topic]) => {
      expect({ bundle, topics: topicsIn(bundle) }).toEqual({
        bundle,
        topics: [topic]
      });
    });
  });

  it("only uses topics that exist in the built index", () => {
    const dirs = fs
      .readdirSync(LWC, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .filter((name) => fs.existsSync(path.join(LWC, name, `${name}.html`)));
    dirs.forEach((bundle) => {
      topicsIn(bundle).forEach((topic) => {
        expect({ bundle, topic, known: slugs.has(topic) }).toEqual({
          bundle,
          topic,
          known: true
        });
      });
    });
  });
});
