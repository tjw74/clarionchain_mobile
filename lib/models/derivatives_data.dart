class FundingSnapshot {
  final double rate;          // decimal e.g. 0.0001 = 0.01%
  final DateTime nextFunding;
  final double markPrice;
  final double annualizedPct; // rate * 3 * 365 * 100

  const FundingSnapshot({
    required this.rate,
    required this.nextFunding,
    required this.markPrice,
    required this.annualizedPct,
  });
}

class OiSnapshot {
  final double oiBtc;
  final double oiUsd;
  final double longPct;   // 0–1
  final double shortPct;  // 0–1

  const OiSnapshot({
    required this.oiBtc,
    required this.oiUsd,
    required this.longPct,
    required this.shortPct,
  });
}

class OiHistoryPoint {
  final DateTime timestamp;
  final double oiUsd;
  const OiHistoryPoint({required this.timestamp, required this.oiUsd});
}

class FundingHistoryPoint {
  final DateTime timestamp;
  final double rate;
  const FundingHistoryPoint({required this.timestamp, required this.rate});
}
