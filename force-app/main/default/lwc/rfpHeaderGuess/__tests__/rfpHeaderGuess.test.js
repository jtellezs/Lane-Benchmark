import { guess, missingRequired, TARGETS } from "c/rfpHeaderGuess";

describe("rfpHeaderGuess", () => {
  it("recognises common headers case-insensitively", () => {
    const m = guess([
      "Origin City",
      "Orig State",
      "O Zip",
      "Dest City",
      "Destination Province",
      "Dest. Postal Code",
      "Mode",
      "Equip",
      "Commodity",
      "Qty",
      "Annual Shipments",
      "FSC",
      "FSC Included",
      "Hazmat"
    ]);
    expect(m.originCity).toBe("Origin City");
    expect(m.originProvince).toBe("Orig State");
    expect(m.originPostal).toBe("O Zip");
    expect(m.destinationCity).toBe("Dest City");
    expect(m.destinationProvince).toBe("Destination Province");
    expect(m.destinationPostal).toBe("Dest. Postal Code");
    expect(m.mode).toBe("Mode");
    expect(m.equipmentType).toBe("Equip");
    expect(m.quantity).toBe("Qty");
    expect(m.shipmentsPerYear).toBe("Annual Shipments");
    expect(m.fuelSurcharge).toBe("FSC");
    expect(m.fscIncluded).toBe("FSC Included");
    expect(m.hazmat).toBe("Hazmat");
  });
  it("never maps one header to two targets and reports required gaps", () => {
    const m = guess(["From", "To"]);
    expect(m.originCity).toBe("From");
    expect(m.destinationCity).toBe("To");
    expect(missingRequired(m)).toEqual([]);
    expect(missingRequired({ originCity: "From" })).toEqual([
      "destinationCity"
    ]);
    expect(
      missingRequired({ originPostal: "A", destinationPostal: "B" })
    ).toEqual([]);
    expect(missingRequired({})).toEqual(["originCity", "destinationCity"]);
    expect(TARGETS.map((t) => t.key)).toContain("quantityUnit");
  });
});
