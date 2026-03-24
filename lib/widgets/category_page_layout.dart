import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Standard page shell: compact header, chart and stats each take half of remaining height.
class CategoryPageLayout extends StatelessWidget {
  final Widget header;
  final Widget chart;
  final Widget stats;

  const CategoryPageLayout({
    super.key,
    required this.header,
    required this.chart,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          Expanded(child: chart),
          const SizedBox(height: 8),
          Expanded(child: stats),
        ],
      ),
    );
  }
}

/// Minimal section header — category + page title. No duplicate global metrics (e.g. BTC spot).
class CategoryPageHeader extends StatelessWidget {
  final String category;
  final String title;
  final Color accentColor;
  /// Optional one line (e.g. primary metric for this screen only).
  final String? subtitle;
  final String? trailingHint;

  const CategoryPageHeader({
    super.key,
    required this.category,
    required this.title,
    required this.accentColor,
    this.subtitle,
    this.trailingHint,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: subtitle != null || trailingHint != null ? 48 : 36,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                category.toUpperCase(),
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
              if (trailingHint != null) ...[
                const Spacer(),
                Text(
                  trailingHint!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
