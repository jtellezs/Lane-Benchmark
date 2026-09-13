// Every "?" in the app points at a section that exists, every area the
// spec lists has its "?", and every "?" names its topic literally. Reads
// every template under lwc and the built index from disk.
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

// The <c-help-hint ...> opening tags in a template, each with its literal
// topic. A hint whose topic is bound (topic={x}), spelt data-topic or
// missing gets null, so the tests below can name it.
function hintTags(html) {
  return [...html.matchAll(/<c-help-hint\b[^>]*>/g)].map((m) => {
    const topic = /\stopic="([^"]+)"/.exec(m[0]);
    return { tag: m[0], topic: topic ? topic[1] : null };
  });
}

// Every hint in every *.html of a bundle, tagged with its file.
function hintsIn(bundle) {
  const dir = path.join(LWC, bundle);
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".html"))
    .sort()
    .flatMap((f) =>
      hintTags(fs.readFileSync(path.join(dir, f), "utf8")).map((h) => ({
        ...h,
        file: `${bundle}/${f}`
      }))
    );
}

function bundles() {
  return fs
    .readdirSync(LWC, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

describe("help hint placement", () => {
  const slugs = new Set(
    JSON.parse(fs.readFileSync(INDEX, "utf8")).sections.map((s) => s.slug)
  );
  const all = bundles().flatMap(hintsIn);

  it("reads a hint's topic only from a literal topic attribute", () => {
    expect(
      hintTags('<c-help-hint topic="rfp-bulk" label="Help"></c-help-hint>')
    ).toEqual([
      { tag: '<c-help-hint topic="rfp-bulk" label="Help">', topic: "rfp-bulk" }
    ]);
    expect(
      hintTags('<c-help-hint\n  topic="lb-lane"\n  label="Help: lane"\n>')[0]
        .topic
    ).toBe("lb-lane");
    expect(hintTags("<c-help-hint topic={topic}></c-help-hint>")).toEqual([
      { tag: "<c-help-hint topic={topic}>", topic: null }
    ]);
    expect(
      hintTags('<c-help-hint data-topic="rfp-bulk"></c-help-hint>')[0].topic
    ).toBeNull();
    expect(hintTags('<c-help-hint label="Help"></c-help-hint>')[0].topic).toBe(
      null
    );
    expect(hintTags('<a topic="x"></a><c-help-hinted topic="x">')).toEqual([]);
  });

  it("gives every hint a literal topic", () => {
    expect(all.length).toBeGreaterThan(0);
    const problems = all
      .filter((h) => h.topic === null)
      .map((h) => `${h.file}: ${h.tag} needs a literal topic="..." attribute`);
    expect(problems).toEqual([]);
  });

  it("puts the expected topic in each host template", () => {
    Object.entries(EXPECTED).forEach(([bundle, topic]) => {
      expect({ bundle, topics: hintsIn(bundle).map((h) => h.topic) }).toEqual({
        bundle,
        topics: [topic]
      });
    });
  });

  it("only uses topics that exist in the built index", () => {
    // Hints without a literal topic are reported by the test above.
    const named = all.filter((h) => h.topic !== null);
    expect(named.length).toBeGreaterThan(0);
    named.forEach(({ file, topic }) => {
      expect({ file, topic, known: slugs.has(topic) }).toEqual({
        file,
        topic,
        known: true
      });
    });
  });
});
