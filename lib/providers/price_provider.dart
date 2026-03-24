import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exchange_tick.dart';
import '../services/exchange_service.dart';
import '../services/bitview_service.dart';

const _maxHistory = 25000;
const _sampleInterval = Duration(seconds: 5);

/// Full Bitcoin price history since genesis — for MA, z-score, quantile computation.
/// Loaded once, not updated with live ticks.
final priceHistoryDailyProvider = FutureProvider<List<PriceTick>>((ref) {
  final svc = BitviewService();
  return svc.getFullPriceHistory();
});

final exchangeServiceProvider = Provider<ExchangeService>((ref) {
  final service = ExchangeService();
  ref.onDispose(service.dispose);
  return service;
});

final _localBitviewProvider = Provider<BitviewService>((ref) {
  final service = BitviewService();
  ref.onDispose(service.dispose);
  return service;
});

final priceStateProvider =
    StateNotifierProvider<PriceStateNotifier, PriceState>((ref) {
  return PriceStateNotifier(ref.watch(exchangeServiceProvider));
});

/// Live VWAP vs prior daily close (bitview), as %. Used for top bar; avoids
/// using `priceHistoryProvider` which mixes years of dailies with sub-minute ticks.
final btcDailyChangeVsPriorClosePctProvider = Provider<double?>((ref) {
  final dailyAsync = ref.watch(priceHistoryDailyProvider);
  final live = ref.watch(priceStateProvider).vwap;
  return dailyAsync.maybeWhen(
    data: (ticks) {
      if (ticks.length < 2 || live <= 0) return null;
      final prevClose = ticks[ticks.length - 2].price;
      if (prevClose <= 0) return null;
      return (live - prevClose) / prevClose * 100;
    },
    orElse: () => null,
  );
});

class PriceStateNotifier extends StateNotifier<PriceState> {
  final ExchangeService _service;
  StreamSubscription<ExchangeTick>? _sub;

  PriceStateNotifier(this._service) : super(const PriceState.empty()) {
    _sub = _service.ticks.listen((tick) {
      final updated = Map<String, ExchangeTick>.from(state.ticks);
      updated[tick.exchange] = tick;
      state = PriceState(ticks: updated);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final historyLoadingProvider = StateProvider<bool>((ref) => true);

final priceHistoryProvider =
    StateNotifierProvider<PriceHistoryNotifier, List<PriceTick>>((ref) {
  return PriceHistoryNotifier(ref);
});

class PriceHistoryNotifier extends StateNotifier<List<PriceTick>> {
  final Ref _ref;
  StreamSubscription<ExchangeTick>? _sub;
  DateTime? _lastSample;
  DateTime? _historyEnd;

  PriceHistoryNotifier(this._ref) : super([]) {
    _loadHistory();
    _sub = _ref.read(exchangeServiceProvider).ticks.listen(_onTick);
  }

  Future<void> _loadHistory() async {
    _ref.read(historyLoadingProvider.notifier).state = true;
    try {
      final bitview = _ref.read(_localBitviewProvider);
      final history = await bitview.getDailyPriceHistory(days: 730);
      if (mounted && history.isNotEmpty) {
        state = history;
        _historyEnd = history.last.timestamp;
      }
    } catch (_) {}
    if (mounted) {
      _ref.read(historyLoadingProvider.notifier).state = false;
    }
  }

  void _onTick(ExchangeTick tick) {
    final now = DateTime.now();
    if (_lastSample != null && now.difference(_lastSample!) < _sampleInterval) return;
    final priceState = _ref.read(priceStateProvider);
    if (!priceState.hasData) return;
    _lastSample = now;

    final newTick = PriceTick(price: priceState.vwap, timestamp: now);
    // Don't append if within 12h of last historical daily point (avoid duplicates)
    if (_historyEnd != null &&
        newTick.timestamp.isBefore(_historyEnd!.add(const Duration(hours: 12)))) {
      return;
    }

    final history = [...state, newTick];
    state = history.length > _maxHistory
        ? history.sublist(history.length - _maxHistory)
        : history;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

