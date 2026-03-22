import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/btc_metrics.dart';
import '../models/exchange_tick.dart';
import '../services/bitview_service.dart';

final bitviewServiceProvider = Provider<BitviewService>((ref) {
  final service = BitviewService();
  ref.onDispose(service.dispose);
  return service;
});

// --- Mining ---

final miningMetricsProvider =
    StateNotifierProvider<_PollingNotifier<MiningMetrics>, AsyncValue<MiningMetrics>>(
        (ref) {
  final service = ref.watch(bitviewServiceProvider);
  return _PollingNotifier(
    fetch: () => service.getMiningMetrics(),
    interval: const Duration(minutes: 5),
  );
});

// --- Mempool ---

final mempoolMetricsProvider =
    StateNotifierProvider<_PollingNotifier<MempoolMetrics>, AsyncValue<MempoolMetrics>>(
        (ref) {
  final service = ref.watch(bitviewServiceProvider);
  return _PollingNotifier(
    fetch: () => service.getMempoolMetrics(),
    interval: const Duration(seconds: 30),
  );
});

// --- Realized price history ---

final realizedPriceHistoryProvider =
    FutureProvider<List<PriceTick>>((ref) async {
  final service = ref.watch(bitviewServiceProvider);
  return service.getRealizedPriceHistory(days: 730);
});

// --- Market ---

final marketMetricsProvider =
    StateNotifierProvider<_PollingNotifier<MarketMetrics>, AsyncValue<MarketMetrics>>(
        (ref) {
  final service = ref.watch(bitviewServiceProvider);
  return _PollingNotifier(
    fetch: () => service.getMarketMetrics(0),
    interval: const Duration(minutes: 5),
  );
});

// --- Sentiment ---

final sentimentMetricsProvider =
    StateNotifierProvider<_PollingNotifier<SentimentMetrics>, AsyncValue<SentimentMetrics>>(
        (ref) {
  final service = ref.watch(bitviewServiceProvider);
  return _PollingNotifier(
    fetch: () => service.getSentimentMetrics(),
    interval: const Duration(minutes: 15),
  );
});

// Generic polling notifier

class _PollingNotifier<T> extends StateNotifier<AsyncValue<T>> {
  final Future<T?> Function() fetch;
  final Duration interval;
  Timer? _timer;

  _PollingNotifier({required this.fetch, required this.interval})
      : super(const AsyncValue.loading()) {
    _load();
    _timer = Timer.periodic(interval, (_) => _load());
  }

  Future<void> _load() async {
    try {
      final result = await fetch();
      if (result != null && mounted) {
        state = AsyncValue.data(result);
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
