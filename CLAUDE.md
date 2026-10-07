# Lane Benchmark - Project Notes

## Org
- Alias: postproduc
- User: julian.tellez@trans-pro.com.postproduc
- Access: `sf data query --target-org postproduc`
- Source code: `c:/Projects/Lane Benchmark/PricingDepartemnt/PricingDepartemnt/`
- GitHub: https://github.com/IulianEnescu78/PricingDepartment.git (origin)

---

## CURRENT STATUS — Production Deployment In Progress

### What we are trying to do
Deploy the Lane Benchmark + RFP Tool to **production** using **Flosum**.
Flosum retrieves metadata from **postproduc** (sandbox) and deploys to production.

### What we tried and why it failed

**Attempt 1 — Deploy objects only (no fields)**
Failed with: `Variable does not exist: Rate__c`, `Invalid type: LaneSearchException`, etc.
Reason: In Flosum, CustomObject and CustomField are **separate components**. Deploying just the object shell without fields means Apex can't compile — it references fields that don't exist yet.

**Attempt 2 — Change sharingModel to Private temporarily**
`RFP_Lane__c` and `RFP_Project__c` both have `sharingModel = ControlledByParent` (master-detail relationships). Production doesn't have the objects yet so deploying `ControlledByParent` with no master-detail field present fails.
We tried changing to `Private` but postproduc already has the master-detail fields so it rejected the change there too. Files were reverted — both object-meta.xml files are back to `ControlledByParent`.

**Attempt 3 — Deploy everything at once (objects + fields + Apex + LWC)**
Still failing because Flosum needs the CustomField components explicitly selected per object.
Errors like `No such column 'City__c' on entity 'Pricing_Place__c'` confirm that `Pricing_Place__c` fields are missing from the deployment package.

### What needs to happen next
In Flosum, search for each object and **select all its CustomField components** explicitly. There is no automatic "include all fields" when you add a CustomObject — you must add fields separately.

**Objects whose fields must all be selected in Flosum:**
- `RFP_Project__c` — 10 custom fields
- `RFP_Lane__c` — 47 custom fields
- `Benchmark_Rate__c` — 36 custom fields
- `Pricing_Place__c` — 12 custom fields
- `Truck_Route__c` — 10 custom fields
- `Pricing_Department_Setting__mdt` — 2 custom fields
- `Truck_Routing_Setting__mdt` — 6 custom fields
- `Intercompany_Carrier__mdt` — 2 custom fields
- `Handoff_Point__mdt` — 2 custom fields

**In Flosum:** search by object name (e.g. "Benchmark_Rate__c") to filter all its CustomField components, then select all. Repeat for each object above.

**Then deploy everything in ONE shot** — objects + fields + all Apex + all LWC + permission sets + everything else from the list below.

### Test classes to specify (RunSpecifiedTests)
```
BenchmarkRateServiceTest, BidSearchQueryBuilderTest, BidSearchServiceTest,
CarrierLeadServiceTest, CarrierSplitLimitsTest, CarrierSplitSecurityTest,
CarrierWarningTest, ExchangeRatesTest, HandoffPointsTest, IntercompanyCarriersTest,
LaneBenchmarkControllerTest, LaneBenchmarkPlaceServiceTest, LaneKeyMatcherTest,
LaneQueriesTest, LaneSearchExclusionsTest, LaneSearchQueryBuilderTest,
LaneSearchServiceTest, LaneTrendBucketsTest, LaneTrendControllerTest,
LaneTrendQueriesTest, LaneTrendServiceTest, MapboxGeocoderTest,
MapboxTruckRouteTest, MarketTestControllerTest, MarketTestServiceTest,
MarketTestSettingTest, PlaceBuilderBatchTest, PlaceNormalizerTest,
PricingTestDataFactory, PricingTestDataFactoryTest, RfpBidAccessTest,
RfpBidControllerTest, RfpBulkControllerTest, RfpBulkServiceTest,
RfpControllerTest, RfpHistoryServiceTest, RfpImportServiceTest,
RfpLaneControllerTest, RfpLaneSimilarityTest, RfpPricingMathTest,
RfpProjectControllerTest, RfpSecurityTest, RfpTestDataFactory,
RfpTestDataFactoryTest, RouteMapUrlTest, SplitEstimatesTest,
SplitLaneControllerTest, SplitLaneServiceTest, SplitTestDataTest,
TripMilesServiceTest
```

### After deployment — manual steps required
1. **Mapbox API Key** — Setup → Custom Settings → TPRO_KPI__c → Manage → Org Default → set `Mapbox_Api_Key__c`
2. **Market Test Account ID** — Setup → Custom Metadata → Pricing Department Setting → Default record → update `Market_Test_Account_Id__c` to production Account ID
3. **Assign permission sets** to pricing team users: `Lane_Benchmark_User` + `RFP_Tool_User`
4. **Remote Site + CSP** (do manually in production Setup): `MapBox` remote site + `Mapbox_API` CSP trusted site
5. **Pricing_Place__c data** — this is data not metadata, Flosum won't move it. Need to export from postproduc and import to production separately.

### Test results (confirmed in postproduc)
- 92/92 test methods passed, 0 failures
- Coverage: 76% (above the 75% Salesforce requirement)
- All classes above 75% individually

---

## Full Deployment Component List

### Custom Objects (+ all their fields)
`Pricing_Place__c`, `RFP_Project__c`, `RFP_Lane__c`, `Benchmark_Rate__c`, `Truck_Route__c`

### Custom Metadata Types + Records
- `Pricing_Department_Setting__mdt` → record: Default
- `Truck_Routing_Setting__mdt` → record: Default
- `Intercompany_Carrier__mdt` → records: Tpml_TP_Org, Lessard_Org
- `Handoff_Point__mdt` → records: Laredo_TX_US, San_Diego_CA_US, Calexico_CA_US

### Apex Classes
`BenchmarkRateService`, `BidSearchQueryBuilder`, `BidSearchService`, `CarrierLeadController`, `CarrierLeadResult`, `CarrierLeadService`, `CarrierWarning`, `ExchangeRates`, `FreightPlanReader`, `HandoffPoints`, `IntercompanyCarriers`, `LaneBenchmarkController`, `LaneBenchmarkPlaceService`, `LaneKeyMatcher`, `LaneLoadFilters`, `LaneQueries`, `LaneSearchException`, `LaneSearchExclusions`, `LaneSearchFilters`, `LaneSearchQueryBuilder`, `LaneSearchRequest`, `LaneSearchResult`, `LaneSearchService`, `LaneTrend`, `LaneTrendBuckets`, `LaneTrendController`, `LaneTrendQueries`, `LaneTrendScope`, `LaneTrendService`, `LaneTrendSummary`, `MapboxException`, `MapboxGeocoder`, `MapboxHttp`, `MapboxResponseParser`, `MapboxTruckRoute`, `MarketTestController`, `MarketTestFilter`, `MarketTestService`, `MarketTestSetting`, `PlaceBuilderBatch`, `PlaceNormalizer`, `PlaceUsageBatch`, `PlaceWriteBatch`, `RfpBidAccess`, `RfpBidController`, `RfpBulkController`, `RfpBulkService`, `RfpController`, `RfpHistoryController`, `RfpHistoryService`, `RfpImportService`, `RfpLaneController`, `RfpLaneRouteService`, `RfpLaneSimilarity`, `RfpPricingInput`, `RfpPricingMath`, `RfpProjectController`, `RfpUserError`, `RouteMapUrl`, `SplitEstimates`, `SplitLaneController`, `SplitLaneResult`, `SplitLaneService`, `SplitTestData`, `TripMilesService`, `TripRouteView`, `TruckRoute`

### Apex Test Classes
`BenchmarkRateServiceTest`, `BidSearchQueryBuilderTest`, `BidSearchServiceTest`, `CarrierLeadServiceTest`, `CarrierSplitLimitsTest`, `CarrierSplitSecurityTest`, `CarrierWarningTest`, `ExchangeRatesTest`, `HandoffPointsTest`, `IntercompanyCarriersTest`, `LaneBenchmarkControllerTest`, `LaneBenchmarkPlaceServiceTest`, `LaneKeyMatcherTest`, `LaneQueriesTest`, `LaneSearchExclusionsTest`, `LaneSearchQueryBuilderTest`, `LaneSearchServiceTest`, `LaneTrendBucketsTest`, `LaneTrendControllerTest`, `LaneTrendQueriesTest`, `LaneTrendServiceTest`, `MapboxGeocoderTest`, `MapboxTruckRouteTest`, `MarketTestControllerTest`, `MarketTestServiceTest`, `MarketTestSettingTest`, `PlaceBuilderBatchTest`, `PlaceNormalizerTest`, `PricingTestDataFactory`, `PricingTestDataFactoryTest`, `RfpBidAccessTest`, `RfpBidControllerTest`, `RfpBulkControllerTest`, `RfpBulkServiceTest`, `RfpControllerTest`, `RfpHistoryServiceTest`, `RfpImportServiceTest`, `RfpLaneControllerTest`, `RfpLaneSimilarityTest`, `RfpPricingMathTest`, `RfpProjectControllerTest`, `RfpSecurityTest`, `RfpTestDataFactory`, `RfpTestDataFactoryTest`, `RouteMapUrlTest`, `SplitEstimatesTest`, `SplitLaneControllerTest`, `SplitLaneServiceTest`, `SplitTestDataTest`, `TripMilesServiceTest`

### Apex Trigger
`BenchmarkRateTrigger`

### LWC Components
`carrierLeadRules`, `carrierLeads`, `distanceUnit`, `distanceUnitToggle`, `helpCenter`, `helpContent`, `helpHint`, `laneBenchmark`, `laneBenchmarkCsv`, `laneBenchmarkFilters`, `laneBenchmarkMap`, `laneBenchmarkPlacePicker`, `laneBenchmarkResults`, `laneBenchmarkSelling`, `laneBenchmarkStats`, `laneBenchmarkStorage`, `laneTrendChart`, `marginMath`, `marketTestRates`, `rfpAccountPicker`, `rfpBatch`, `rfpBidForm`, `rfpBulk`, `rfpBulkBar`, `rfpColumnMapper`, `rfpExport`, `rfpHeaderGuess`, `rfpLaneFilter`, `rfpLanePanel`, `rfpLaneTable`, `rfpLaneTemplate`, `rfpMath`, `rfpPricing`, `rfpProjectList`, `rfpProjectsForAccount`, `rfpSheet`, `rfpSheetLoader`, `rfpTool`, `rfpToolbar`, `rfpUpload`, `rfpWorkbook`, `routeMap`, `splitLaneOptions`

### Static Resources
`helpCenter`, `sheetJs`

### Lightning Message Channel
`Distance_Unit`

### Lightning Pages
`Help_Center`, `Lane_Benchmark`, `RFP_Tool`

### Tabs
`Help_Center`, `Lane_Benchmark`, `RFP_Tool`

### Apps
`Lane_Benchmark`, `TransPro`

### Permission Sets
`Lane_Benchmark_User`, `RFP_Tool_User`

### Custom Permission
`RFP_Tool`

### Security (manual in production Setup)
- RemoteSiteSetting: `MapBox`
- CspTrustedSite: `Mapbox_API`

### Validation Rule
`Benchmark_Rate__c.Carrier_Or_Name_Required`

---

## Observations to Investigate

1. **Field-level security on RFP_Lane__c** — FieldDefinition API returned limited fields. Was a permissions issue (missing RFP_Tool_User). Resolved by assigning permission set.

2. **Market Test filter toggle awareness** — INCLUDE / EXCLUDE / ONLY toggle added Sept 2026. Confirm visible and labeled clearly in UI.

3. **Bid expiration is 30 days by default** — includeExpiredBids flag exists but UI exposure unclear.

4. **Unresolved lane ends can silently stall pricing** — Hist_Status = Unresolved when import can't match origin/destination.

5. **Trend chart truncation message** — caps at 11,000 rows, sets truncated = true. Confirm UI shows warning.
