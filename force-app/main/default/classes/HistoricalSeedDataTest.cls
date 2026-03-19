@isTest
private class HistoricalSeedDataTest {

    @isTest
    static void testGetHistoricalWinRate_1vs16() {
        Decimal winRate = HistoricalSeedData.getHistoricalWinRate(1, 16);
        System.assertEquals(0.994, winRate, '1-seed vs 16-seed should have 99.4% win rate');
    }

    @isTest
    static void testGetHistoricalWinRate_5vs12() {
        Decimal winRate = HistoricalSeedData.getHistoricalWinRate(5, 12);
        System.assertEquals(0.642, winRate, '5-seed vs 12-seed should have 64.2% win rate');
    }

    @isTest
    static void testGetHistoricalWinRate_UnknownMatchup() {
        Decimal winRate = HistoricalSeedData.getHistoricalWinRate(3, 10);

        System.assertNotEquals(null, winRate, 'Unknown matchup should return a calculated default');
        System.assert(winRate >= 0.05 && winRate <= 0.95,
            'Default win rate should be between 0.05 and 0.95, got: ' + winRate);
    }

    @isTest
    static void testGetUpsetProbability() {
        Decimal upsetProb = HistoricalSeedData.getUpsetProbability(1, 16);
        Decimal expectedUpset = 1.0 - 0.994;

        System.assertEquals(expectedUpset, upsetProb,
            'Upset probability should be 1 minus the favorite win rate');
    }

    @isTest
    static void testGetSeedMatchupInsight() {
        String insight = HistoricalSeedData.getSeedMatchupInsight(1, 16);

        System.assertNotEquals(null, insight, 'Insight should not be null');
        System.assert(insight.length() > 0, 'Insight should not be empty');
        System.assert(insight.contains('1-seeds'), 'Insight should reference the higher seed');
    }

    @isTest
    static void testGetSeedMatchupInsight_EqualSeeds() {
        String insight = HistoricalSeedData.getSeedMatchupInsight(5, 5);

        System.assert(insight.contains('even seed matchup'),
            'Equal seed insight should mention even matchup');
    }

    @isTest
    static void testGetSeedMatchupInsight_UpsetProne() {
        String insight = HistoricalSeedData.getSeedMatchupInsight(5, 12);

        System.assertNotEquals(null, insight, 'Insight for upset-prone matchup should not be null');
        System.assert(insight.contains('5-seeds'), 'Insight should reference 5-seeds');
    }
}
