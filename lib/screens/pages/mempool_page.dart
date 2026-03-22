import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

final _numFmt = NumberFormat('#,##0', 'en_US');

class MempoolPage extends ConsumerWidget {
  const MempoolPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mempoolAsync = ref.watch(mempoolMetricsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.inbox_rounded, color: AppColors.btcOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'MEMPOOL & FEES',
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
            mempoolAsync.when(
              loading: () => const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.btcOrange, strokeWidth: 2),
                ),
              ),
              error: (e, _) => const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: AppColors.textMuted, size: 32),
                      SizedBox(height: 8),
                      Text('Could not load mempool data',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              data: (m) {
                final sizeLabel = _formatBytes(m.mempoolSizeBytes);

                return Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Fee tiers
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.btcOrange.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'RECOMMENDED FEES',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _FeeRow(
                                label: 'Next Block',
                                icon: Icons.bolt_rounded,
                                iconColor: AppColors.negative,
                                value: '${m.feeFastSatsPerVb} sat/vB',
                              ),
                              const SizedBox(height: 10),
                              _FeeRow(
                                label: '~30 min',
                                icon: Icons.timer_outlined,
                                iconColor: AppColors.btcOrange,
                                value: '${m.feeMediumSatsPerVb} sat/vB',
                              ),
                              const SizedBox(height: 10),
                              _FeeRow(
                                label: '~1 hour',
                                icon: Icons.hourglass_bottom_rounded,
                                iconColor: AppColors.positive,
                                value: '${m.feeSlowSatsPerVb} sat/vB',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        StatRow(cards: [
                          StatCard(
                            label: 'Pending TXs',
                            icon: Icons.receipt_long_outlined,
                            value: _numFmt.format(m.pendingTxCount),
                            subValue: 'Unconfirmed',
                          ),
                          StatCard(
                            label: 'Mempool Size',
                            icon: Icons.data_usage_rounded,
                            value: sizeLabel,
                            subValue: 'Virtual bytes',
                          ),
                        ]),

                        const SizedBox(height: 10),

                        StatCard(
                          label: 'Pending Fees',
                          icon: Icons.toll_outlined,
                          value: '${m.totalFeeBtc.toStringAsFixed(4)} BTC',
                          subValue: 'Total fees waiting for miners',
                        ),

                        const SizedBox(height: 10),

                        // Context note
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  size: 16, color: AppColors.textMuted),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Fees update every 30 seconds. '
                                  'High mempool congestion means longer waits '
                                  'and higher required fees.',
                                  style: const TextStyle(
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

  String _formatBytes(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final String value;

  const _FeeRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
