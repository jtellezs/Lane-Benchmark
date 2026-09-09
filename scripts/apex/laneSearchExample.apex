// Montreal -> Toronto at each precision, last 90 days. Read-only. Prints rows, truncation, and elapsed ms.
List<LaneSearchRequest.Precision> precisions = new List<LaneSearchRequest.Precision>{
  LaneSearchRequest.Precision.CITY,
  LaneSearchRequest.Precision.PROVINCE,
  LaneSearchRequest.Precision.ZIP3,
  LaneSearchRequest.Precision.RADIUS
};
for (LaneSearchRequest.Precision p : precisions) {
  LaneSearchRequest r = new LaneSearchRequest();
  r.originKey = 'montreal|qc|ca';
  r.destinationKey = 'toronto|on|ca';
  r.originPrecision = p;
  r.destinationPrecision = p;
  r.originRadius = 100;
  r.destinationRadius = 100;
  r.lookbackDays = 90;
  LaneSearchResult res = LaneSearchService.search(r);
  System.debug(
    'LANE ' +
      p +
      ' rows=' +
      res.rows.size() +
      ' truncated=' +
      res.truncated +
      ' ms=' +
      res.elapsedMs +
      ' stats=' +
      JSON.serialize(res.statsByCurrency)
  );
}
LaneSearchRequest r2 = new LaneSearchRequest();
r2.originKey = 'montreal|qc|ca';
r2.destinationKey = 'toronto|on|ca';
r2.originPrecision = LaneSearchRequest.Precision.RADIUS;
r2.destinationPrecision = LaneSearchRequest.Precision.RADIUS;
r2.originRadius = 100;
r2.destinationRadius = 100;
r2.lookbackDays = 365;
r2.includeStopGeolocation = false;
System.debug(
  'LANE RADIUS-365-accountsOnly ms=' + LaneSearchService.search(r2).elapsedMs
);
r2.includeStopGeolocation = true;
System.debug(
  'LANE RADIUS-365-withStops ms=' + LaneSearchService.search(r2).elapsedMs
);
