/**
 * @AuraEnabled entry points of the RFP tool. Phase 3a ships projectsForAccount (the customer
 * Account component); phase 3b adds the workbench methods. Runs in user mode: RFP records are
 * created and read by pricing users under their own permissions.
 */
public with sharing class RfpController {
  public class ProjectSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal laneCount = 0;
    @AuraEnabled
    public Decimal costedCount = 0;
    @AuraEnabled
    public Decimal soldCount = 0;
    @AuraEnabled
    public Integer bidCount = 0;
    @AuraEnabled
    public List<String> fileNames = new List<String>();
  }

  @AuraEnabled(cacheable=true)
  public static List<ProjectSummary> projectsForAccount(Id accountId) {
    if (accountId == null) {
      return new List<ProjectSummary>();
    }
    try {
      Map<Id, ProjectSummary> byId = new Map<Id, ProjectSummary>();
      for (RFP_Project__c p : [
        SELECT
          Id,
          Name,
          Status__c,
          Due_Date__c,
          Lane_Count__c,
          Costed_Count__c,
          Sold_Count__c
        FROM RFP_Project__c
        WHERE Customer__c = :accountId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 200
      ]) {
        byId.put(p.Id, toSummary(p));
      }
      if (byId.isEmpty()) {
        return new List<ProjectSummary>();
      }
      addBidCounts(byId);
      addFileNames(byId);
      return byId.values();
    } catch (QueryException e) {
      throw userError('RFP projects could not be loaded for this account.');
    }
  }

  private static ProjectSummary toSummary(RFP_Project__c p) {
    ProjectSummary s = new ProjectSummary();
    s.id = p.Id;
    s.name = p.Name;
    s.status = p.Status__c;
    s.dueDate = p.Due_Date__c;
    s.laneCount = p.Lane_Count__c ?? 0;
    s.costedCount = p.Costed_Count__c ?? 0;
    s.soldCount = p.Sold_Count__c ?? 0;
    return s;
  }

  private static void addBidCounts(Map<Id, ProjectSummary> byId) {
    for (AggregateResult ar : [
      SELECT RFP_Project__c pid, COUNT(Id) n
      FROM Benchmark_Rate__c
      WHERE RFP_Project__c IN :byId.keySet()
      WITH USER_MODE
      GROUP BY RFP_Project__c
    ]) {
      byId.get((Id) ar.get('pid')).bidCount = (Integer) ar.get('n');
    }
  }

  private static void addFileNames(Map<Id, ProjectSummary> byId) {
    for (ContentDocumentLink l : [
      SELECT LinkedEntityId, ContentDocument.Title
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :byId.keySet()
      WITH USER_MODE
    ]) {
      byId.get(l.LinkedEntityId).fileNames.add(l.ContentDocument.Title);
    }
  }

  private static AuraHandledException userError(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
