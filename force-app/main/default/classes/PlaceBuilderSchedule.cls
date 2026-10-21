/**
 * Lets the place dictionary rebuild run on a schedule instead of by hand.
 *
 * PlaceBuilderBatch is a Batchable, and neither Setup's Schedule Apex nor System.schedule will
 * accept one - both require a Schedulable - so until this class existed the dictionary could only
 * be rebuilt by someone remembering to run one line of anonymous Apex. That matters because two
 * things go stale on their own: a shipper or consignee account created this week is a city nobody
 * can search until the batch runs again, and Load_Count_365d__c is a rolling 365-day count that
 * orders the place picker.
 *
 * Rerunning is safe by design - PlaceBuilderBatch never deletes a place and never overwrites
 * Aliases__c or Active__c - which is what makes a standing schedule reasonable rather than risky.
 *
 * This class only starts PlaceBuilderBatch. That batch chains PlaceWriteBatch, which chains
 * PlaceUsageBatch; nothing here needs to know that order.
 */
public without sharing class PlaceBuilderSchedule implements Schedulable {
  /** One stable name, so scheduleWeekly() can find and replace an existing schedule. */
  public static final String JOB_NAME = 'Pricing Department - place dictionary rebuild';

  /**
   * Sunday 02:00. Weekly rather than nightly because the dictionary changes slowly and a rebuild
   * reads every location account referenced by a stop - 58,755 of them in PostProduc, about three
   * minutes - and rather than monthly because a new customer's city should not stay unsearchable
   * for weeks. Load_Count_365d__c drifts by only 1/365 a day, so weekly keeps the picker honest.
   */
  public static final String CRON_WEEKLY = '0 0 2 ? * SUN';

  /** Matches the scope the README records for the manual run. */
  @TestVisible
  private static final Integer SCOPE = 2000;

  public void execute(SchedulableContext sc) {
    Database.executeBatch(new PlaceBuilderBatch(), SCOPE);
  }

  /**
   * Schedules the weekly rebuild, replacing any schedule of the same name.
   *
   * The abort is not tidiness: System.schedule throws on a duplicate name rather than replacing,
   * so without it a second run of this line - during a go-live retry, say - fails with an error
   * that reads like a problem when it is not. Safe to run as many times as you like.
   */
  public static String scheduleWeekly() {
    for (CronTrigger existing : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :JOB_NAME AND State != 'DELETED'
      WITH USER_MODE
    ]) {
      System.abortJob(existing.Id);
    }
    return System.schedule(JOB_NAME, CRON_WEEKLY, new PlaceBuilderSchedule());
  }
}