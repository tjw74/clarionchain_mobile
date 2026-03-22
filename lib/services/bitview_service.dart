import 'package:dio/dio.dart';
import '../models/btc_metrics.dart';
import '../models/exchange_tick.dart';

class BitviewService {
  static const _base = 'https://bitview.space';

  final _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/json'},
  ));

  Future<MiningMetrics?> getMiningMetrics() async {
    try {
      final results = await Future.wait([
        _dio.get('/api/v1/difficulty-adjustment'),
        _dio.get('/api/v1/mining/hashrate/1w'),
      ]);

      final adj = results[0].data as Map<String, dynamic>;
      final hashrate = results[1].data;

      final blocksRemaining = (adj['remainingBlocks'] as num?)?.toInt() ?? 0;
      final adjustmentPercent =
          (adj['difficultyChange'] as num?)?.toDouble() ?? 0.0;
      final currentDifficulty =
          (adj['currentDifficulty'] as num?)?.toDouble() ?? 0.0;

      // Extract latest hashrate value
      double hashrateEhs = 0;
      if (hashrate is List && hashrate.isNotEmpty) {
        final latest = hashrate.last;
        if (latest is Map) {
          final val = (latest['avgHashrate'] ?? latest['value'] ?? latest['hashrate'] ?? 0);
          hashrateEhs = (val as num).toDouble() / 1e18; // convert to EH/s
        }
      } else if (hashrate is Map) {
        final val = hashrate['currentHashrate'] ?? hashrate['avgHashrate'] ?? 0;
        hashrateEhs = (val as num).toDouble() / 1e18;
      }

      DateTime? estimatedDate;
      final remaining = adj['remainingTime'];
      if (remaining != null) {
        estimatedDate = DateTime.now().add(
          Duration(seconds: (remaining as num).toInt()),
        );
      }

      return MiningMetrics(
        hashrateEhs: hashrateEhs,
        difficultyAdjustmentPercent: adjustmentPercent,
        blocksUntilAdjustment: blocksRemaining,
        estimatedAdjustmentDate: estimatedDate,
        currentDifficulty: currentDifficulty,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MempoolMetrics?> getMempoolMetrics() async {
    try {
      final results = await Future.wait([
        _dio.get('/api/mempool/info'),
        _dio.get('/api/v1/fees/recommended'),
      ]);

      final mempool = results[0].data as Map<String, dynamic>;
      final fees = results[1].data as Map<String, dynamic>;

      return MempoolMetrics(
        pendingTxCount: (mempool['count'] as num?)?.toInt() ?? 0,
        totalFeeBtc: ((mempool['total_fee'] as num?) ?? 0).toDouble() / 1e8,
        mempoolSizeBytes: (mempool['vsize'] as num?)?.toInt() ?? 0,
        feeSlowSatsPerVb: (fees['hourFee'] as num?)?.toInt() ?? 0,
        feeMediumSatsPerVb: (fees['halfHourFee'] as num?)?.toInt() ?? 0,
        feeFastSatsPerVb: (fees['fastestFee'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<MarketMetrics?> getMarketMetrics(double currentPrice) async {
    try {
      final results = await Future.wait([
        _dio.get('/api/metric/market-cap', queryParameters: {'limit': 1}),
        _dio.get('/api/metric/realized-cap', queryParameters: {'limit': 1}),
        _dio.get('/api/metric/supply', queryParameters: {'limit': 1}),
      ]);

      double extract(Response r) {
        final d = r.data;
        if (d is List && d.isNotEmpty) {
          final item = d.last;
          if (item is Map) return (item['value'] ?? item['v'] ?? 0 as num).toDouble();
        }
        if (d is Map) return ((d['value'] ?? d['v'] ?? 0) as num).toDouble();
        return 0;
      }

      final marketCap = extract(results[0]);
      final realizedCap = extract(results[1]);
      final supply = extract(results[2]);

      final mvrv = realizedCap > 0 ? marketCap / realizedCap : 0.0;

      return MarketMetrics(
        marketCapUsd: marketCap,
        realizedCapUsd: realizedCap,
        mvrv: mvrv,
        circulatingSupply: supply > 0 ? supply : 19800000,
        volume24hUsd: 0,
      );
    } catch (_) {
      return null;
    }
  }


  Future<SentimentMetrics?> getSentimentMetrics() async {
    try {
      // Try common metric names for fear/greed
      for (final name in ['fear-and-greed', 'fear-greed', 'greed-index']) {
        try {
          final r = await _dio.get('/api/metric/$name', queryParameters: {'limit': 1});
          final d = r.data;
          double score = 0;
          if (d is List && d.isNotEmpty) {
            final item = d.last;
            if (item is Map) score = ((item['value'] ?? item['v'] ?? 0) as num).toDouble();
          } else if (d is Map) {
            score = ((d['value'] ?? d['v'] ?? 0) as num).toDouble();
          }
          if (score > 0) {
            return SentimentMetrics(
              fearGreedIndex: score,
              fearGreedLabel: SentimentMetrics.labelFromScore(score),
            );
          }
        } catch (_) {
          continue;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch 2 years of daily closing prices from bitview.space.
  /// Endpoint: GET /api/metric/price_close/dateindex
  /// Response: {"total": N, "data": [float, ...]} where index 0 = Jan 3, 2009
  Future<List<PriceTick>> getDailyPriceHistory({int days = 730}) async {
    try {
      final r = await _dio.get('/api/metric/price_close/dateindex');
      final body = r.data as Map<String, dynamic>;
      final data = body['data'];
      if (data is! List || data.isEmpty) return [];

      // Each index = one day since Bitcoin genesis (Jan 3, 2009)
      final genesis = DateTime.utc(2009, 1, 3);
      final totalDays = data.length;
      final startIdx = (totalDays - days).clamp(0, totalDays);

      final result = <PriceTick>[];
      for (int i = startIdx; i < totalDays; i++) {
        final price = (data[i] as num?)?.toDouble() ?? 0.0;
        if (price > 0) {
          result.add(PriceTick(
            price: price,
            timestamp: genesis.add(Duration(days: i)),
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _dio.close();
  }
}
