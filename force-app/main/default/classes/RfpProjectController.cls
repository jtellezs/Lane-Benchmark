public with sharing class RfpProjectController {
  public class AccountOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String city;
  }
  // listProjects() renders up to 200 rows at once, so it deliberately excludes the two long-text
  // fields (Column_Mapping__c, Notes__c) that only a single project's detail view needs;
  // DETAIL_FIELDS adds them back for one()/getProject()/saveProject()'s return.
  private static final String LIST_FIELDS =
    'Id, Name, Customer__c, Customer__r.Name, Status__c, Due_Date__c, Default_Margin__c, CurrencyIsoCode, ' +
    'Lane_Count__c, Costed_Count__c, Sold_Count__c, Source_File_Name__c, LastModifiedDate';
  private static final String DETAIL_FIELDS =
    LIST_FIELDS + ', Column_Mapping__c, Notes__c';
  private static final Integer MAX_BASE64 = 4200000;

  @AuraEnabled
  public static List<RFP_Project__c> listProjects() {
    try {
      return Database.queryWithBinds(
        'SELECT ' +
          LIST_FIELDS +
          ' FROM RFP_Project__c ORDER BY LastModifiedDate DESC LIMIT 200',
        new Map<String, Object>(),
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw RfpUserError.of('RFP projects could not be loaded.');
    }
  }

  @AuraEnabled
  public static RFP_Project__c getProject(Id projectId) {
    try {
      return one(projectId);
    } catch (Exception e) {
      throw RfpUserError.of('The RFP project could not be loaded.');
    }
  }

  @AuraEnabled
  public static RFP_Project__c saveProject(String projectJson) {
    try {
      RFP_Project__c posted = (RFP_Project__c) JSON.deserialize(
        projectJson,
        RFP_Project__c.class
      );
      Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(
        projectJson
      );
      RFP_Project__c p = new RFP_Project__c(Id = posted.Id);
      for (
        String f : new List<String>{
          'Name',
          'Customer__c',
          'Status__c',
          'Due_Date__c',
          'Default_Margin__c',
          'CurrencyIsoCode',
          'Notes__c',
          'Column_Mapping__c',
          'Source_File_Name__c'
        }
      ) {
        if (fields.containsKey(f)) {
          p.put(f, posted.get(f));
        }
      }
      // The owner's rule (2026-09-18): a project created without a customer is a market test,
      // and lands on the Market Test account. Customer__c is a master-detail, so there is no
      // such thing as a project without one - this is what "no customer" means here.
      if (p.Id == null && p.Customer__c == null) {
        p.Customer__c = MarketTestSetting.accountId();
      }
      SObject clean = Security.stripInaccessible(
          p.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
          new List<RFP_Project__c>{ p }
        )
        .getRecords()[0];
      if (p.Id == null) {
        Database.insert(clean, AccessLevel.USER_MODE);
      } else {
        Database.update(clean, AccessLevel.USER_MODE);
      }
      return one(clean.Id);
    } catch (Exception e) {
      throw RfpUserError.of(
        'The RFP project could not be saved. ' + RfpUserError.safe(e)
      );
    }
  }

  // Column_Mapping__c is a long text area field, which SOQL cannot filter in a WHERE clause
  // (adaptation from the brief's "AND Column_Mapping__c != NULL" filter, which this org rejects
  // with "field 'Column_Mapping__c' can not be filtered in a query call"); the latest-first scan
  // below finds the same "latest project of that customer with a non-blank mapping" record.
  @AuraEnabled
  public static String columnMappingFor(Id accountId) {
    try {
      for (RFP_Project__c p : [
        SELECT Column_Mapping__c
        FROM RFP_Project__c
        WHERE Customer__c = :accountId
        WITH USER_MODE
        ORDER BY LastModifiedDate DESC
        LIMIT 200
      ]) {
        if (String.isNotBlank(p.Column_Mapping__c)) {
          return p.Column_Mapping__c;
        }
      }
      return null;
    } catch (Exception e) {
      throw RfpUserError.of('The saved column mapping could not be loaded.');
    }
  }

  @AuraEnabled
  public static List<AccountOption> searchAccounts(String term, String kind) {
    List<AccountOption> out = new List<AccountOption>();
    if (term == null || term.trim().length() < 2) {
      return out;
    }
    List<String> types = kind == 'carrier'
      ? new List<String>{ 'Carrier', 'New_Carrier' }
      : new List<String>{ 'Customer', 'New_Customer' };
    String pattern = '%' + LaneSearchQueryBuilder.escapeLike(term.trim()) + '%';
    try {
      for (Account a : [
        SELECT Id, Name, BillingCity
        FROM Account
        WHERE Name LIKE :pattern AND RecordType.DeveloperName IN :types
        WITH USER_MODE
        ORDER BY Name
        LIMIT 10
      ]) {
        AccountOption o = new AccountOption();
        o.id = a.Id;
        o.name = a.Name;
        o.city = a.BillingCity;
        out.add(o);
      }
      return out;
    } catch (Exception e) {
      throw RfpUserError.of('Accounts could not be searched.');
    }
  }

  @AuraEnabled
  public static Id attachFile(Id projectId, String fileName, String base64) {
    if (base64 == null || base64.length() > MAX_BASE64) {
      throw RfpUserError.of(
        'The file is larger than 3 MB. Split it and upload the parts.'
      );
    }
    try {
      ContentVersion cv = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName,
        VersionData = EncodingUtil.base64Decode(base64)
      );
      Database.insert(cv, AccessLevel.USER_MODE);
      Id docId = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        WITH USER_MODE
      ]
      .ContentDocumentId;
      Database.insert(
        new ContentDocumentLink(
          ContentDocumentId = docId,
          LinkedEntityId = projectId,
          ShareType = 'V',
          Visibility = 'AllUsers'
        ),
        AccessLevel.USER_MODE
      );
      Database.update(
        new RFP_Project__c(
          Id = projectId,
          Source_File_Name__c = fileName.left(255)
        ),
        AccessLevel.USER_MODE
      );
      return docId;
    } catch (Exception e) {
      throw RfpUserError.of(
        'The file could not be attached. ' + RfpUserError.safe(e)
      );
    }
  }

  private static RFP_Project__c one(Id projectId) {
    return (RFP_Project__c) Database.queryWithBinds(
      'SELECT ' + DETAIL_FIELDS + ' FROM RFP_Project__c WHERE Id = :projectId',
      new Map<String, Object>{ 'projectId' => projectId },
      AccessLevel.USER_MODE
    )[0];
  }
}
