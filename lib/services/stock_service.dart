import 'package:dio/dio.dart';
import '../models/stock_data.dart';

class StockService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0',
    },
  ));

  // Cache: ticker -> (fetchedAt, data)
  final Map<String, (DateTime, StockQuote)> _cache = {};
  static const _cacheDuration = Duration(minutes: 15);

  Future<StockQuote?> getQuote(String ticker) async {
    final cached = _cache[ticker];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < _cacheDuration) {
      return cached.$2;
    }

    try {
      final r = await _dio.get(
        'https://query1.finance.yahoo.com/v8/finance/chart/$ticker',
        queryParameters: {'interval': '1d', 'range': '2y'},
      );

      final chart = (r.data as Map)['chart'] as Map;
      final results = chart['result'] as List?;
      if (results == null || results.isEmpty) return null;
      final result = results[0] as Map<String, dynamic>;

      final meta = result['meta'] as Map<String, dynamic>;
      final timestamps = result['timestamp'] as List?;
      final quoteList = (result['indicators']?['quote'] as List?);
      final closes =
          quoteList != null && quoteList.isNotEmpty ? quoteList[0]['close'] as List? : null;
      final volumes =
          quoteList != null && quoteList.isNotEmpty ? quoteList[0]['volume'] as List? : null;

      final history = <StockBar>[];
      if (timestamps != null && closes != null) {
        for (int i = 0; i < timestamps.length; i++) {
          final ts = (timestamps[i] as num?)?.toInt();
          final close = (closes[i] as num?)?.toDouble();
          if (ts == null || close == null || close <= 0) continue;
          final vol = (volumes?[i] as num?)?.toDouble() ?? 0;
          history.add(StockBar(
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            close: close,
            volume: vol,
          ));
        }
      }

      final quote = StockQuote(
        ticker: ticker,
        name: (meta['shortName'] ?? meta['longName'] ?? ticker).toString(),
        price: (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0,
        previousClose: (meta['chartPreviousClose'] as num?)?.toDouble() ?? 0,
        fiftyTwoWeekHigh: (meta['fiftyTwoWeekHigh'] as num?)?.toDouble() ?? 0,
        fiftyTwoWeekLow: (meta['fiftyTwoWeekLow'] as num?)?.toDouble() ?? 0,
        history: history,
      );

      _cache[ticker] = (DateTime.now(), quote);
      return quote;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _dio.close();
}
