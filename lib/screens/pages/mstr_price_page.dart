import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/price_provider.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/stock_data.dart';

final _priceFmt2 = NumberFormat('#,##0.00', 'en_US');
final _priceFmt0 = NumberFormat('#,##0', 'en_US');

class MstrPricePage extends ConsumerStatefulWidget {
  const MstrPricePage({super.key});

  @override
  ConsumerState<MstrPricePage> createState() => _MstrPricePageState();
}

class _MstrPricePageState extends ConsumerState<MstrPricePage> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final mstrAsync = ref.watch(stockQuoteProvider('MSTR'));
    final btcHistory = ref.watch(priceHistoryProvider);

    final quote = mstrAsync.valueOrNull;
    final price = quote?.price ?? 0.0;
    final changeDollar = quote?.changeDollar ?? 0.0;
    final changePct = quote?.changePct ?? 0.0;
    final isUp = changePct >= 0;
    final changeColor = isUp ? AppColors.positive : AppColors.negative;

    final high52w = quote?.fiftyTwoWeekHigh ?? 0.0;
    final low52w = quote?.fiftyTwoWeekLow ?? 0.0;

    // Compute MSTR vs BTC comparison over same period
    final history = quote?.history ?? [];
    String vsBtc = '—';
    if (history.isNotEmpty && btcHistory.isNotEmpty) {
      final firstBar = history.first.close;
      final lastBar = history.last.close;
      final mstrChangePct =
          firstBar > 0 ? (lastBar - firstBar) / firstBar * 100 : 0.0;

      final btcFirst = btcHistory.first.price;
      final btcLast = btcHistory.last.price;
      final btcChangePct =
          btcFirst > 0 ? (btcLast - btcFirst) / btcFirst * 100 : 0.0;

      final diff = mstrChangePct - btcChangePct;
      final sign = diff >= 0 ? '+' : '';
      vsBtc =
          'MSTR ${mstrChangePct >= 0 ? '+' : ''}${mstrChangePct.toStringAsFixed(1)}% vs BTC ${btcChangePct >= 0 ? '+' : ''}${btcChangePct.toStringAsFixed(1)}%';
      vsBtc = '$sign${diff.toStringAsFixed(1)}% vs BTC';
    }

    final headerValue =
        price > 0 ? '\$${_priceFmt2.format(price)}' : '—';
    final headerChange = changePct != 0
        ? '${isUp ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%'
        : '—';

    return LayoutBuilder(builder: (context, constraints) {
      const headerH = 56.0;
      final totalH = constraints.maxHeight;
      final chartH = (totalH - headerH - 16) * 0.50;
      final statsH = (totalH - headerH - 16) * 0.50;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('MSTR', 'PRICE', headerValue, headerChange, changeColor),
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: mstrAsync.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.btcOrange, strokeWidth: 2))
                  : mstrAsync.hasError
                      ? Center(
                          child: Text('Error loading MSTR',
                              style: const TextStyle(
                                  color: AppColors.textSecondary)))
                      : _buildChart(context, history),
            ),
            SizedBox(
              height: statsH,
              child: _buildStats(
                price,
                changeDollar,
                changePct,
                changeColor,
                high52w,
                low52w,
                vsBtc,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildChart(BuildContext context, List<StockBar> history) {
    if (history.isEmpty) {
      return const Center(
        child: Text('No history available',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final n = history.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final slice = startIdx < endIdx
        ? history.sublist(startIdx, endIdx + 1)
        : [history.last];

    final spots = slice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();

    final closes = slice.map((b) => b.close).toList();
    final minP = closes.reduce((a, b) => a < b ? a : b);
    final maxP = closes.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxP - minP) * 0.08).clamp(0.5, double.infinity);
    final effMin = minP - yPad;
    final effMax = maxP + yPad;

    final isUp = slice.last.close >= slice.first.close;
    final lineColor = isUp ? AppColors.positive : AppColors.negative;
    final vc = slice.length;
    final labelInterval = (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays =
        slice.last.timestamp.difference(slice.first.timestamp).inDays.toDouble();

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
                reservedSize: 68,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '\$${_priceFmt0.format(value.round())}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
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
                  if (idx < 0 || idx >= slice.length) {
                    return const SizedBox.shrink();
                  }
                  final dt = slice[idx].timestamp;
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
            LineChartBarData(
              spots: spots,
              isCurved: vc < 100,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: vc > 200 ? 1.5 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.15),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _buildStats(
    double price,
    double changeDollar,
    double changePct,
    Color changeColor,
    double high52w,
    double low52w,
    String vsBtc,
  ) {
    String _high52wStr() {
      if (high52w > 0) return '\$${_priceFmt2.format(high52w)}';
      return '—';
    }

    String _low52wStr() {
      if (low52w > 0) return '\$${_priceFmt2.format(low52w)}';
      return '—';
    }

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
                        label: 'PRICE',
                        value: price > 0
                            ? '\$${_priceFmt2.format(price)}'
                            : '—',
                        valueColor: AppColors.textPrimary,
                        signal: 'Current market price',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: '1D CHANGE',
                        value: changeDollar != 0
                            ? '${changeDollar >= 0 ? '+' : ''}\$${_priceFmt2.format(changeDollar.abs())}'
                            : '—',
                        valueColor: changeColor,
                        signal: changePct != 0
                            ? '${changePct >= 0 ? '+' : ''}${(changePct * 100).toStringAsFixed(2)}%'
                            : '',
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
                        label: '52W HIGH',
                        value: _high52wStr(),
                        valueColor: AppColors.textPrimary,
                        signal: '52-week high',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: '52W LOW',
                        value: _low52wStr(),
                        valueColor: AppColors.textPrimary,
                        signal: '52-week low',
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
                        label: 'VS BTC',
                        value: vsBtc,
                        valueColor: AppColors.textSecondary,
                        signal: 'Relative performance',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'SIGNAL',
                        value: 'Leveraged BTC',
                        valueColor: AppColors.btcOrange,
                        signal: 'Leveraged BTC exposure',
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

  Widget _header(
    String category,
    String page,
    String value,
    String change,
    Color changeColor,
  ) {
    return SizedBox(
      height: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Text(category,
                style: const TextStyle(
                    color: AppColors.btcOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(width: 6),
            Text(page,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.0)),
          ]),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0)),
              const SizedBox(width: 8),
              Text(change,
                  style: TextStyle(
                      color: changeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
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
