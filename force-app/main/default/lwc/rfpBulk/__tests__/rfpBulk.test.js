import applyMedian from "@salesforce/apex/RfpBulkController.applyMedian";
import applyPricing from "@salesforce/apex/RfpBulkController.applyPricing";
import deleteLanes from "@salesforce/apex/RfpBulkController.deleteLanes";
import { runBulk, applyBulkResult, summaryText, BULK_CHUNK } from "c/rfpBulk";

jest.mock(
  "@salesforce/apex/RfpBulkController.applyMedian",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.applyBid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.copyPricing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RfpBulkController.deleteLanes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ids = (n) => Array.from({ length: n }, (_, i) => `a0L${i + 1}`);

describe("runBulk", () => {
  beforeEach(() => jest.clearAllMocks());

  it("chunks by 200 and folds the results together", async () => {
    applyMedian.mockImplementation(async ({ laneIds }) => ({
      lanes: laneIds.map((Id) => ({ Id, Cost__c: 1 })),
      updated: laneIds.length - 1,
      skipped: 1,
      skippedIds: [laneIds[0]],
      errors: []
    }));
    const progress = [];
    const r = await runBulk({
      action: "median",
      ids: ids(450),
      params: { overwrite: true },
      onProgress: (n) => progress.push(n)
    });
    expect(applyMedian).toHaveBeenCalledTimes(3);
    expect(applyMedian.mock.calls[0][0]).toEqual({
      laneIds: ids(450).slice(0, BULK_CHUNK),
      overwrite: true
    });
    expect(r.updated).toBe(447);
    expect(r.skipped).toBe(3);
    expect(r.skippedIds).toEqual(["a0L1", "a0L201", "a0L401"]);
    expect(r.lanes).toHaveLength(450);
    expect(progress).toEqual([200, 200, 50]);
  });

  it("a failing chunk counts its ids as failed and the run carries on", async () => {
    applyPricing
      .mockRejectedValueOnce({
        body: { message: "The margin must be between 0 and 100." }
      })
      .mockResolvedValueOnce({
        lanes: [],
        updated: 1,
        skipped: 0,
        skippedIds: [],
        errors: []
      });
    const r = await runBulk({
      action: "pricing",
      ids: ids(201),
      params: { margin: 10 }
    });
    expect(applyPricing.mock.calls[0][0]).toEqual({
      laneIds: ids(200),
      cost: null,
      sell: null,
      margin: 10
    });
    expect(r.failedIds).toHaveLength(200);
    expect(r.updated).toBe(1);
    expect(r.errors[0]).toBe("The margin must be between 0 and 100.");
  });

  it("stops between chunks when asked", async () => {
    deleteLanes.mockResolvedValue({
      lanes: [],
      updated: 200,
      skipped: 0,
      skippedIds: [],
      errors: []
    });
    let stop = false;
    const r = await runBulk({
      action: "delete",
      ids: ids(400),
      onProgress: () => {
        stop = true;
      },
      isStopped: () => stop
    });
    expect(deleteLanes).toHaveBeenCalledTimes(1);
    expect(r.updated).toBe(200);
  });

  it("refuses an unknown action", async () => {
    await expect(runBulk({ action: "nope", ids: ids(1) })).rejects.toThrow(
      "Unknown bulk action"
    );
  });
});

describe("applyBulkResult / summaryText", () => {
  const lanes = [
    { Id: "a", Cost__c: null },
    { Id: "b", Cost__c: null },
    { Id: "c" }
  ];
  it("merges returned lanes for pricing actions", () => {
    const out = applyBulkResult(lanes, ["a", "c"], {
      action: "median",
      lanes: [{ Id: "a", Cost__c: 5 }],
      updated: 1,
      skipped: 0,
      skippedIds: [],
      errors: [],
      failedIds: []
    });
    expect(out.lanes[0]).toEqual({ Id: "a", Cost__c: 5 });
    expect(out.lanes[1]).toEqual({ Id: "b", Cost__c: null });
    expect(out.selectedIds).toEqual(["a", "c"]);
  });
  it("drops deleted lanes from the list and the selection", () => {
    const out = applyBulkResult(lanes, ["a", "b", "c"], {
      action: "delete",
      lanes: [{ Id: "b", Cost__c: null }],
      updated: 2,
      skipped: 0,
      skippedIds: [],
      errors: [],
      failedIds: [],
      ids: ["a", "b", "c"]
    });
    expect(out.lanes.map((l) => l.Id)).toEqual(["b"]);
    expect(out.selectedIds).toEqual(["b"]);
  });
  it("words the summary", () => {
    expect(
      summaryText({
        action: "median",
        updated: 143,
        skipped: 12,
        failedIds: [],
        errors: []
      })
    ).toBe("Median applied to 143 lanes; 12 skipped");
    expect(
      summaryText({
        action: "delete",
        updated: 1,
        skipped: 0,
        failedIds: ["x"],
        errors: ["boom"]
      })
    ).toBe("Deleted 1 lane; 1 failed; boom");
    expect(
      summaryText({
        action: "bid",
        updated: 3,
        skipped: 0,
        failedIds: [],
        errors: []
      })
    ).toBe("Carrier rate added to 3 lanes");
  });
});
