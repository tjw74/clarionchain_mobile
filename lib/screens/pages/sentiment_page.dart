import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';

class SentimentPage extends ConsumerWidget {
  const SentimentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentimentAsync = ref.watch(sentimentMetricsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.psychology_rounded,
                    color: AppColors.btcOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'SENTIMENT',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            sentimentAsync.when(
              loading: () => const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.btcOrange, strokeWidth: 2),
                ),
              ),
              error: (e, _) => const Expanded(
                child: Center(child: _UnavailableCard()),
              ),
              data: (s) {
                final gaugeColor = _gaugeColor(s.fearGreedIndex);

                return Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Fear & Greed gauge
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 24),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: gaugeColor.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'FEAR & GREED INDEX',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Mapped from NUPL (BRK / bitview.space)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textMuted,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _GaugeWidget(value: s.fearGreedIndex),
                              const SizedBox(height: 16),
                              Text(
                                s.fearGreedLabel.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: gaugeColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${s.fearGreedIndex.toStringAsFixed(0)} / 100',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Gauge legend
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              _legendRow(0, 20, 'Extreme Fear',
                                  const Color(0xFFFF4444)),
                              _legendRow(21, 40, 'Fear',
                                  const Color(0xFFFF8C42)),
                              _legendRow(41, 60, 'Neutral',
                                  const Color(0xFF8A8A9A)),
                              _legendRow(61, 80, 'Greed',
                                  const Color(0xFF90EE90)),
                              _legendRow(81, 100, 'Extreme Greed',
                                  AppColors.positive),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Context note
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded,
                                  size: 16, color: AppColors.btcOrange),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Extreme fear may signal a buying opportunity. '
                                  'Extreme greed suggests the market may need a correction. '
                                  'Updates every 15 minutes.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _gaugeColor(double value) {
    if (value <= 20) return const Color(0xFFFF4444);
    if (value <= 40) return const Color(0xFFFF8C42);
    if (value <= 60) return const Color(0xFF8A8A9A);
    if (value <= 80) return const Color(0xFF90EE90);
    return AppColors.positive;
  }

  Widget _legendRow(int from, int to, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$from – $to',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _GaugeWidget extends StatelessWidget {
  final double value; // 0-100

  const _GaugeWidget({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 110,
      child: CustomPaint(
        painter: _GaugePainter(value: value),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;

  _GaugePainter({required this.value});

  static const _segments = [
    (0.0, 0.2, Color(0xFFFF4444)),
    (0.2, 0.4, Color(0xFFFF8C42)),
    (0.4, 0.6, Color(0xFF8A8A9A)),
    (0.6, 0.8, Color(0xFF90EE90)),
    (0.8, 1.0, AppColors.positive),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;
    const trackWidth = 14.0;
    // Arc goes from π (left) to 0 (right), sweeping -π (i.e., the top half)
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Track background
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.border,
    );

    // Colored segments (dimmed)
    for (final seg in _segments) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + sweepAngle * seg.$1,
        sweepAngle * (seg.$2 - seg.$1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackWidth
          ..strokeCap = StrokeCap.butt
          ..color = seg.$3.withValues(alpha: 0.25),
      );
    }

    // Active fill up to current value
    final fraction = (value / 100).clamp(0.0, 1.0);
    Color activeColor;
    if (value <= 20) activeColor = const Color(0xFFFF4444);
    else if (value <= 40) activeColor = const Color(0xFFFF8C42);
    else if (value <= 60) activeColor = const Color(0xFF8A8A9A);
    else if (value <= 80) activeColor = const Color(0xFF90EE90);
    else activeColor = AppColors.positive;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round
        ..color = activeColor,
    );

    // Needle dot at current position
    final needleAngle = startAngle + sweepAngle * fraction;
    final dotX = center.dx + radius * math.cos(needleAngle);
    final dotY = center.dy + radius * math.sin(needleAngle);

    canvas.drawCircle(
      Offset(dotX, dotY),
      7,
      Paint()..color = AppColors.textPrimary,
    );
    canvas.drawCircle(
      Offset(dotX, dotY),
      4,
      Paint()..color = activeColor,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 40, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Sentiment data unavailable',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'Could not load the NUPL series from\nbitview.space (Bitcoin Research Kit API).',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
