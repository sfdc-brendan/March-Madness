public with sharing class HistoricalSeedData {

    private static final Map<String, Decimal> SEED_WIN_RATES = new Map<String, Decimal>{
        '1_vs_16' => 0.994, '1_vs_8' => 0.797, '1_vs_9' => 0.203,
        '2_vs_15' => 0.944, '2_vs_7' => 0.667, '2_vs_10' => 0.333,
        '3_vs_14' => 0.854, '3_vs_6' => 0.583, '3_vs_11' => 0.417,
        '4_vs_13' => 0.792, '4_vs_5' => 0.542, '4_vs_12' => 0.458,
        '5_vs_12' => 0.642, '5_vs_4' => 0.458,
        '6_vs_11' => 0.625, '6_vs_3' => 0.417,
        '7_vs_10' => 0.604, '7_vs_2' => 0.333,
        '8_vs_9' => 0.510, '8_vs_1' => 0.203,
        '9_vs_8' => 0.490,
        '10_vs_7' => 0.396,
        '11_vs_6' => 0.375,
        '12_vs_5' => 0.358,
        '13_vs_4' => 0.208,
        '14_vs_3' => 0.146,
        '15_vs_2' => 0.056,
        '16_vs_1' => 0.006
    };

    public static Decimal getHistoricalWinRate(Integer higherSeed, Integer lowerSeed) {
        String key = higherSeed + '_vs_' + lowerSeed;
        if (SEED_WIN_RATES.containsKey(key)) {
            return SEED_WIN_RATES.get(key);
        }
        Integer diff = Math.abs(lowerSeed - higherSeed);
        return Math.min(0.95, Math.max(0.05, 0.5 + (diff * 0.03)));
    }

    public static Decimal getUpsetProbability(Integer favoriteSeed, Integer underdogSeed) {
        return 1.0 - getHistoricalWinRate(favoriteSeed, underdogSeed);
    }

    public static String getSeedMatchupInsight(Integer seed1, Integer seed2) {
        Integer higher = Math.min(seed1, seed2);
        Integer lower = Math.max(seed1, seed2);

        if (seed1 == seed2) {
            return 'This is an even seed matchup between two ' + seed1 + '-seeds.';
        }

        Decimal favoriteRate = getHistoricalWinRate(higher, lower);
        Decimal upsetRate = 1.0 - favoriteRate;

        String insight = higher + '-seeds have beaten ' + lower + '-seeds ' +
            (favoriteRate * 100).setScale(1) + '% of the time historically. ';

        if (upsetRate >= 0.30) {
            insight += 'This is a classic upset-prone matchup.';
        } else if (upsetRate >= 0.15) {
            insight += 'Upsets happen occasionally in this matchup.';
        } else {
            insight += 'Upsets are rare in this matchup.';
        }

        return insight;
    }
}
