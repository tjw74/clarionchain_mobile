import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exchange_tick.dart';
import '../services/exchange_service.dart';

// Max price history points (1 per ~2s = ~12 hours worth)
const _maxHistory = 21600;

final exchangeServiceProvider = Provider<ExchangeService>((ref) {
  final service = ExchangeService();
  ref.onDispose(service.dispose);
  return service;
});

final priceStateProvider =
    StateNotifierProvider<PriceStateNotifier, PriceState>((ref) {
  final service = ref.watch(exchangeServiceProvider);
  return PriceStateNotifier(service);
});

class PriceStateNotifier extends StateNotifier<PriceState> {
  final ExchangeService _service;
  StreamSubscription<ExchangeTick>? _sub;

  PriceStateNotifier(this._service) : super(const PriceState.empty()) {
    _sub = _service.ticks.listen(_onTick);
  }

  void _onTick(ExchangeTick tick) {
    final updated = Map<String, ExchangeTick>.from(state.ticks);
    updated[tick.exchange] = tick;
    state = PriceState(ticks: updated);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final priceHistoryProvider =
    StateNotifierProvider<PriceHistoryNotifier, List<PriceTick>>((ref) {
  return PriceHistoryNotifier(ref);
});

class PriceHistoryNotifier extends StateNotifier<List<PriceTick>> {
  final Ref _ref;
  StreamSubscription<ExchangeTick>? _sub;
  int _tickCount = 0;

  PriceHistoryNotifier(this._ref) : super([]) {
    final service = _ref.read(exchangeServiceProvider);
    _sub = service.ticks.listen(_onTick);
  }

  void _onTick(ExchangeTick tick) {
    _tickCount++;
    // Sample ~1 point every 5 ticks across all exchanges to avoid oversampling
    if (_tickCount % 5 != 0) return;

    final priceState = _ref.read(priceStateProvider);
    if (!priceState.hasData) return;

    final newTick = PriceTick(
      price: priceState.vwap,
      timestamp: DateTime.now(),
    );

    final history = [...state, newTick];
    if (history.length > _maxHistory) {
      state = history.sublist(history.length - _maxHistory);
    } else {
      state = history;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// Visible chart window state: [startIndex, endIndex]
final chartWindowProvider =
    StateNotifierProvider<ChartWindowNotifier, ChartWindow>((ref) {
  return ChartWindowNotifier();
});

class ChartWindow {
  final int visibleCount; // how many points to show
  final double scrollFraction; // 0.0 = oldest visible, 1.0 = newest

  const ChartWindow({
    this.visibleCount = 300,
    this.scrollFraction = 1.0,
  });

  ChartWindow copyWith({int? visibleCount, double? scrollFraction}) {
    return ChartWindow(
      visibleCount: visibleCount ?? this.visibleCount,
      scrollFraction: scrollFraction ?? this.scrollFraction,
    );
  }
}

class ChartWindowNotifier extends StateNotifier<ChartWindow> {
  ChartWindowNotifier() : super(const ChartWindow());

  void zoom(double scaleFactor) {
    final newCount = (state.visibleCount / scaleFactor)
        .round()
        .clamp(30, _maxHistory);
    state = state.copyWith(visibleCount: newCount);
  }

  void scroll(double delta) {
    final newFraction = (state.scrollFraction + delta).clamp(0.0, 1.0);
    state = state.copyWith(scrollFraction: newFraction);
  }

  void resetToLatest() {
    state = state.copyWith(scrollFraction: 1.0);
  }
}
