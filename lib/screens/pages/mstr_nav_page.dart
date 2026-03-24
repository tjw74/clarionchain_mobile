import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/chart_axis_labels.dart';
import '../../models/exchange_tick.dart';
import '../../models/stock_data.dart';
import '../../widgets/category_page_layout.dart';

final _priceFmt2Nav = NumberFormat('#,##0.00', 'en_US');
final _intFmtNav = NumberFormat('#,##0', 'en_US');

String _compactNav(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
  return '\$${v.toStringAsFixed(2)}';
}

class MstrNavPage extends ConsumerStatefulWidget {
  const MstrNavPage({super.key});

  @override
  ConsumerState<MstrNavPage> createState() => _MstrNavPageState();
}

class _MstrNavPageState extends ConsumerState<MstrNavPage> {
  static const int _btcHoldings = 528185;
  static const int _sharesOutstandingFallback = 246000000;

  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final priceState = ref.watch(priceStateProvider);
    final history = ref.watch(priceHistoryProvider);
    final mstrAsync = ref.watch(stockQuoteProvider('MSTR'));

    final btcPrice = priceState.vwap;
    final mstrQuote = mstrAsync.valueOrNull;
    final mstrPrice = mstrQuote?.price ?? 0.0;

    // Shares outstanding: attempt to derive from market cap / price using
    // Yahoo Finance data. Since StockQuote doesn't expose sharesOutstanding
    // directly, fall back to hardcoded value.
    final sharesOutstanding = _sharesOutstandingFallback;

    final navPerShare = btcPrice > 0
        ? (_btcHoldings * btcPrice) / sharesOutstanding
        : 0.0;

    final premium = navPerShare > 0 && mstrPrice > 0
        ? (mstrPrice - navPerShare) / navPerShare
        : 0.0;

    final btcPerShare = _btcHoldings / sharesOutstanding;
    final marketCap = mstrPrice > 0 ? mstrPrice * sharesOutstanding : 0.0;

    // Change for header
    final changePct = mstrQuote?.changePct ?? 0.0;
    final premiumPct = premium * 100;
    final premiumStr =
        premium != 0 ? '${premium >= 0 ? '+' : ''}${premiumPct.toStringAsFixed(1)}% premium' : '—';

    final premiumColor = premium > 1.0
        ? AppColors.negative
        : premium >= 0 && premium < 0.2
            ? AppColors.positive
            : AppColors.textPrimary;

    // NAV history: btcHoldings * btcPrice_per_day / sharesOutstanding
    final navHistory = history
        .map((t) => t.price * _btcHoldings / sharesOutstanding)
        .toList();

    // MSTR price history aligned to same indices as btcHistory
    final mstrBarHistory = mstrQuote?.history ?? [];

    final subtitle = navPerShare > 0
        ? '\$${_priceFmt2Nav.format(navPerShare)} / sh · $premiumStr'
        : null;

    return CategoryPageLayout(
      header: CategoryPageHeader(
        category: 'MSTR',
        title: 'NAV',
        accentColor: const Color(0xFFFF6B35),
        subtitle: subtitle,
      ),
      chart: _buildChart(
          context, history, navHistory, mstrBarHistory, sharesOutstanding),
      stats: _buildStats(
        navPerShare,
        mstrPrice,
        premium,
        premiumColor,
        btcPerShare,
        marketCap,
        changePct,
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    List<PriceTick> btcHistory,
    List<double> navHistory,
    List<StockBar> mstrHistory,
    int sharesOutstanding,
  ) {
    if (btcHistory.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.btcOrange, strokeWidth: 2),
      );
    }

    final n = btcHistory.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final sliceBtc = startIdx < endIdx
        ? btcHistory.sublist(startIdx, endIdx + 1)
        : [btcHistory.last];
    final sliceNav = startIdx < endIdx && endIdx < navHistory.length
        ? navHistory.sublist(startIdx, endIdx + 1)
        : navHistory.isNotEmpty
            ? [navHistory.last]
            : <double>[];

    // NAV spots
    final navSpots = sliceNav.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    double minP = sliceNav.isNotEmpty
        ? sliceNav.reduce((a, b) => a < b ? a : b)
        : 0.0;
    double maxP = sliceNav.isNotEmpty
        ? sliceNav.reduce((a, b) => a > b ? a : b)
        : 1.0;

    // MSTR price spots — align by date
    final Map<int, double> mstrByDay = {};
    for (final bar in mstrHistory) {
      mstrByDay[bar.timestamp.millisecondsSinceEpoch ~/ 86400000] = bar.close;
    }

    final mstrSpots = <FlSpot>[];
    for (int i = 0; i < sliceBtc.length; i++) {
      final dayKey =
          sliceBtc[i].timestamp.millisecondsSinceEpoch ~/ 86400000;
      final mp = mstrByDay[dayKey];
      if (mp != null) {
        if (mp < minP) minP = mp;
        if (mp > maxP) maxP = mp;
        mstrSpots.add(FlSpot(i.toDouble(), mp));
      }
    }

    final yPad = ((maxP - minP) * 0.08).clamp(0.5, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final vc = sliceBtc.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays = sliceBtc.last.timestamp
            .difference(sliceBtc.first.timestamp)
            .inMinutes /
        1440.0;

    return GestureDetector(
      onScaleStart: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        _gsWidth = rb?.size.width ?? 300;
        _gsFocalX = d.localFocalPoint.dx;
        _gsViewStart = _viewStart;
        _gsViewEnd = _viewEnd;
      },
      onScaleUpdate: (d) {
        if (_gsWidth == 0 || d.pointerCount < 2) return;
        final oldSpan = _gsViewEnd - _gsViewStart;
        final newSpan = (oldSpan / d.scale).clamp(0.002, 1.0);
        final focalFrac = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final focalData = _gsViewStart + focalFrac * oldSpan;
        final panPixels = d.localFocalPoint.dx - _gsFocalX;
        final panData = -(panPixels / _gsWidth) * newSpan;
        final s =
            (focalData - focalFrac * newSpan + panData).clamp(0.0, 1.0 - newSpan);
        setState(() {
          _viewStart = s;
          _viewEnd = s + newSpan;
        });
      },
      onDoubleTap: () => setState(() {
        _viewStart = 0;
        _viewEnd = 1.0;
      }),
      child: LineChart(
        LineChartData(
          minY: effMin,
          maxY: effMax,
          clipData: const FlClipData.all(),
          lineTouchData: const LineTouchData(enabled: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: kChartAxisReservedRight,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    formatAxisUsdCompact(value),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9),
                    textAlign: TextAlign.right,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= sliceBtc.length) {
                    return const SizedBox.shrink();
                  }
                  final dt = sliceBtc[idx].timestamp;
                  final label = visibleDays > 365
                      ? DateFormat('MMM yy').format(dt)
                      : visibleDays > 60
                          ? DateFormat('MMM').format(dt)
                          : DateFormat('MMM d').format(dt);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            // NAV line (teal)
            if (navSpots.isNotEmpty)
              LineChartBarData(
                spots: navSpots,
                isCurved: false,
                color: AppColors.positive,
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            // MSTR price (btcOrange dashed)
            if (mstrSpots.isNotEmpty)
              LineChartBarData(
                spots: mstrSpots,
                isCurved: false,
                color: AppColors.btcOrange,
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                dashArray: [6, 4],
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _buildStats(
    double navPerShare,
    double mstrPrice,
    double premium,
    Color premiumColor,
    double btcPerShare,
    double marketCap,
    double mstrChangePct,
  ) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: 'NAV PER SHARE',
                        value: navPerShare > 0
                            ? '\$${_priceFmt2Nav.format(navPerShare)}'
                            : '—',
                        valueColor: AppColors.positive,
                        signal: '${_btcHoldings} BTC / ${_intFmtNav.format(_sharesOutstandingFallback)} shares',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'MSTR PRICE',
                        value: mstrPrice > 0
                            ? '\$${_priceFmt2Nav.format(mstrPrice)}'
                            : '—',
                        valueColor: AppColors.textPrimary,
                        signal: mstrChangePct != 0
                            ? '${mstrChangePct >= 0 ? '+' : ''}${(mstrChangePct * 100).toStringAsFixed(2)}% today'
                            : 'Strategy Inc.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: 'PREMIUM TO NAV',
                        value: premium != 0
                            ? '${premium >= 0 ? '+' : ''}${(premium * 100).toStringAsFixed(1)}%'
                            : '—',
                        valueColor: premiumColor,
                        signal: premium > 1.0
                            ? 'Historically rich'
                            : premium < 0.2 && premium >= 0
                                ? 'Historically cheap'
                                : 'Moderate premium',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'BTC HELD',
                        value: '${_intFmtNav.format(_btcHoldings)} ₿',
                        valueColor: AppColors.btcOrange,
                        signal: 'As of latest filing',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatPanel(
                        label: 'BTC PER SHARE',
                        value: btcPerShare > 0
                            ? '₿${btcPerShare.toStringAsFixed(6)}'
                            : '—',
                        valueColor: AppColors.textPrimary,
                        signal: 'Effective BTC exposure',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'MARKET CAP',
                        value: marketCap > 0 ? _compactNav(marketCap) : '—',
                        valueColor: AppColors.textPrimary,
                        signal: 'price × shares',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

class _StatPanel extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String signal;

  const _StatPanel({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
                color: valueColor, fontSize: 20, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (signal.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(signal,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
