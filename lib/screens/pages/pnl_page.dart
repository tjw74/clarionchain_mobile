import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/exchange_tick.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';

// ── Formatting ────────────────────────────────────────────────────────────────

String _compactUsd(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(2)}T';
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
  return '\$${v.toStringAsFixed(0)}';
}

String _axisLabel(double v) {
  if (v >= 1e12) return '\$${(v / 1e12).toStringAsFixed(1)}T';
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(0)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(0)}M';
  return '\$${v.toStringAsFixed(0)}';
}

// ── Dual-line chart ───────────────────────────────────────────────────────────

class _PnlChart extends StatefulWidget {
  final List<PriceTick> profit;
  final List<PriceTick> loss;
  final Color profitColor;
  final Color lossColor;

  const _PnlChart({
    required this.profit,
    required this.loss,
    required this.profitColor,
    required this.lossColor,
  });

  @override
  State<_PnlChart> createState() => _PnlChartState();
}

class _PnlChartState extends State<_PnlChart> {
  double _viewStart = 0.0;
  double _viewEnd = 1.0;
  double _gsWidth = 0, _gsFocalX = 0, _gsViewStart = 0, _gsViewEnd = 1;

  @override
  Widget build(BuildContext context) {
    final profit = widget.profit;
    final loss = widget.loss;
    if (profit.isEmpty) return const SizedBox.shrink();

    final n = profit.length;
    final si = (_viewStart * (n - 1)).round().clamp(0, n - 1);
    final ei = (_viewEnd * (n - 1)).round().clamp(0, n - 1);
    final pSlice =
        si < ei ? profit.sublist(si, ei + 1) : [profit.last];

    final startTs = pSlice.first.timestamp;
    final endTs = pSlice.last.timestamp;
    final lSlice = loss
        .where((t) =>
            !t.timestamp.isBefore(startTs) && !t.timestamp.isAfter(endTs))
        .toList();

    final pSpots = pSlice.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price))
        .toList();

    final totalMs =
        endTs.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
    final lSpots = lSlice.map((t) {
      final elapsedMs =
          t.timestamp.millisecondsSinceEpoch - startTs.millisecondsSinceEpoch;
      final x = totalMs > 0
          ? (elapsedMs / totalMs) * (pSlice.length - 1)
          : 0.0;
      return FlSpot(x, t.price);
    }).toList();

    final allVals = [
      ...pSlice.map((t) => t.price),
      ...lSlice.map((t) => t.price),
    ];
    final maxY = allVals.reduce((a, b) => a > b ? a : b);
    final yPad = maxY * 0.08;

    final vc = pSlice.length;
    final labelInterval =
        (vc / 4).floorToDouble().clamp(1.0, double.infinity);
    final visibleDays = endTs.difference(startTs).inDays.toDouble();

    String timeLabel(DateTime dt) {
      if (visibleDays <= 60) return '${dt.month}/${dt.day}';
      if (visibleDays <= 365) {
        const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return m[dt.month];
      }
      return '${dt.year}';
    }

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
        final newSpan = (oldSpan / d.scale).clamp(0.01, 1.0);
        final focalFrac = (_gsFocalX / _gsWidth).clamp(0.0, 1.0);
        final focalData = _gsViewStart + focalFrac * oldSpan;
        final panData = -((d.localFocalPoint.dx - _gsFocalX) / _gsWidth) * newSpan;
        final s = (focalData - focalFrac * newSpan + panData)
            .clamp(0.0, 1.0 - newSpan);
        setState(() { _viewStart = s; _viewEnd = s + newSpan; });
      },
      onDoubleTap: () => setState(() { _viewStart = 0; _viewEnd = 1.0; }),
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
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
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
                reservedSize: 20,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= pSlice.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
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
              isCurved: vc < 200,
              curveSmoothness: 0.2,
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
                    widget.profitColor.withValues(alpha: 0.18),
                    widget.profitColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            if (lSpots.isNotEmpty)
              LineChartBarData(
                spots: lSpots,
                isCurved: true,
                curveSmoothness: 0.2,
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
                      widget.lossColor.withValues(alpha: 0.18),
                      widget.lossColor.withValues(alpha: 0.0),
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
}

// ── Stat row ──────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8)),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader(
      {required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
      Container(width: 3, height: 14,
          decoration: BoxDecoration(color: color,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
      const SizedBox(width: 8),
      Expanded(child: Text(subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 10),
          overflow: TextOverflow.ellipsis)),
    ]);
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class PnlPage extends ConsumerWidget {
  const PnlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uProfit = ref.watch(unrealizedProfitProvider).valueOrNull ?? [];
    final uLoss = ref.watch(unrealizedLossProvider).valueOrNull ?? [];
    final rProfit = ref.watch(realizedProfitProvider).valueOrNull ?? [];
    final rLoss = ref.watch(realizedLossProvider).valueOrNull ?? [];
    final supplyInProfit = ref.watch(supplyInProfitProvider).valueOrNull ?? [];

    // Current (latest) values
    final curUP = uProfit.isNotEmpty ? uProfit.last.price : 0.0;
    final curUL = uLoss.isNotEmpty ? uLoss.last.price : 0.0;
    final curRP = rProfit.isNotEmpty ? rProfit.last.price : 0.0;
    final curRL = rLoss.isNotEmpty ? rLoss.last.price : 0.0;
    final netUnrealized = curUP - curUL;
    final netRealized = curRP - curRL;

    // Supply in profit %  (values are in satoshis)
    const totalSats = 19800000 * 100000000.0;
    final supplyPct = supplyInProfit.isNotEmpty
        ? (supplyInProfit.last.price / totalSats * 100).clamp(0, 100)
        : 0.0;

    // Interpret unrealized pressure
    String unrealizedSignal;
    Color unrealizedSignalColor;
    if (curUP == 0 && curUL == 0) {
      unrealizedSignal = 'Loading…';
      unrealizedSignalColor = AppColors.textMuted;
    } else if (curUP > curUL * 5) {
      unrealizedSignal = 'High sell pressure';
      unrealizedSignalColor = AppColors.negative;
    } else if (curUP > curUL * 2) {
      unrealizedSignal = 'Elevated sell pressure';
      unrealizedSignalColor = Color(0xFFFF8C00);
    } else if (curUL > curUP * 2) {
      unrealizedSignal = 'Capitulation pressure';
      unrealizedSignalColor = Color(0xFF6B8EFF);
    } else {
      unrealizedSignal = 'Balanced market';
      unrealizedSignalColor = AppColors.textSecondary;
    }

    // Loading state
    final loading = uProfit.isEmpty && uLoss.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),

        // Header
        Row(children: [
          const Icon(Icons.waterfall_chart_rounded,
              color: AppColors.btcOrange, size: 20),
          const SizedBox(width: 8),
          const Text('PROFIT & LOSS',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          const Spacer(),
          if (!loading)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: unrealizedSignalColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(unrealizedSignal,
                  style: TextStyle(
                      color: unrealizedSignalColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
        ]),

        const SizedBox(height: 14),

        if (loading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.btcOrange, strokeWidth: 2),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // ── UNREALIZED ────────────────────────────────────────
                _SectionHeader(
                  title: 'UNREALIZED',
                  subtitle:
                      'Incentive to sell (profit) or capitulate (loss)',
                  color: AppColors.positive,
                ),
                const SizedBox(height: 10),

                SizedBox(
                  height: 180,
                  child: Stack(children: [
                    _PnlChart(
                      profit: uProfit,
                      loss: uLoss,
                      profitColor: AppColors.positive,
                      lossColor: AppColors.negative,
                    ),
                    Positioned(top: 6, left: 6,
                      child: Row(children: [
                        _dot(AppColors.positive),
                        const SizedBox(width: 4),
                        const Text('Profit',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10)),
                        const SizedBox(width: 10),
                        _dot(AppColors.negative),
                        const SizedBox(width: 4),
                        const Text('Loss',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10)),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 10),

                // Unrealized stat tiles
                Row(children: [
                  _StatTile(
                    label: 'UNREALIZED PROFIT',
                    value: curUP > 0 ? _compactUsd(curUP) : '—',
                    valueColor: AppColors.positive,
                    sub: 'BTC held above cost basis',
                  ),
                  const SizedBox(width: 8),
                  _StatTile(
                    label: 'UNREALIZED LOSS',
                    value: curUL > 0 ? _compactUsd(curUL) : '—',
                    valueColor: AppColors.negative,
                    sub: 'BTC held below cost basis',
                  ),
                ]),

                const SizedBox(height: 8),

                Row(children: [
                  _StatTile(
                    label: 'NET UNREALIZED',
                    value: (curUP > 0 || curUL > 0)
                        ? '${netUnrealized >= 0 ? '+' : ''}${_compactUsd(netUnrealized)}'
                        : '—',
                    valueColor: netUnrealized >= 0
                        ? AppColors.positive
                        : AppColors.negative,
                    sub: 'Profit minus loss exposure',
                  ),
                  const SizedBox(width: 8),
                  _StatTile(
                    label: 'SUPPLY IN PROFIT',
                    value: supplyPct > 0
                        ? '${supplyPct.toStringAsFixed(1)}%'
                        : '—',
                    valueColor: supplyPct > 70
                        ? AppColors.negative
                        : supplyPct < 40
                            ? const Color(0xFF6B8EFF)
                            : AppColors.textPrimary,
                    sub: 'of circulating BTC',
                  ),
                ]),

                const SizedBox(height: 20),

                // ── REALIZED ──────────────────────────────────────────
                _SectionHeader(
                  title: 'REALIZED',
                  subtitle: 'Actual profit taking and loss capitulation',
                  color: AppColors.btcOrange,
                ),
                const SizedBox(height: 10),

                SizedBox(
                  height: 180,
                  child: Stack(children: [
                    _PnlChart(
                      profit: rProfit,
                      loss: rLoss,
                      profitColor: AppColors.btcOrange,
                      lossColor: const Color(0xFF6B8EFF),
                    ),
                    Positioned(top: 6, left: 6,
                      child: Row(children: [
                        _dot(AppColors.btcOrange),
                        const SizedBox(width: 4),
                        const Text('Profit taken',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10)),
                        const SizedBox(width: 10),
                        _dot(Color(0xFF6B8EFF)),
                        const SizedBox(width: 4),
                        const Text('Loss realized',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10)),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 10),

                Row(children: [
                  _StatTile(
                    label: 'REALIZED PROFIT',
                    value: curRP > 0 ? _compactUsd(curRP) : '—',
                    valueColor: AppColors.btcOrange,
                    sub: 'Profit locked in today',
                  ),
                  const SizedBox(width: 8),
                  _StatTile(
                    label: 'REALIZED LOSS',
                    value: curRL > 0 ? _compactUsd(curRL) : '—',
                    valueColor: const Color(0xFF6B8EFF),
                    sub: 'Loss accepted today',
                  ),
                ]),

                const SizedBox(height: 8),

                Row(children: [
                  _StatTile(
                    label: 'NET REALIZED',
                    value: (curRP > 0 || curRL > 0)
                        ? '${netRealized >= 0 ? '+' : ''}${_compactUsd(netRealized)}'
                        : '—',
                    valueColor: netRealized >= 0
                        ? AppColors.btcOrange
                        : const Color(0xFF6B8EFF),
                    sub: 'Net flow today',
                  ),
                  const SizedBox(width: 8),
                  // Ratio card
                  _StatTile(
                    label: 'PROFIT/LOSS RATIO',
                    value: curRL > 0
                        ? (curRP / curRL).toStringAsFixed(2)
                        : '—',
                    valueColor: (curRL == 0 || curRP / curRL >= 1)
                        ? AppColors.btcOrange
                        : const Color(0xFF6B8EFF),
                    sub: '>1 profit dominant · <1 loss',
                  ),
                ]),

                const SizedBox(height: 20),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _dot(Color color) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
