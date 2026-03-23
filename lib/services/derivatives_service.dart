import 'package:dio/dio.dart';
import '../models/derivatives_data.dart';

class DerivativesService {
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://fapi.binance.com',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    headers: {'Accept': 'application/json'},
  ));

  Future<FundingSnapshot?> getFunding() async {
    try {
      final r = await _dio.get(
          '/fapi/v1/premiumIndex', queryParameters: {'symbol': 'BTCUSDT'});
      final d = r.data as Map<String, dynamic>;
      final rate = double.tryParse(d['lastFundingRate']?.toString() ?? '') ?? 0;
      final nextMs = (d['nextFundingTime'] as num?)?.toInt() ?? 0;
      final mark = double.tryParse(d['markPrice']?.toString() ?? '') ?? 0;
      return FundingSnapshot(
        rate: rate,
        nextFunding: DateTime.fromMillisecondsSinceEpoch(nextMs),
        markPrice: mark,
        annualizedPct: rate * 3 * 365 * 100,
      );
    } catch (_) {
      return null;
    }
  }

  Future<OiSnapshot?> getOi(double markPrice) async {
    try {
      final results = await Future.wait([
        _dio.get('/fapi/v1/openInterest', queryParameters: {'symbol': 'BTCUSDT'}),
        _dio.get('/futures/data/globalLongShortAccountRatio',
            queryParameters: {
              'symbol': 'BTCUSDT',
              'period': '1h',
              'limit': 1,
            }),
      ]);

      final oiData = results[0].data as Map<String, dynamic>;
      final oiBtc = double.tryParse(oiData['openInterest']?.toString() ?? '') ?? 0;

      double longPct = 0.5, shortPct = 0.5;
      final lsData = results[1].data;
      if (lsData is List && lsData.isNotEmpty) {
        final item = lsData.last as Map<String, dynamic>;
        longPct = double.tryParse(item['longAccount']?.toString() ?? '') ?? 0.5;
        shortPct = double.tryParse(item['shortAccount']?.toString() ?? '') ?? 0.5;
      }

      return OiSnapshot(
        oiBtc: oiBtc,
        oiUsd: oiBtc * markPrice,
        longPct: longPct,
        shortPct: shortPct,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<OiHistoryPoint>> getOiHistory({int days = 90}) async {
    try {
      final r = await _dio.get('/futures/data/openInterestHist',
          queryParameters: {
            'symbol': 'BTCUSDT',
            'period': '1d',
            'limit': days,
          });
      final list = r.data as List;
      return list.map((item) {
        final ts = int.tryParse(item['timestamp']?.toString() ?? '') ?? 0;
        final usd = double.tryParse(item['sumOpenInterestValue']?.toString() ?? '') ?? 0;
        return OiHistoryPoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
          oiUsd: usd,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<FundingHistoryPoint>> getFundingHistory({int limit = 90}) async {
    try {
      final r = await _dio.get('/fapi/v1/fundingRate',
          queryParameters: {'symbol': 'BTCUSDT', 'limit': limit});
      final list = r.data as List;
      return list.map((item) {
        final ts = (item['fundingTime'] as num?)?.toInt() ?? 0;
        final rate = double.tryParse(item['fundingRate']?.toString() ?? '') ?? 0;
        return FundingHistoryPoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
          rate: rate,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() => _dio.close();
}
