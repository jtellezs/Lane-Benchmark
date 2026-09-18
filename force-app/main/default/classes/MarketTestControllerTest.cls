/**
 * Phase 9. The controller is thin, so these tests prove the two things it owns: the round trip
 * the page depends on, and that a refusal reaches the screen as one sentence rather than a
 * platform dump.
 */
@IsTest
private class MarketTestControllerTest {
  private static Pricing_Place__c origin;
  private static Pricing_Place__c destination;

  private static void lane() {
    origin = RfpTestDataFactory.createPlace(
      'Toronto',
      'ON',
      'CA',
      43.65,
      -79.38,
      'M5V'
    );
    destination = RfpTestDataFactory.createPlace(
      'Montreal',
      'QC',
      'CA',
      45.5,
      -73.57,
      'H3B'
    );
  }

  private static String rateJson(Decimal rate) {
    return JSON.serialize(
      new Benchmark_Rate__c(
        Carrier_Name__c = 'Ad Hoc Carrier',
        Rate__c = rate,
        CurrencyIsoCode = 'CAD'
      )
    );
  }

  @IsTest
  static void aSavedRateComesBackFromGetRates() {
    lane();
    Test.startTest();
    Benchmark_Rate__c saved = MarketTestController.saveRate(
      rateJson(2400),
      origin.Id,
      destination.Id
    );
    List<Benchmark_Rate__c> rates = MarketTestController.getRates(
      origin.Id,
      destination.Id
    );
    Test.stopTest();
    System.assertEquals(1, rates.size());
    System.assertEquals(saved.Id, rates[0].Id);
    System.assertEquals(2400, rates[0].Rate__c);
  }

  @IsTest
  static void anUnreadableRateIsRefusedWithAShortSentence() {
    lane();
    String message = '';
    Test.startTest();
    try {
      MarketTestController.saveRate('{not json', origin.Id, destination.Id);
    } catch (Exception e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assert(
      message.contains('could not be read'),
      'the pricer is told to try again, not shown a parser dump: ' + message
    );
  }

  @IsTest
  static void aMissingLaneEndReachesTheScreenAsItsMessage() {
    lane();
    String message = '';
    Test.startTest();
    try {
      MarketTestController.getRates(origin.Id, null);
    } catch (Exception e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(MarketTestService.NO_PLACES, message);
  }

  @IsTest
  static void deletingSomebodyElsesRateIsRefused() {
    lane();
    User other = RfpTestDataFactory.restrictedUser('RFP_Tool_User');
    if (other == null) {
      return;
    }
    Benchmark_Rate__c theirs;
    System.runAs(other) {
      theirs = MarketTestService.save(
        new Benchmark_Rate__c(
          Carrier_Name__c = 'Theirs',
          Rate__c = 2000,
          CurrencyIsoCode = 'CAD'
        ),
        origin.Id,
        destination.Id
      );
    }
    String message = '';
    Test.startTest();
    try {
      MarketTestController.deleteRate(theirs.Id);
    } catch (Exception e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(MarketTestService.NOT_YOURS, message);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :theirs.Id]
    );
  }

  @IsTest
  static void myOwnRateCanBeUpdatedAndDeleted() {
    lane();
    Benchmark_Rate__c saved = MarketTestController.saveRate(
      rateJson(2400),
      origin.Id,
      destination.Id
    );
    Test.startTest();
    Benchmark_Rate__c changed = MarketTestController.updateRate(
      JSON.serialize(
        new Benchmark_Rate__c(
          Id = saved.Id,
          Carrier_Name__c = 'Ad Hoc Carrier',
          Rate__c = 2650,
          CurrencyIsoCode = 'CAD'
        )
      )
    );
    MarketTestController.deleteRate(changed.Id);
    Test.stopTest();
    System.assertEquals(
      2650,
      changed.Rate__c,
      'the rate its owner recorded is editable'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Benchmark_Rate__c WHERE Id = :saved.Id],
      'and deletable'
    );
  }

  @IsTest
  static void anUnreadableUpdateIsRefusedWithAShortSentence() {
    lane();
    String message = '';
    Test.startTest();
    try {
      MarketTestController.updateRate('{not json');
    } catch (Exception e) {
      message = e.getMessage();
    }
    Test.stopTest();
    System.assert(
      message.contains('could not be read'),
      'expected the short sentence, got: ' + message
    );
  }

  @IsTest
  static void aWrongLaneEndAndABadCarrierBothGiveOneSentence() {
    lane();
    Benchmark_Rate__c saved = MarketTestController.saveRate(
      rateJson(2000),
      origin.Id,
      destination.Id
    );
    // Carrier__c looks up an Account, so a place id makes the DML fail rather than the guard.
    String badCarrier = JSON.serialize(
      new Benchmark_Rate__c(
        Carrier__c = origin.Id,
        Rate__c = 1,
        CurrencyIsoCode = 'CAD'
      )
    );
    String wrongEnd = '';
    String saveMessage = '';
    String updateMessage = '';
    Test.startTest();
    try {
      MarketTestController.getRates(saved.Id, destination.Id);
    } catch (Exception e) {
      wrongEnd = e.getMessage();
    }
    try {
      MarketTestController.saveRate(badCarrier, origin.Id, destination.Id);
    } catch (Exception e) {
      saveMessage = e.getMessage();
    }
    try {
      MarketTestController.updateRate(
        JSON.serialize(
          new Benchmark_Rate__c(Id = saved.Id, Carrier__c = origin.Id)
        )
      );
    } catch (Exception e) {
      updateMessage = e.getMessage();
    }
    Test.stopTest();
    System.assertEquals(
      MarketTestService.NO_PLACES,
      wrongEnd,
      'an id of the wrong kind reads as a missing lane end, never a platform dump'
    );
    System.assert(
      saveMessage.contains('could not be saved'),
      'expected the short sentence, got: ' + saveMessage
    );
    System.assert(
      updateMessage.contains('could not be saved'),
      'expected the short sentence, got: ' + updateMessage
    );
  }
}
