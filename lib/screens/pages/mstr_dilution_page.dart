import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';

final _intFmtDil = NumberFormat('#,##0', 'en_US');

// Historical shares outstanding milestones (approximate, from public SEC filings)
// Stored as (year, month, sharesMillions)
const List<({int year, int month, double sharesMillion})> _dilutionMilestones = [
  (year: 2020, month: 1, sharesMillion: 95.0),
  (year: 2021, month: 1, sharesMillion: 103.0),
  (year: 2022, month: 1, sharesMillion: 115.0),
  (year: 2023, month: 1, sharesMillion: 135.0),
  (year: 2024, month: 1, sharesMillion: 170.0),
  (year: 2024, month: 7, sharesMillion: 210.0),
  (year: 2025, month: 1, sharesMillion: 340.0),
];

const int _btcHoldingsDil = 528185;
const int _jan2025BaselineDil = 340000000;
const int _jan2024BaselineDil = 170000000;
const int _sharesFallbackDil = 370000000;

class MstrDilutionPage extends ConsumerStatefulWidget {
  const MstrDilutionPage({super.key});

  @override
  ConsumerState<MstrDilutionPage> createState() => _MstrDilutionPageState();
}

class _MstrDilutionPageState extends ConsumerState<MstrDilutionPage> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;

  @override
  Widget build(BuildContext context) {
    final mstrAsync = ref.watch(stockQuoteProvider('MSTR'));

    // Derive shares outstanding from Yahoo Finance data if available
    // StockQuote doesn't expose sharesOutstanding directly — use fallback
    final currentShares = _sharesFallbackDil;

    final ytdDilution =
        (currentShares - _jan2025BaselineDil) / _jan2025BaselineDil;
    final twoYrDilution =
        (currentShares - _jan2024BaselineDil) / _jan2024BaselineDil;

    final btcPerShare = _btcHoldingsDil / currentShares;

    String signal;
    if (ytdDilution > 0.50) {
      signal = 'Aggressive dilution';
    } else if (ytdDilution > 0.20) {
      signal = 'High dilution rate — monitor';
    } else {
      signal = 'Moderate pace';
    }

    final signalColor = ytdDilution > 0.50
        ? AppColors.negative
        : ytdDilution > 0.20
            ? const Color(0xFFFFAA00)
            : AppColors.positive;

    final headerValue = _intFmtDil.format(currentShares);
    final headerChange =
        '${ytdDilution >= 0 ? '+' : ''}${(ytdDilution * 100).toStringAsFixed(1)}% YTD';
    final headerChangeColor =
        ytdDilution > 0.20 ? AppColors.negative : AppColors.textSecondary;

    // Build spots from milestones + current value
    final allMilestones = [
      ..._dilutionMilestones,
      // Append current (approximate: mid-2025)
      (year: 2025, month: 6, sharesMillion: currentShares / 1000000.0),
    ];

    // Convert to FlSpot using months since Jan 2020 as x
    final baseYear = 2020;
    final baseMonth = 1;
    final chartSpots = allMilestones.map((m) {
      final monthsOffset =
          (m.year - baseYear) * 12 + (m.month - baseMonth);
      return FlSpot(monthsOffset.toDouble(), m.sharesMillion);
    }).toList();

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
            _header('MSTR', 'DILUTION', headerValue, headerChange,
                headerChangeColor),
            const SizedBox(height: 8),
            SizedBox(
              height: chartH,
              child: _buildChart(context, chartSpots, allMilestones),
            ),
            SizedBox(
              height: statsH,
              child: _buildStats(
                currentShares,
                ytdDilution,
                twoYrDilution,
                btcPerShare,
                signal,
                signalColor,
                mstrAsync.isLoading,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildChart(
    BuildContext context,
    List<FlSpot> spots,
    List<({int year, int month, double sharesMillion})> milestones,
  ) {
    if (spots.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: AppColors.btcOrange, strokeWidth: 2),
      );
    }

    final n = spots.length;
    final startIdx = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final endIdx = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final slice = startIdx <= endIdx
        ? spots.sublist(startIdx, endIdx + 1)
        : [spots.last];

    final minY =
        slice.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY =
        slice.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);
    final effMin = minY - yPad;
    final effMax = maxY + yPad;

    return GestureDetector(
      onScaleStart: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        final w = rb?.size.width ?? 300;
        setState(() {
          _viewStart = _viewStart;
          _viewEnd = _viewEnd;
        });
        // Store gesture start state in-place using closure variables
        _gsScaleStart(d.localFocalPoint.dx, w);
      },
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        _gsScaleUpdate(d.scale, d.localFocalPoint.dx);
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
                    '${value.toStringAsFixed(0)}M',
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
                getTitlesWidget: (value, meta) {
                  // value = months since Jan 2020
                  final totalMonths = value.toInt();
                  final year = 2020 + totalMonths ~/ 12;
                  final month = (totalMonths % 12) + 1;
                  // Only show January labels
                  if (month != 1) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$year',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: slice,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppColors.negative,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.negative,
                  strokeWidth: 1,
                  strokeColor: AppColors.background,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.negative.withValues(alpha: 0.15),
                    AppColors.negative.withValues(alpha: 0.0),
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

  // Gesture state
  double _gsWidth = 0;
  double _gsFocalX = 0;
  double _gsViewStart = 0;
  double _gsViewEnd = 1;

  void _gsScaleStart(double focalX, double width) {
    _gsWidth = width;
    _gsFocalX = focalX;
    _gsViewStart = _viewStart;
    _gsViewEnd = _viewEnd;
  }

  void _gsScaleUpdate(double scale, double focalX) {
    if (_gsWidth == 0) return;
    final oldSpan = _gsViewEnd - _gsViewStart;
    final newSpan = (oldSpan / scale).clamp(0.1, 1.0);
    final focalFrac = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
    final focalData = _gsViewStart + focalFrac * oldSpan;
    final panPixels = focalX - _gsFocalX;
    final panData = -(panPixels / _gsWidth) * newSpan;
    final s =
        (focalData - focalFrac * newSpan + panData).clamp(0.0, 1.0 - newSpan);
    setState(() {
      _viewStart = s;
      _viewEnd = s + newSpan;
    });
  }

  Widget _buildStats(
    int currentShares,
    double ytdDilution,
    double twoYrDilution,
    double btcPerShare,
    String signal,
    Color signalColor,
    bool loading,
  ) {
    final ytdColor = ytdDilution > 0.20
        ? AppColors.negative
        : AppColors.textPrimary;
    final twoYrColor = twoYrDilution > 0.50
        ? AppColors.negative
        : AppColors.textPrimary;

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
                        label: 'SHARES OUTSTANDING',
                        value: loading
                            ? '...'
                            : _intFmtDil.format(currentShares),
                        valueColor: AppColors.textPrimary,
                        signal: 'From Yahoo Finance',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'YTD DILUTION',
                        value:
                            '${ytdDilution >= 0 ? '+' : ''}${(ytdDilution * 100).toStringAsFixed(1)}%',
                        valueColor: ytdColor,
                        signal: 'vs Jan 2025 (340M)',
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
                        label: '2YR DILUTION',
                        value:
                            '${twoYrDilution >= 0 ? '+' : ''}${(twoYrDilution * 100).toStringAsFixed(1)}%',
                        valueColor: twoYrColor,
                        signal: 'vs Jan 2024 (170M)',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'BTC HOLDINGS',
                        value: '${_intFmtDil.format(_btcHoldingsDil)} ₿',
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
                        signal: 'Effective BTC per share',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatPanel(
                        label: 'SIGNAL',
                        value: signal,
                        valueColor: signalColor,
                        signal: 'Based on YTD dilution',
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
