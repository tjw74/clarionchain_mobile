import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock_data.dart';
import '../services/stock_service.dart';

final _stockServiceProvider = Provider<StockService>((ref) {
  final s = StockService();
  ref.onDispose(s.dispose);
  return s;
});

final stockQuoteProvider =
    FutureProvider.family<StockQuote?, String>((ref, ticker) =>
        ref.watch(_stockServiceProvider).getQuote(ticker));
