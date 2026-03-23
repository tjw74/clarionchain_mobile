import 'dart:math' show min, max, log;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/exchange_tick.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';

// ── Formatting ────────────────────────────────────────────────────────────────

String _compactUsd(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9)  return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6)  return '\$${(v / 1e6).toStringAsFixed(1)}M';
  return '\$${v.toStringAsFixed(0)}';
}

String _axisLabel(double v) {
  if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(1)}T';
  if (v >= 1e9)  return '${(v / 1e9).toStringAsFixed(0)}B';
  if (v >= 1e6)  return '${(v / 1e6).toStringAsFixed(0)}M';
  return v.toStringAsFixed(0);
}

// ── Shared view-window state ──────────────────────────────────────────────────
// Both charts share _viewStart/_viewEnd so they scroll/zoom together.

class _ViewWindow {
  double start;
  double end;
  _ViewWindow(this.start, this.end);
}

// ── Main P&L chart ────────────────────────────────────────────────────────────

class _PnlChart extends StatefulWidget {
  final List<PriceTick> profit;
  final List<PriceTick> loss;
  final Color profitColor;
  final Color lossColor;
  final _ViewWindow view;
  final ValueChanged<_ViewWindow> onViewChanged;

  const _PnlChart({
    required this.profit,
    required this.loss,
    required this.profitColor,
    required this.lossColor,
    required this.view,
    required this.onViewChanged,
  });

  @override
  State<_PnlChart> createState() => _PnlChartState();
}

class _PnlChartState extends State<_PnlChart> {
  double _gsWidth = 0, _gsFocalX = 0, _gsViewStart = 0, _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final profit = widget.profit;
    final loss   = widget.loss;
    if (profit.isEmpty) return const SizedBox.expand();

    final n  = profit.length;
    final vs = widget.view.start;
    final ve = widget.view.end;
    final si = (vs * (n - 1)).round().clamp(0, n - 1);
    final ei = (ve * (n - 1)).round().clamp(0, n - 1);
    final pSlice = si < ei ? profit.sublist(si, ei + 1) : [profit.last];

    final startTs = pSlice.first.timestamp;
    final endTs   = pSlice.last.timestamp;
    final lSlice  = loss
        .where((t) => !t.timestamp.isBefore(startTs) &&
                      !t.timestamp.isAfter(endTs))
        .toList();

    final pSpots = pSlice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    final totalMs = endTs.millisecondsSinceEpoch -
                    startTs.millisecondsSinceEpoch;
    final lSpots = lSlice.map((t) {
      final ms = t.timestamp.millisecondsSinceEpoch -
                 startTs.millisecondsSinceEpoch;
      final x  = totalMs > 0
          ? (ms / totalMs) * (pSlice.length - 1) : 0.0;
      return FlSpot(x, t.price);
    }).toList();

    final allVals = [
      ...pSlice.map((t) => t.price),
      ...lSlice.map((t) => t.price),
    ];
    final maxY = allVals.isNotEmpty
        ? allVals.reduce((a, b) => a > b ? a : b) : 1.0;
    final yPad = maxY * 0.06;

    final visibleDays = endTs.difference(startTs).inDays.toDouble();
    final vc = pSlice.length;
    final labelInterval =
        (vc / 5).floorToDouble().clamp(1.0, double.infinity);

    String timeLabel(DateTime dt) {
      if (visibleDays <= 90) return '${dt.month}/${dt.day}';
      if (visibleDays <= 730) {
        const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
        return m[dt.month];
      }
      return '\'${dt.year % 100}';
    }

    return GestureDetector(
      onScaleStart: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        _gsWidth    = rb?.size.width ?? 300;
        _gsFocalX   = d.localFocalPoint.dx;
        _gsViewStart = widget.view.start;
        _gsViewEnd   = widget.view.end;
      },
      onScaleUpdate: (d) {
        if (_gsWidth == 0 || d.pointerCount < 2) return;
        final oldSpan = _gsViewEnd - _gsViewStart;
        final newSpan = (oldSpan / d.scale).clamp(0.02, 1.0);
        final focalFrac = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final focalData = _gsViewStart + focalFrac * oldSpan;
        final panData   = -((d.localFocalPoint.dx - _gsFocalX) / _gsWidth) *
                          newSpan;
        final s = (focalData - focalFrac * newSpan + panData)
            .clamp(0.0, 1.0 - newSpan);
        widget.onViewChanged(_ViewWindow(s, s + newSpan));
      },
      onDoubleTap: () =>
          widget.onViewChanged(_ViewWindow(_default4YrStart(n), 1.0)),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY + yPad,
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
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(_axisLabel(value),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 9),
                      textAlign: TextAlign.right);
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= pSlice.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(timeLabel(pSlice[idx].timestamp),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: pSpots,
              isCurved: false,
              color: widget.profitColor,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.profitColor.withValues(alpha: 0.20),
                    widget.profitColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            if (lSpots.isNotEmpty)
              LineChartBarData(
                spots: lSpots,
                isCurved: false,
                color: widget.lossColor,
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.lossColor.withValues(alpha: 0.20),
                      widget.lossColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      ),
    );
  }
}

// ── Ratio chart ───────────────────────────────────────────────────────────────

class _RatioChart extends StatelessWidget {
  final List<PriceTick> profit;
  final List<PriceTick> loss;
  final _ViewWindow view;
  final ValueChanged<_ViewWindow> onViewChanged;

  const _RatioChart({
    required this.profit,
    required this.loss,
    required this.view,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (profit.isEmpty || loss.isEmpty) return const SizedBox.expand();

    final n    = profit.length;
    final minN = min(profit.length, loss.length);
    final si   = (view.start * (n - 1)).round().clamp(0, minN - 1);
    final ei   = (view.end   * (n - 1)).round().clamp(0, minN - 1);
    if (si >= ei) return const SizedBox.expand();

    // Ratio = log(profit / loss) — positive = profit dominant, negative = loss
    final ratioSpots = <FlSpot>[];
    double maxAbs = 0;
    for (int i = si; i <= ei; i++) {
      final p = profit[i].price;
      final l = loss[i].price;
      if (p <= 0 || l <= 0) continue;
      final r = log(p / l);
      final x = (i - si).toDouble();
      ratioSpots.add(FlSpot(x, r));
      maxAbs = max(maxAbs, r.abs());
    }
    if (ratioSpots.isEmpty) return const SizedBox.expand();

    final yBound = (maxAbs * 1.1).clamp(0.5, double.infinity);
    final vc = ei - si + 1;
    final labelInterval =
        (vc / 5).floorToDouble().clamp(1.0, double.infinity);

    final startTs = profit[si].timestamp;
    final endTs   = profit[ei].timestamp;
    final visibleDays = endTs.difference(startTs).inDays.toDouble();

    String timeLabel(DateTime dt) {
      if (visibleDays <= 90)  return '${dt.month}/${dt.day}';
      if (visibleDays <= 730) {
        const m = ['','Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
        return m[dt.month];
      }
      return '\'${dt.year % 100}';
    }

    double _gsWidth = 0, _gsFocalX = 0;
    double _gsViewStart = view.start, _gsViewEnd = view.end;

    return GestureDetector(
      onScaleStart: (d) {
        final rb = context.findRenderObject() as RenderBox?;
        _gsWidth     = rb?.size.width ?? 300;
        _gsFocalX    = d.localFocalPoint.dx;
        _gsViewStart = view.start;
        _gsViewEnd   = view.end;
      },
      onScaleUpdate: (d) {
        if (_gsWidth == 0 || d.pointerCount < 2) return;
        final oldSpan = _gsViewEnd - _gsViewStart;
        final newSpan = (oldSpan / d.scale).clamp(0.02, 1.0);
        final ff = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final fd = _gsViewStart + ff * oldSpan;
        final pd = -((d.localFocalPoint.dx - _gsFocalX) / _gsWidth) * newSpan;
        final s  = (fd - ff * newSpan + pd).clamp(0.0, 1.0 - newSpan);
        onViewChanged(_ViewWindow(s, s + newSpan));
      },
      child: LineChart(
        LineChartData(
          minY: -yBound,
          maxY: yBound,
          clipData: const FlClipData.all(),
          lineTouchData: const LineTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            checkToShowHorizontalLine: (v) => v == 0,
            getDrawingHorizontalLine: (v) => FlLine(
              color: v == 0
                  ? AppColors.textMuted.withValues(alpha: 0.5)
                  : AppColors.border,
              strokeWidth: v == 0 ? 1.5 : 1,
              dashArray: v == 0 ? [4, 4] : null,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  if (value == 0) {
                    return const Text('0',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 9),
                        textAlign: TextAlign.right);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final i = si + value.toInt();
                  if (i < 0 || i >= profit.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(timeLabel(profit[i].timestamp),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: ratioSpots,
              isCurved: false,
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.positive, AppColors.negative],
                stops: [0.5, 0.5],
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.negative.withValues(alpha: 0.12),
                cutOffY: 0,
                applyCutOffY: true,
              ),
              aboveBarData: BarAreaData(
                show: true,
                color: AppColors.positive.withValues(alpha: 0.12),
                cutOffY: 0,
                applyCutOffY: true,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

double _default4YrStart(int n) {
  const days4yr = 1460;
  if (n <= days4yr) return 0.0;
  return (n - days4yr) / n;
}

Widget _dot(Color color) => Container(
    width: 7, height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle));

Widget _legend(Color color, String label) => Row(children: [
  _dot(color),
  const SizedBox(width: 4),
  Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
]);

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String sub;

  const _StatTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class PnlPage extends ConsumerStatefulWidget {
  const PnlPage({super.key});

  @override
  ConsumerState<PnlPage> createState() => _PnlPageState();
}

class _PnlPageState extends ConsumerState<PnlPage> {
  _ViewWindow _view = _ViewWindow(0.0, 1.0);
  bool _viewInitialized = false;

  @override
  Widget build(BuildContext context) {
    final uProfit       = ref.watch(unrealizedProfitProvider).valueOrNull ?? [];
    final uLoss         = ref.watch(unrealizedLossProvider).valueOrNull ?? [];
    final supplyInProfit = ref.watch(supplyInProfitProvider).valueOrNull ?? [];

    // Initialize 4-year default once data is available
    if (!_viewInitialized && uProfit.length > 100) {
      _view = _ViewWindow(_default4YrStart(uProfit.length), 1.0);
      _viewInitialized = true;
    }

    final curUP = uProfit.isNotEmpty ? uProfit.last.price : 0.0;
    final curUL = uLoss.isNotEmpty   ? uLoss.last.price   : 0.0;
    final netUn = curUP - curUL;

    const totalSats = 19800000 * 100000000.0;
    final supplyPct = supplyInProfit.isNotEmpty
        ? (supplyInProfit.last.price / totalSats * 100).clamp(0.0, 100.0)
        : 0.0;

    // Unrealized signal
    String signal;
    Color signalColor;
    if (curUP == 0 && curUL == 0) {
      signal = 'Loading…';
      signalColor = AppColors.textMuted;
    } else if (curUP > curUL * 5) {
      signal = 'High sell pressure';
      signalColor = AppColors.negative;
    } else if (curUP > curUL * 2) {
      signal = 'Elevated sell pressure';
      signalColor = const Color(0xFFFF8C00);
    } else if (curUL > curUP * 2) {
      signal = 'Capitulation';
      signalColor = const Color(0xFF6B8EFF);
    } else {
      signal = 'Balanced market';
      signalColor = AppColors.textSecondary;
    }

    final loading = uProfit.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header row ────────────────────────────────────────────────────
        Row(children: [
          const Text('UNREALIZED P&L',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(width: 12),
          _legend(AppColors.positive, 'Profit'),
          const SizedBox(width: 10),
          _legend(AppColors.negative, 'Loss'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: signalColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(signal,
                style: TextStyle(
                    color: signalColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ]),

        const SizedBox(height: 8),

        // ── Main P&L chart ────────────────────────────────────────────────
        if (loading)
          const Expanded(child: Center(
            child: CircularProgressIndicator(
                color: AppColors.btcOrange, strokeWidth: 2)))
        else ...[
          Expanded(
            flex: 5,
            child: _PnlChart(
              profit: uProfit,
              loss: uLoss,
              profitColor: AppColors.positive,
              lossColor: AppColors.negative,
              view: _view,
              onViewChanged: (v) => setState(() => _view = v),
            ),
          ),

          const SizedBox(height: 10),

          // ── Ratio section header ───────────────────────────────────────
          Row(children: [
            const Text('P/L RATIO  (log)',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(width: 8),
            _legend(AppColors.positive, 'Profit dominant'),
            const SizedBox(width: 8),
            _legend(AppColors.negative, 'Loss dominant'),
          ]),

          const SizedBox(height: 6),

          // ── Ratio chart ───────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: _RatioChart(
              profit: uProfit,
              loss: uLoss,
              view: _view,
              onViewChanged: (v) => setState(() => _view = v),
            ),
          ),

          const SizedBox(height: 10),

          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            _StatTile(
              label: 'UNREALIZED PROFIT',
              value: curUP > 0 ? _compactUsd(curUP) : '—',
              valueColor: AppColors.positive,
              sub: 'BTC above cost basis',
            ),
            const SizedBox(width: 8),
            _StatTile(
              label: 'UNREALIZED LOSS',
              value: curUL > 0 ? _compactUsd(curUL) : '—',
              valueColor: AppColors.negative,
              sub: 'BTC below cost basis',
            ),
          ]),

          const SizedBox(height: 8),

          Row(children: [
            _StatTile(
              label: 'NET UNREALIZED',
              value: (curUP > 0 || curUL > 0)
                  ? '${netUn >= 0 ? '+' : ''}${_compactUsd(netUn)}'
                  : '—',
              valueColor: netUn >= 0 ? AppColors.positive : AppColors.negative,
              sub: 'Profit minus loss',
            ),
            const SizedBox(width: 8),
            _StatTile(
              label: 'SUPPLY IN PROFIT',
              value: supplyPct > 0
                  ? '${supplyPct.toStringAsFixed(1)}%'
                  : '—',
              valueColor: supplyPct > 75
                  ? AppColors.negative
                  : supplyPct < 40
                      ? const Color(0xFF6B8EFF)
                      : AppColors.textPrimary,
              sub: 'of circulating BTC',
            ),
          ]),

          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}
