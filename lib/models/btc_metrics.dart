class MiningMetrics {
  final double hashrateEhs; // EH/s
  final double difficultyAdjustmentPercent;
  final int blocksUntilAdjustment;
  final DateTime? estimatedAdjustmentDate;
  final double currentDifficulty;

  const MiningMetrics({
    required this.hashrateEhs,
    required this.difficultyAdjustmentPercent,
    required this.blocksUntilAdjustment,
    this.estimatedAdjustmentDate,
    required this.currentDifficulty,
  });
}

class MempoolMetrics {
  final int pendingTxCount;
  final double totalFeeBtc;
  final int mempoolSizeBytes;
  final int feeSlowSatsPerVb;
  final int feeMediumSatsPerVb;
  final int feeFastSatsPerVb;

  const MempoolMetrics({
    required this.pendingTxCount,
    required this.totalFeeBtc,
    required this.mempoolSizeBytes,
    required this.feeSlowSatsPerVb,
    required this.feeMediumSatsPerVb,
    required this.feeFastSatsPerVb,
  });
}

class MarketMetrics {
  final double marketCapUsd;
  final double realizedCapUsd;
  final double mvrv; // market cap / realized cap
  final double circulatingSupply;
  final double volume24hUsd;

  const MarketMetrics({
    required this.marketCapUsd,
    required this.realizedCapUsd,
    required this.mvrv,
    required this.circulatingSupply,
    required this.volume24hUsd,
  });
}

class SentimentMetrics {
  final double fearGreedIndex; // 0-100
  final String fearGreedLabel;
  final double? painIndex;

  const SentimentMetrics({
    required this.fearGreedIndex,
    required this.fearGreedLabel,
    this.painIndex,
  });

  static String labelFromScore(double score) {
    if (score <= 20) return 'Extreme Fear';
    if (score <= 40) return 'Fear';
    if (score <= 60) return 'Neutral';
    if (score <= 80) return 'Greed';
    return 'Extreme Greed';
  }
}
