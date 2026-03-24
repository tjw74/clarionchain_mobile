import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exchange_tick.dart';
import '../services/exchange_service.dart';
import '../services/bitview_service.dart';

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

/// Rolling **~2 years** of daily closes from Bitview (`getFullPriceHistory` tail),
/// with **live VWAP on the last bar**. Never uses live tick spam (sub-minute) as chart data.
const chartDailyWindow = 730;

/// True if this series spans enough calendar time to be daily (or multi-day) history.
bool chartHistoryLooksLikeDailySeries(List<PriceTick> h) {
  if (h.length < 2) return false;
  final spanDays =
      h.last.timestamp.difference(h.first.timestamp).inDays.abs();
  return spanDays >= 14;
}

List<PriceTick> _sliceChartWindow(List<PriceTick> daily, double liveVwap) {
  final n = daily.length;
  final start = n > chartDailyWindow ? n - chartDailyWindow : 0;
  final slice = List<PriceTick>.from(daily.sublist(start));
  if (liveVwap > 0 && slice.isNotEmpty) {
    final last = slice.last;
    slice[slice.length - 1] =
        PriceTick(price: liveVwap, timestamp: last.timestamp);
  }
  return slice;
}

final chartDailyPriceHistoryProvider = Provider<List<PriceTick>>((ref) {
  final dailyAsync = ref.watch(priceHistoryDailyProvider);
  final fallback = ref.watch(priceHistoryProvider);
  final live = ref.watch(priceStateProvider).vwap;

  final daily = dailyAsync.valueOrNull;
  if (daily != null && daily.isNotEmpty) {
    return _sliceChartWindow(daily, live);
  }

  // Same Bitview daily endpoint as Notifier (730), without tick pollution — only if multi-week span.
  if (chartHistoryLooksLikeDailySeries(fallback)) {
    return _sliceChartWindow(fallback, live);
  }

  return [];
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

  PriceHistoryNotifier(this._ref) : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    _ref.read(historyLoadingProvider.notifier).state = true;
    try {
      final bitview = _ref.read(_localBitviewProvider);
      final history = await bitview.getDailyPriceHistory(days: 730);
      if (mounted && history.isNotEmpty) {
        state = history;
      }
    } catch (_) {}
    if (mounted) {
      _ref.read(historyLoadingProvider.notifier).state = false;
    }
  }

}

