@IsTest
private class PlaceBuilderScheduleTest {
  /** Sunday at 02:00, the cadence scheduleWeekly() commits to. */
  private static final String SUNDAY_0200 = '0 0 2 ? * SUN';

  /**
   * Mutation (observed): empty PlaceBuilderSchedule.execute() - no AsyncApexJob for
   * PlaceBuilderBatch exists after the schedule fires, and the second assertion fails. That is the
   * whole job of this class: Setup's Schedule Apex and System.schedule both refuse a class that is
   * not Schedulable, so without this wrapper the place dictionary can only ever be rebuilt by hand.
   */
  @IsTest
  static void firingTheScheduleStartsThePlaceDictionaryRebuild() {
    Test.startTest();
    String jobId = System.schedule(
      'PlaceBuilderScheduleTest rebuild',
      SUNDAY_0200,
      new PlaceBuilderSchedule()
    );
    // stopTest fires the scheduled job, which enqueues the batch. The batch itself does not run
    // here - Apex flushes one level of async in a test - so this asserts that it was started,
    // which is the only thing this class is responsible for.
    Test.stopTest();

    CronTrigger scheduled = [
      SELECT CronExpression, TimesTriggered
      FROM CronTrigger
      WHERE Id = :jobId
    ];
    System.assertEquals(
      SUNDAY_0200,
      scheduled.CronExpression,
      'the schedule keeps the cadence it was given'
    );

    List<AsyncApexJob> started = [
      SELECT Id, ApexClass.Name
      FROM AsyncApexJob
      WHERE JobType = 'BatchApex' AND ApexClass.Name = 'PlaceBuilderBatch'
    ];
    System.assertEquals(
      1,
      started.size(),
      'firing the schedule starts PlaceBuilderBatch exactly once; PlaceWriteBatch and ' +
      'PlaceUsageBatch are chained by the batch itself, not started here'
    );
  }

  /**
   * The cadence is in version control rather than in whoever last used Setup. Weekly because the
   * dictionary changes slowly - new shipper and consignee accounts - while Load_Count_365d__c is a
   * rolling 365-day count that drifts by only 1/365 a day.
   *
   * Mutation (traced, not run): change CRON_WEEKLY and this fails, which is the point - the cadence
   * is a decision, so moving it should be a deliberate edit with a reason, not a quiet one. Traced
   * rather than observed because the assertion compares the class's constant against a literal
   * here, with no runtime step between them that could mask a difference.
   */
  @IsTest
  static void scheduleWeeklyCommitsToSundayNightsSoNobodyHasToRememberTheCron() {
    Test.startTest();
    String jobId = PlaceBuilderSchedule.scheduleWeekly();
    Test.stopTest();

    System.assertEquals(
      SUNDAY_0200,
      [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId].CronExpression
    );
    System.assertEquals(
      PlaceBuilderSchedule.JOB_NAME,
      [SELECT CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId]
      .CronJobDetail.Name,
      'one stable name, so a second run replaces the schedule rather than stacking another'
    );
  }

  /**
   * Mutation (observed): drop the abortJob loop from scheduleWeekly and the second call throws
   * "That job name is already in use", because System.schedule replaces nothing. A runbook step
   * that fails the second time it is run reads like a fault when it is not.
   */
  @IsTest
  static void schedulingTwiceReplacesTheJobRatherThanRefusing() {
    Test.startTest();
    PlaceBuilderSchedule.scheduleWeekly();
    String second = PlaceBuilderSchedule.scheduleWeekly();
    Test.stopTest();

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :PlaceBuilderSchedule.JOB_NAME
      ],
      'one schedule, not two'
    );
    System.assertNotEquals(
      null,
      second,
      'and the second call still returns its job id'
    );
  }
}