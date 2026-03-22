import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/metrics_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_card.dart';

final _numFmt = NumberFormat('#,##0.00', 'en_US');
final _dateFmt = DateFormat('MMM d, y');

class MiningPage extends ConsumerWidget {
  const MiningPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miningAsync = ref.watch(miningMetricsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.memory_rounded, color: AppColors.btcOrange, size: 20),
                SizedBox(width: 8),
                Text(
                  'MINING',
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
            miningAsync.when(
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
                      Text('Could not load mining data',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              data: (m) {
                final adjColor = m.difficultyAdjustmentPercent > 0
                    ? AppColors.negative
                    : AppColors.positive;
                final adjSign =
                    m.difficultyAdjustmentPercent > 0 ? '+' : '';

                return Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Hashrate hero
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
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
                                'NETWORK HASHRATE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    m.hashrateEhs > 0
                                        ? _numFmt.format(m.hashrateEhs)
                                        : '—',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 5),
                                    child: Text(
                                      'EH/s',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Exahashes per second',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Difficulty adjustment
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: adjColor.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'NEXT ADJUSTMENT',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textMuted,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$adjSign${m.difficultyAdjustmentPercent.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: adjColor,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    if (m.estimatedAdjustmentDate != null)
                                      Text(
                                        'Est. ${_dateFmt.format(m.estimatedAdjustmentDate!)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 56,
                                color: AppColors.border,
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'BLOCKS LEFT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${m.blocksUntilAdjustment}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const Text(
                                    'of 2,016',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Progress bar for difficulty epoch
                        _DifficultyProgress(
                            blocksRemaining: m.blocksUntilAdjustment),

                        const SizedBox(height: 10),

                        StatCard(
                          label: 'Current Difficulty',
                          icon: Icons.speed_rounded,
                          value: _formatDifficulty(m.currentDifficulty),
                          subValue: 'Adjusts every 2,016 blocks (~2 weeks)',
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

  String _formatDifficulty(double d) {
    if (d >= 1e12) return '${(d / 1e12).toStringAsFixed(2)}T';
    if (d >= 1e9) return '${(d / 1e9).toStringAsFixed(2)}B';
    return d.toStringAsFixed(0);
  }
}

class _DifficultyProgress extends StatelessWidget {
  final int blocksRemaining;

  const _DifficultyProgress({required this.blocksRemaining});

  @override
  Widget build(BuildContext context) {
    const epochSize = 2016;
    final done = ((epochSize - blocksRemaining) / epochSize).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EPOCH PROGRESS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${(done * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.btcOrange),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${epochSize - blocksRemaining} blocks mined',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                '$blocksRemaining remaining',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
