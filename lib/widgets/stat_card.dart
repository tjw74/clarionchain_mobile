import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;
  final IconData? icon;
  final bool compact;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
    this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 5),
              ],
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 16 : 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StatRow extends StatelessWidget {
  final List<StatCard> cards;

  const StatRow({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: cards
          .map((card) => Expanded(child: card))
          .expand((w) => [w, const SizedBox(width: 8)])
          .toList()
        ..removeLast(),
    );
  }
}
