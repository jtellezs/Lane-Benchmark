const MODE_CELL_CLASS = {
  LTL: "ltl-cell",
  Truckload: "ftl-cell",
  "Freight Forwarding": "freight-cell"
};

export function calculateStats(quotes) {
  let sum = 0;
  let count = 0;
  let countZero = 0;
  let min = Number.MAX_VALUE;
  let max = -Number.MAX_VALUE;

  quotes.forEach((quote) => {
    const total = quote.CAD_Quote_Total__c;
    if (!total) {
      countZero += 1;
      return;
    }
    if (total < min) min = total;
    if (total > max) max = total;
    sum += total;
    count += 1;
  });

  const avg = count === 0 ? 0 : sum / count;
  return {
    min: count === 0 ? 0 : min,
    max: count === 0 ? 0 : max,
    avg,
    roundedAvg: avg.toFixed(2),
    nbOfQuotes: count + countZero,
    nbOfQuotesNotZero: count
  };
}

export function shapeRows(quotes) {
  return quotes.map((quote, index) => ({
    ...quote,
    rowNumber: index + 1,
    id: index,
    cellModeClass: MODE_CELL_CLASS[quote.Mode__c] || "",
    showAdditionalContent: false,
    additionalContentKey: `${quote.Id}-additional-content`
  }));
}

export function modeOptionsFrom(quotes) {
  const modes = [...new Set(quotes.map((quote) => quote.Mode__c))];
  return [
    { label: "-- All --", value: "" },
    ...modes.map((mode) => ({ label: mode, value: mode }))
  ];
}
