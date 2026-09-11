import { chunk, mergeLanes, lanesForHistory, series } from "c/rfpBatch";

const lane = (id, extra) => ({
  Id: id,
  Row_Number__c: Number(id.replace(/\D/g, "")),
  Origin_Resolved__c: true,
  Destination_Resolved__c: true,
  Hist_Status__c: "Pending",
  ...extra
});

describe("chunk", () => {
  it("splits a list into groups of the given size, last one short", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });

  it("splits 23 lane ids into 10 / 10 / 3 in order", () => {
    const ids = Array.from({ length: 23 }, (_, i) => `id${i}`);
    const groups = chunk(ids, 10);
    expect(groups.map((g) => g.length)).toEqual([10, 10, 3]);
    expect(groups[0][0]).toBe("id0");
    expect(groups[1][0]).toBe("id10");
    expect(groups[2]).toEqual(["id20", "id21", "id22"]);
  });

  it("splits 450 rows into 200 / 200 / 50", () => {
    const rows = Array.from({ length: 450 }, (_, i) => i);
    expect(chunk(rows, 200).map((g) => g.length)).toEqual([200, 200, 50]);
  });

  it("returns an empty list for an empty or missing list", () => {
    expect(chunk([], 10)).toEqual([]);
    expect(chunk(undefined, 10)).toEqual([]);
  });
});

describe("mergeLanes", () => {
  it("replaces lanes by Id and keeps the original order", () => {
    const lanes = [lane("a1"), lane("a2"), lane("a3")];
    const merged = mergeLanes(lanes, [
      lane("a3", { Hist_Status__c: "Done" }),
      lane("a1", { Hist_Status__c: "No match" })
    ]);
    expect(merged.map((l) => l.Id)).toEqual(["a1", "a2", "a3"]);
    expect(merged.map((l) => l.Hist_Status__c)).toEqual([
      "No match",
      "Pending",
      "Done"
    ]);
  });

  it("accepts a single lane and ignores unknown ids", () => {
    const lanes = [lane("a1"), lane("a2")];
    const merged = mergeLanes(lanes, lane("a2", { Cost__c: 1200 }));
    expect(merged[1].Cost__c).toBe(1200);
    expect(mergeLanes(lanes, lane("zz")).map((l) => l.Id)).toEqual([
      "a1",
      "a2"
    ]);
  });

  it("returns the lanes untouched for an empty update", () => {
    const lanes = [lane("a1")];
    expect(mergeLanes(lanes, [])).toEqual(lanes);
    expect(mergeLanes(lanes, null)).toEqual(lanes);
    expect(mergeLanes(null, [lane("a1")])).toEqual([]);
  });
});

describe("lanesForHistory", () => {
  const lanes = [
    lane("a1"),
    lane("a2", { Hist_Status__c: "Done" }),
    lane("a3", { Hist_Status__c: "Failed" }),
    lane("a4", {
      Hist_Status__c: "Unresolved",
      Destination_Resolved__c: false
    }),
    lane("a5", { Origin_Resolved__c: false, Hist_Status__c: "Pending" })
  ];

  it("takes only resolved Pending lanes by default", () => {
    expect(lanesForHistory(lanes, "pending").map((l) => l.Id)).toEqual(["a1"]);
  });

  it("takes every lane with both ends resolved for a refresh", () => {
    expect(lanesForHistory(lanes, "all").map((l) => l.Id)).toEqual([
      "a1",
      "a2",
      "a3"
    ]);
  });

  it("takes only the failed lanes for a retry", () => {
    expect(lanesForHistory(lanes, "failed").map((l) => l.Id)).toEqual(["a3"]);
  });

  it("handles a missing lane list", () => {
    expect(lanesForHistory(undefined, "all")).toEqual([]);
  });
});

describe("series", () => {
  it("runs the steps one at a time, in order", async () => {
    const started = [];
    const finished = [];
    await series([1, 2, 3], async (n) => {
      started.push(n);
      await Promise.resolve();
      finished.push(n);
    });
    expect(started).toEqual([1, 2, 3]);
    expect(finished).toEqual([1, 2, 3]);
  });

  it("passes the index through and tolerates a missing list", async () => {
    const seen = [];
    await series(["a", "b"], (item, index) => seen.push(`${index}:${item}`));
    expect(seen).toEqual(["0:a", "1:b"]);
    await expect(series(undefined, () => {})).resolves.toBeUndefined();
  });

  it("still gives every step its turn, so a step can opt out itself", async () => {
    let stopped = false;
    const ran = [];
    await series([1, 2, 3], (n) => {
      if (stopped) {
        return;
      }
      ran.push(n);
      stopped = n === 2;
    });
    expect(ran).toEqual([1, 2]);
  });
});
