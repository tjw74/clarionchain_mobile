import 'package:dio/dio.dart';
import '../models/btc_metrics.dart';
import '../models/exchange_tick.dart';

/// Client for [bitview.space](https://bitview.space) (BRK — Bitcoin Research Kit).
/// Prefer `/api/series/...`; deprecated `/api/metric/...` kept as fallback. See
/// [API docs](https://bitview.space/api).
class BitviewService {
  static const _base = 'https://bitview.space';

  /// Daily series use index `day1` (genesis-aligned); `/latest` often uses alias `day`.
  static const _indexDay1 = 'day1';
  static const _indexDayLatest = 'day';

  final _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    headers: const {
      'Accept': 'application/json',
      'User-Agent': 'cc_mobile/1.0 (Flutter; +https://bitview.space/api)',
    },
  ));

  /// BRK series envelope: `{ "data": [...], "version", "index", ... }`.
  List<dynamic>? _extractSeriesData(dynamic response) {
    if (response is Map) {
      final d = response['data'];
      if (d is List) return d;
    }
    return null;
  }

  /// Legacy dateindex: raw array or `{ "data": [...] }`.
  List<dynamic>? _extractDateindexList(dynamic response) {
    if (response is List) return response;
    if (response is Map) {
      final d = response['data'];
      if (d is List) return d;
    }
    return null;
  }

  static final _genesisUtc = DateTime.utc(2009, 1, 3);

  /// Scalar `day1` series → [PriceTick]; skips nulls; [requirePositive] for USD levels.
  Future<List<PriceTick>> _fetchSeriesDay1Scalar(
    String series, {
    int days = 365,
    bool requirePositive = true,
  }) async {
    final r = await _dio.get('/api/series/$series/$_indexDay1');
    final data = _extractSeriesData(r.data);
    if (data == null || data.isEmpty) return [];

    final totalDays = data.length;
    final startIdx = (totalDays - days).clamp(0, totalDays);
    final result = <PriceTick>[];
    for (int i = startIdx; i < totalDays; i++) {
      final raw = data[i];
      if (raw == null) continue;
      final val = (raw as num?)?.toDouble();
      if (val == null) continue;
      if (requirePositive) {
        if (val > 0) {
          result.add(PriceTick(price: val, timestamp: _genesisUtc.add(Duration(days: i))));
        }
      } else if (val >= 0) {
        result.add(PriceTick(price: val, timestamp: _genesisUtc.add(Duration(days: i))));
      }
    }
    return result;
  }

  Future<List<PriceTick>> _fetchSeriesDay1ScalarWithFallback(
    String series, {
    required String legacyMetricSlug,
    int days = 365,
    bool requirePositive = true,
  }) async {
    try {
      final v = await _fetchSeriesDay1Scalar(series, days: days, requirePositive: requirePositive);
      if (v.isNotEmpty) return v;
    } catch (_) {}
    return _fetchLegacyDateindex(legacyMetricSlug, days: days, requirePositive: requirePositive);
  }

  Future<double?> _seriesLatestNum(String series) async {
    try {
      final r = await _dio.get('/api/series/$series/$_indexDayLatest/latest');
      final d = r.data;
      if (d is num) return d.toDouble();
    } catch (_) {}
    return null;
  }

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

      double hashrateEhs = 0;
      if (hashrate is List && hashrate.isNotEmpty) {
        final latest = hashrate.last;
        if (latest is Map) {
          final val = (latest['avgHashrate'] ?? latest['value'] ?? latest['hashrate'] ?? 0);
          hashrateEhs = (val as num).toDouble() / 1e18;
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
        _seriesLatestNum('market_cap'),
        _seriesLatestNum('realized_cap'),
        _seriesLatestNum('supply'),
      ]);

      Future<double?> legacyLatest(String metric) async {
        try {
          final r = await _dio.get('/api/metric/$metric', queryParameters: {'limit': 1});
          final d = r.data;
          if (d is List && d.isNotEmpty) {
            final item = d.last;
            if (item is Map) {
              return ((item['value'] ?? item['v'] ?? 0) as num).toDouble();
            }
          }
          if (d is Map) return ((d['value'] ?? d['v'] ?? 0) as num).toDouble();
        } catch (_) {}
        return null;
      }

      var marketCap = results[0] ?? 0;
      var realizedCap = results[1] ?? 0;
      var supply = results[2] ?? 0;

      if (marketCap <= 0) marketCap = await legacyLatest('market-cap') ?? 0;
      if (realizedCap <= 0) realizedCap = await legacyLatest('realized-cap') ?? 0;
      if (supply <= 0) supply = await legacyLatest('supply') ?? 0;

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

  /// On-chain sentiment proxy: maps NUPL (≈ −1…1) to a 0–100 score (not CNN Fear & Greed).
  Future<SentimentMetrics?> getSentimentMetrics() async {
    try {
      final nupl = await _seriesLatestNum('nupl');
      if (nupl != null) {
        final score = (((nupl.clamp(-1.0, 1.0) + 1.0) / 2.0) * 100.0).clamp(0.0, 100.0);
        return SentimentMetrics(
          fearGreedIndex: score,
          fearGreedLabel: SentimentMetrics.labelFromScore(score),
        );
      }

      for (final name in ['greed_index', 'fear-and-greed', 'fear-greed', 'greed-index']) {
        try {
          if (name.contains('-')) {
            final r = await _dio.get('/api/metric/$name', queryParameters: {'limit': 1});
            final d = r.data;
            double raw = 0;
            if (d is List && d.isNotEmpty) {
              final item = d.last;
              if (item is Map) raw = ((item['value'] ?? item['v'] ?? 0) as num).toDouble();
            } else if (d is Map) {
              raw = ((d['value'] ?? d['v'] ?? 0) as num).toDouble();
            }
            if (raw > 0 && raw <= 100) {
              return SentimentMetrics(
                fearGreedIndex: raw,
                fearGreedLabel: SentimentMetrics.labelFromScore(raw),
              );
            }
          } else {
            final raw = await _seriesLatestNum(name);
            if (raw != null && raw > 0 && raw <= 100) {
              return SentimentMetrics(
                fearGreedIndex: raw,
                fearGreedLabel: SentimentMetrics.labelFromScore(raw),
              );
            }
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

  Future<List<PriceTick>> _fetchLegacyDateindex(
    String metric, {
    int days = 365,
    bool requirePositive = true,
  }) async {
    try {
      final r = await _dio.get('/api/metric/$metric/dateindex');
      final data = _extractDateindexList(r.data);
      if (data == null || data.isEmpty) return [];

      final total = data.length;
      final startIdx = (total - days).clamp(0, total);
      final result = <PriceTick>[];
      for (int i = startIdx; i < total; i++) {
        final raw = data[i];
        if (raw == null) continue;
        final val = (raw as num?)?.toDouble();
        if (val == null) continue;
        final ok = requirePositive ? val > 0 : val >= 0;
        if (ok) {
          result.add(PriceTick(price: val, timestamp: _genesisUtc.add(Duration(days: i))));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<PriceTick>> getUnrealizedProfitHistory({int days = 365}) =>
      _fetchSeriesDay1ScalarWithFallback('unrealized_profit', legacyMetricSlug: 'unrealized-profit', days: days);

  Future<List<PriceTick>> getUnrealizedLossHistory({int days = 365}) =>
      _fetchSeriesDay1ScalarWithFallback('unrealized_loss', legacyMetricSlug: 'unrealized-loss', days: days);

  /// Realized P/L: BRK exposes block-height levels as `realized_profit`; use 24h sums on `day1`.
  Future<List<PriceTick>> getRealizedProfitHistory({int days = 365}) =>
      _fetchSeriesDay1ScalarWithFallback('realized_profit_sum_24h', legacyMetricSlug: 'realized-profit', days: days);

  Future<List<PriceTick>> getRealizedLossHistory({int days = 365}) =>
      _fetchSeriesDay1ScalarWithFallback('realized_loss_sum_24h', legacyMetricSlug: 'realized-loss', days: days);

  /// Values in satoshis (matches PnL % math using total sats).
  Future<List<PriceTick>> getSupplyInProfitHistory({int days = 365}) =>
      _fetchSeriesDay1ScalarWithFallback('supply_in_profit_sats', legacyMetricSlug: 'supply-in-profit', days: days);

  Future<List<PriceTick>> getRealizedPriceHistory({int days = 730}) =>
      _fetchSeriesDay1ScalarWithFallback('realized_price', legacyMetricSlug: 'realized-price', days: days);

  /// Daily closes from OHLC series (preferred) — see `/api/series/price_ohlc/day1`.
  Future<List<PriceTick>> _fetchDailyPriceHistoryFromOhlc({required int days}) async {
    final r = await _dio.get('/api/series/price_ohlc/$_indexDay1');
    final data = _extractSeriesData(r.data);
    if (data == null || data.isEmpty) return [];

    final totalDays = data.length;
    final startIdx = (totalDays - days).clamp(0, totalDays);
    final result = <PriceTick>[];
    for (int i = startIdx; i < totalDays; i++) {
      final bar = data[i];
      if (bar is! List || bar.length < 4) continue;
      final close = (bar[3] as num?)?.toDouble() ?? 0.0;
      if (close > 0) {
        result.add(PriceTick(price: close, timestamp: _genesisUtc.add(Duration(days: i))));
      }
    }
    return result;
  }

  /// Last [days] daily closes — series OHLC first, then scalar `price`/`day1`, then legacy dateindex.
  Future<List<PriceTick>> getDailyPriceHistory({int days = 730}) async {
    try {
      final ohlc = await _fetchDailyPriceHistoryFromOhlc(days: days);
      if (ohlc.isNotEmpty) return ohlc;
    } catch (_) {}

    try {
      final scalar = await _fetchSeriesDay1Scalar('price', days: days, requirePositive: true);
      if (scalar.isNotEmpty) return scalar;
    } catch (_) {}

    return _fetchLegacyDateindex('price_close', days: days, requirePositive: true);
  }

  Future<List<PriceTick>> getFullPriceHistory() =>
      getDailyPriceHistory(days: 9999);

  void dispose() {
    _dio.close();
  }
}
