import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/derivatives_data.dart';
import '../services/derivatives_service.dart';
import 'price_provider.dart';

final _derivativesServiceProvider = Provider<DerivativesService>((ref) {
  final s = DerivativesService();
  ref.onDispose(s.dispose);
  return s;
});

// Current funding rate — polls every 5 minutes
final fundingProvider =
    StateNotifierProvider<_FundingNotifier, AsyncValue<FundingSnapshot>>(
        (ref) => _FundingNotifier(ref.watch(_derivativesServiceProvider)));

class _FundingNotifier
    extends StateNotifier<AsyncValue<FundingSnapshot>> {
  final DerivativesService _svc;
  Timer? _timer;
  _FundingNotifier(this._svc) : super(const AsyncValue.loading()) {
    _load();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }
  Future<void> _load() async {
    final data = await _svc.getFunding();
    if (!mounted) return;
    if (data != null) {
      state = AsyncValue.data(data);
    } else if (!state.hasValue) {
      state = AsyncValue.error(
        StateError('Funding unavailable'),
        StackTrace.current,
      );
    }
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

/// Mark price for OI USD: Binance mark, else spot VWAP from exchanges.
final _derivativesMarkUsdProvider = Provider<double>((ref) {
  final m = ref.watch(fundingProvider).valueOrNull?.markPrice ?? 0;
  final spot = ref.watch(priceStateProvider).vwap;
  return m > 0 ? m : spot;
});

// Current OI — polls every 5 minutes (needs mark price)
final oiProvider =
    StateNotifierProvider<_OiNotifier, AsyncValue<OiSnapshot>>(
        (ref) => _OiNotifier(ref.watch(_derivativesServiceProvider),
            ref.watch(_derivativesMarkUsdProvider)));

class _OiNotifier extends StateNotifier<AsyncValue<OiSnapshot>> {
  final DerivativesService _svc;
  final double _markPrice;
  Timer? _timer;
  _OiNotifier(this._svc, this._markPrice)
      : super(const AsyncValue.loading()) {
    _load();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }
  Future<void> _load() async {
    final data = await _svc.getOi(_markPrice);
    if (!mounted) return;
    if (data != null) {
      state = AsyncValue.data(data);
    } else if (!state.hasValue) {
      state = AsyncValue.error(
        StateError('Open interest unavailable'),
        StackTrace.current,
      );
    }
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// Historical OI (90 days)
final oiHistoryProvider = FutureProvider<List<OiHistoryPoint>>((ref) =>
    ref.watch(_derivativesServiceProvider).getOiHistory());

// Historical funding rate (last 90 events = 30 days)
final fundingHistoryProvider = FutureProvider<List<FundingHistoryPoint>>((ref) =>
    ref.watch(_derivativesServiceProvider).getFundingHistory(limit: 90));
