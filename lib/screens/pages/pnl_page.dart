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

double _default4YrStart(int n) {
  const days4yr = 1460;
  if (n <= days4yr) return 0.0;
  return (n - days4yr) / n;
}

// ── Chart widget ──────────────────────────────────────────────────────────────

class _PnlChart extends StatefulWidget {
  final List<PriceTick> profit;
  final List<PriceTick> loss;
  final Color profitColor;
  final Color lossColor;
  final double viewStart;
  final double viewEnd;
  final void Function(double start, double end) onViewChanged;

  const _PnlChart({
    required this.profit,
    required this.loss,
    required this.profitColor,
    required this.lossColor,
    required this.viewStart,
    required this.viewEnd,
    required this.onViewChanged,
  });

  @override
  State<_PnlChart> createState() => _PnlChartState();
}

class _PnlChartState extends State<_PnlChart> {
  double _gsWidth = 0, _gsFocalX = 0, _gsStart = 0, _gsEnd = 1;

  @override
  Widget build(BuildContext context) {
    final profit = widget.profit;
    final loss   = widget.loss;
    if (profit.isEmpty) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.btcOrange, strokeWidth: 2));
    }

    final n  = profit.length;
    final si = (widget.viewStart * (n - 1)).round().clamp(0, n - 1);
    final ei = (widget.viewEnd   * (n - 1)).round().clamp(0, n - 1);
    final pSlice = si < ei ? profit.sublist(si, ei + 1) : [profit.last];
    final startTs = pSlice.first.timestamp;
    final endTs   = pSlice.last.timestamp;

    final lSlice = loss.where((t) =>
        !t.timestamp.isBefore(startTs) && !t.timestamp.isAfter(endTs)).toList();

    final pSpots = pSlice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price)).toList();

    final totalMs = endTs.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
    final lSpots = lSlice.map((t) {
      final ms = t.timestamp.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
      return FlSpot(totalMs > 0 ? (ms / totalMs) * (pSlice.length - 1) : 0.0, t.price);
    }).toList();

    final allVals = [...pSlice.map((t) => t.price), ...lSlice.map((t) => t.price)];
    final maxY = allVals.isNotEmpty ? allVals.reduce(max) : 1.0;
    final visibleDays = endTs.difference(startTs).inDays.toDouble();
    final labelInterval = (pSlice.length / 5).floorToDouble().clamp(1.0, double.infinity);

    String timeLabel(DateTime dt) {
      if (visibleDays <= 90)  return '${dt.month}/${dt.day}';
      if (visibleDays <= 730) return ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month];
      return '\'${dt.year % 100}';
    }

    return GestureDetector(
      onScaleStart: (d) {
        _gsWidth  = (context.findRenderObject() as RenderBox?)?.size.width ?? 300;
        _gsFocalX = d.localFocalPoint.dx;
        _gsStart  = widget.viewStart;
        _gsEnd    = widget.viewEnd;
      },
      onScaleUpdate: (d) {
        if (_gsWidth == 0 || d.pointerCount < 2) return;
        final oldSpan = _gsEnd - _gsStart;
        final newSpan = (oldSpan / d.scale).clamp(0.02, 1.0);
        final ff = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final pan = -((d.localFocalPoint.dx - _gsFocalX) / _gsWidth) * newSpan;
        final s = (_gsStart + ff * oldSpan - ff * newSpan + pan).clamp(0.0, 1.0 - newSpan);
        widget.onViewChanged(s, s + newSpan);
      },
      onDoubleTap: () => widget.onViewChanged(_default4YrStart(n), 1.0),
      child: LineChart(
        LineChartData(
          minY: 0, maxY: maxY * 1.06,
          clipData: const FlClipData.all(),
          lineTouchData: const LineTouchData(enabled: false),
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 48,
              getTitlesWidget: (v, meta) {
                if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                return Text(_axisLabel(v),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                    textAlign: TextAlign.right);
              },
            )),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 18,
              interval: labelInterval,
              getTitlesWidget: (v, meta) {
                final idx = v.toInt();
                if (idx < 0 || idx >= pSlice.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(timeLabel(pSlice[idx].timestamp),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                );
              },
            )),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: pSpots, isCurved: false,
              color: widget.profitColor, barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [widget.profitColor.withValues(alpha: 0.22),
                         widget.profitColor.withValues(alpha: 0.0)],
              )),
            ),
            if (lSpots.isNotEmpty)
              LineChartBarData(
                spots: lSpots, isCurved: false,
                color: widget.lossColor, barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [widget.lossColor.withValues(alpha: 0.22),
                           widget.lossColor.withValues(alpha: 0.0)],
                )),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 80),
      ),
    );
  }
}

// ── Ratio chart ───────────────────────────────────────────────────────────────

class _RatioChart extends StatelessWidget {
  final List<PriceTick> profit;
  final List<PriceTick> loss;
  final double viewStart;
  final double viewEnd;

  const _RatioChart({
    required this.profit, required this.loss,
    required this.viewStart, required this.viewEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (profit.isEmpty || loss.isEmpty) return const SizedBox.expand();
    final minN = min(profit.length, loss.length);
    final n    = profit.length;
    final si   = (viewStart * (n - 1)).round().clamp(0, minN - 1);
    final ei   = (viewEnd   * (n - 1)).round().clamp(0, minN - 1);
    if (si >= ei) return const SizedBox.expand();

    final spots = <FlSpot>[];
    double maxAbs = 0;
    for (int i = si; i <= ei; i++) {
      final p = profit[i].price, l = loss[i].price;
      if (p <= 0 || l <= 0) continue;
      final r = log(p / l);
      spots.add(FlSpot((i - si).toDouble(), r));
      maxAbs = max(maxAbs, r.abs());
    }
    if (spots.isEmpty) return const SizedBox.expand();
    final yBound = (maxAbs * 1.1).clamp(0.5, double.infinity);
    final labelInterval = ((ei - si) / 5).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays = profit[ei].timestamp.difference(profit[si].timestamp).inDays.toDouble();

    String timeLabel(DateTime dt) {
      if (visibleDays <= 90)  return '${dt.month}/${dt.day}';
      if (visibleDays <= 730) return ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month];
      return '\'${dt.year % 100}';
    }

    return LineChart(
      LineChartData(
        minY: -yBound, maxY: yBound,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          checkToShowHorizontalLine: (v) => v == 0,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.textMuted.withValues(alpha: 0.5),
            strokeWidth: 1.5, dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 18,
            interval: labelInterval,
            getTitlesWidget: (v, meta) {
              final i = si + v.toInt();
              if (i < 0 || i >= profit.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(timeLabel(profit[i].timestamp),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              );
            },
          )),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: false, barWidth: 1.5,
            dotData: const FlDotData(show: false),
            gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [AppColors.positive, AppColors.negative], stops: [0.5, 0.5],
            ),
            belowBarData: BarAreaData(
              show: true, color: AppColors.negative.withValues(alpha: 0.12),
              cutOffY: 0, applyCutOffY: true,
            ),
            aboveBarData: BarAreaData(
              show: true, color: AppColors.positive.withValues(alpha: 0.12),
              cutOffY: 0, applyCutOffY: true,
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 80),
    );
  }
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String sub;

  const _Stat({required this.label, required this.value,
               required this.color, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              color: AppColors.textMuted, fontSize: 9,
              fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(
              color: color, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

Widget _dot(Color c) => Container(width: 7, height: 7,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle));

// ── Page ──────────────────────────────────────────────────────────────────────

class PnlPage extends ConsumerStatefulWidget {
  const PnlPage({super.key});

  @override
  ConsumerState<PnlPage> createState() => _PnlPageState();
}

class _PnlPageState extends ConsumerState<PnlPage> {
  double _viewStart = 0.0;
  double _viewEnd   = 1.0;
  bool   _init      = false;

  @override
  Widget build(BuildContext context) {
    final uProfit  = ref.watch(unrealizedProfitProvider).valueOrNull ?? [];
    final uLoss    = ref.watch(unrealizedLossProvider).valueOrNull   ?? [];
    final supply   = ref.watch(supplyInProfitProvider).valueOrNull   ?? [];

    if (!_init && uProfit.length > 100) {
      _viewStart = _default4YrStart(uProfit.length);
      _init = true;
    }

    final curUP = uProfit.isNotEmpty ? uProfit.last.price : 0.0;
    final curUL = uLoss.isNotEmpty   ? uLoss.last.price   : 0.0;
    final net   = curUP - curUL;
    const totalSats = 19800000 * 100000000.0;
    final supplyPct = supply.isNotEmpty
        ? (supply.last.price / totalSats * 100).clamp(0.0, 100.0) : 0.0;

    String signal; Color signalColor;
    if (curUP == 0 && curUL == 0) {
      signal = 'Loading…'; signalColor = AppColors.textMuted;
    } else if (curUP > curUL * 5) {
      signal = 'High sell pressure'; signalColor = AppColors.negative;
    } else if (curUP > curUL * 2) {
      signal = 'Elevated pressure'; signalColor = const Color(0xFFFF8C00);
    } else if (curUL > curUP * 2) {
      signal = 'Capitulation'; signalColor = const Color(0xFF6B8EFF);
    } else {
      signal = 'Balanced market'; signalColor = AppColors.textSecondary;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final totalH    = constraints.maxHeight;
      // Fixed-height sections
      const headerH   = 28.0;
      const ratioHdrH = 22.0;
      const statsH    = 130.0; // 2 rows × ~57px + gap
      const spacing   = 8.0 * 5;
      final chartH    = (totalH - headerH - ratioHdrH - statsH - spacing) * 0.65;
      final ratioH    = (totalH - headerH - ratioHdrH - statsH - spacing) * 0.35;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ───────────────────────────────────────────────────
            SizedBox(
              height: headerH,
              child: Row(children: [
                const Text('UNREALIZED P&L',
                    style: TextStyle(color: AppColors.textSecondary,
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(width: 10),
                _dot(AppColors.positive),
                const SizedBox(width: 4),
                const Text('Profit', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
                const SizedBox(width: 8),
                _dot(AppColors.negative),
                const SizedBox(width: 4),
                const Text('Loss', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(signal, style: TextStyle(
                      color: signalColor, fontSize: 10,
                      fontWeight: FontWeight.w600)),
                ),
              ]),
            ),

            const SizedBox(height: 8),

            // ── Main chart ───────────────────────────────────────────────
            SizedBox(
              height: chartH,
              child: _PnlChart(
                profit: uProfit, loss: uLoss,
                profitColor: AppColors.positive,
                lossColor: AppColors.negative,
                viewStart: _viewStart, viewEnd: _viewEnd,
                onViewChanged: (s, e) => setState(() {
                  _viewStart = s; _viewEnd = e;
                }),
              ),
            ),

            const SizedBox(height: 8),

            // ── Ratio header ──────────────────────────────────────────────
            SizedBox(
              height: ratioHdrH,
              child: Row(children: [
                const Text('P/L RATIO',
                    style: TextStyle(color: AppColors.textSecondary,
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(width: 8),
                _dot(AppColors.positive),
                const SizedBox(width: 4),
                const Text('Profit dominant', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
                const SizedBox(width: 8),
                _dot(AppColors.negative),
                const SizedBox(width: 4),
                const Text('Loss dominant', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
              ]),
            ),

            const SizedBox(height: 6),

            // ── Ratio chart ───────────────────────────────────────────────
            SizedBox(
              height: ratioH,
              child: _RatioChart(
                profit: uProfit, loss: uLoss,
                viewStart: _viewStart, viewEnd: _viewEnd,
              ),
            ),

            const SizedBox(height: 8),

            // ── Stats ─────────────────────────────────────────────────────
            SizedBox(
              height: statsH,
              child: Column(children: [
                Expanded(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Stat(label: 'UNREALIZED PROFIT',
                        value: curUP > 0 ? _compactUsd(curUP) : '—',
                        color: AppColors.positive,
                        sub: 'BTC above cost basis'),
                    const SizedBox(width: 8),
                    _Stat(label: 'UNREALIZED LOSS',
                        value: curUL > 0 ? _compactUsd(curUL) : '—',
                        color: AppColors.negative,
                        sub: 'BTC below cost basis'),
                  ],
                )),
                const SizedBox(height: 8),
                Expanded(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Stat(label: 'NET UNREALIZED',
                        value: (curUP > 0 || curUL > 0)
                            ? '${net >= 0 ? '+' : ''}${_compactUsd(net)}' : '—',
                        color: net >= 0 ? AppColors.positive : AppColors.negative,
                        sub: 'Profit minus loss'),
                    const SizedBox(width: 8),
                    _Stat(label: 'SUPPLY IN PROFIT',
                        value: supplyPct > 0
                            ? '${supplyPct.toStringAsFixed(1)}%' : '—',
                        color: supplyPct > 75 ? AppColors.negative
                            : supplyPct < 40 ? const Color(0xFF6B8EFF)
                            : AppColors.textPrimary,
                        sub: 'of circulating BTC'),
                  ],
                )),
              ]),
            ),
          ],
        ),
      );
    });
  }
}
