import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exchange_tick.dart';
import '../services/exchange_service.dart';
import '../services/bitview_service.dart';

// Max total points in history buffer
const _maxHistory = 25000;

// Sample interval for real-time ticks
const _sampleInterval = Duration(seconds: 5);

final exchangeServiceProvider = Provider<ExchangeService>((ref) {
  final service = ExchangeService();
  ref.onDispose(service.dispose);
  return service;
});

// Re-export bitviewServiceProvider here to avoid circular imports
final _bitviewProvider = Provider<BitviewService>((ref) {
  final service = BitviewService();
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

// Whether historical data has finished loading
final historyLoadingProvider = StateProvider<bool>((ref) => true);

final priceHistoryProvider =
    StateNotifierProvider<PriceHistoryNotifier, List<PriceTick>>((ref) {
  return PriceHistoryNotifier(ref);
});

class PriceHistoryNotifier extends StateNotifier<List<PriceTick>> {
  final Ref _ref;
  StreamSubscription<ExchangeTick>? _sub;
  DateTime? _lastSample;
  DateTime? _historyEnd; // last timestamp of loaded historical data

  PriceHistoryNotifier(this._ref) : super([]) {
    _loadHistory();
    final service = _ref.read(exchangeServiceProvider);
    _sub = service.ticks.listen(_onTick);
  }

  Future<void> _loadHistory() async {
    _ref.read(historyLoadingProvider.notifier).state = true;
    try {
      final bitview = _ref.read(_bitviewProvider);
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
    if (_lastSample != null && now.difference(_lastSample!) < _sampleInterval) {
      return;
    }

    final priceState = _ref.read(priceStateProvider);
    if (!priceState.hasData) return;
    _lastSample = now;

    final newTick = PriceTick(price: priceState.vwap, timestamp: now);

    // Skip if this tick is before or at the last historical point
    if (_historyEnd != null &&
        newTick.timestamp.isBefore(
            _historyEnd!.add(const Duration(minutes: 30)))) {
      // Still within the historical window — wait for a clean gap
      if (newTick.timestamp
          .isBefore(_historyEnd!.add(const Duration(hours: 1)))) {
        return;
      }
    }

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

// Chart window: what slice of history to display
final chartWindowProvider =
    StateNotifierProvider<ChartWindowNotifier, ChartWindow>((ref) {
  return ChartWindowNotifier();
});

class ChartWindow {
  final int? visibleCount; // null = show all
  final double scrollFraction; // 1.0 = newest end

  const ChartWindow({
    this.visibleCount, // null = show all history
    this.scrollFraction = 1.0,
  });

  ChartWindow copyWith({int? visibleCount, bool clearVisible = false, double? scrollFraction}) {
    return ChartWindow(
      visibleCount: clearVisible ? null : (visibleCount ?? this.visibleCount),
      scrollFraction: scrollFraction ?? this.scrollFraction,
    );
  }
}

class ChartWindowNotifier extends StateNotifier<ChartWindow> {
  ChartWindowNotifier() : super(const ChartWindow());

  void zoom(double scaleFactor, int totalPoints) {
    final current = state.visibleCount ?? totalPoints;
    final newCount = (current / scaleFactor)
        .round()
        .clamp(10, totalPoints);
    state = state.copyWith(visibleCount: newCount);
  }

  void scroll(double delta) {
    final newFraction = (state.scrollFraction + delta).clamp(0.0, 1.0);
    state = state.copyWith(scrollFraction: newFraction);
  }

  void resetToAll() {
    state = const ChartWindow(); // show all, newest end
  }
}
