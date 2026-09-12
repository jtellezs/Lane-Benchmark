@IsTest
private class RfpPricingMathTest {
  @IsTest
  static void sellAndMarginRoundHalfUpToCents() {
    System.assertEquals(1419.74, RfpPricingMath.sellFor(1234.56, 15));
    System.assertEquals(1150.00, RfpPricingMath.sellFor(1000, 15));
    System.assertEquals(null, RfpPricingMath.sellFor(0, 15));
    System.assertEquals(null, RfpPricingMath.sellFor(1000, null));
    System.assertEquals(15.00, RfpPricingMath.marginFor(1000, 1150));
    System.assertEquals(-10.00, RfpPricingMath.marginFor(1000, 900));
    System.assertEquals(0.33, RfpPricingMath.marginFor(3, 3.01));
    System.assertEquals(null, RfpPricingMath.marginFor(0, 100));
    System.assertEquals(null, RfpPricingMath.marginFor(1000, null));
    System.assertEquals(
      null,
      RfpPricingMath.marginFor(1, 100000),
      'does not fit Margin__c'
    );
  }

  @IsTest
  static void recomputeFollowsTheSellSource() {
    RFP_Lane__c byMargin = new RFP_Lane__c(Cost__c = 2000, Margin__c = 20);
    RfpPricingMath.recompute(byMargin, 15);
    System.assertEquals(2400.00, byMargin.Sell__c);
    System.assertEquals('Margin', byMargin.Sell_Source__c);

    RFP_Lane__c noMargin = new RFP_Lane__c(Cost__c = 2000);
    RfpPricingMath.recompute(noMargin, 15);
    System.assertEquals(15, noMargin.Margin__c, 'project default used');
    System.assertEquals(2300.00, noMargin.Sell__c);

    RFP_Lane__c manual = new RFP_Lane__c(
      Cost__c = 2000,
      Sell__c = 3000,
      Sell_Source__c = 'Manual',
      Margin__c = 15
    );
    RfpPricingMath.recompute(manual, 15);
    System.assertEquals(3000, manual.Sell__c, 'a typed sell never moves');
    System.assertEquals(50.00, manual.Margin__c);
    System.assertEquals('Manual', manual.Sell_Source__c);

    RFP_Lane__c manualNoSell = new RFP_Lane__c(
      Cost__c = 2000,
      Sell_Source__c = 'Manual',
      Margin__c = 10
    );
    RfpPricingMath.recompute(manualNoSell, 15);
    System.assertEquals(
      2200.00,
      manualNoSell.Sell__c,
      'no sell yet: margin drives'
    );
    System.assertEquals('Margin', manualNoSell.Sell_Source__c);
  }
}
