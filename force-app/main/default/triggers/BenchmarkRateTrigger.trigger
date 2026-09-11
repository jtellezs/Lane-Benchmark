trigger BenchmarkRateTrigger on Benchmark_Rate__c(
  before insert,
  before update
) {
  BenchmarkRateService.applyLanes(Trigger.new);
}
