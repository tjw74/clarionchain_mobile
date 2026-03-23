import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/stock_provider.dart';
import '../../theme/app_theme.dart';

final _fmt = NumberFormat('#,##0.00', 'en_US');

const _etfs = [
  (ticker: 'IBIT', name: 'iShares Bitcoin Trust', color: Color(0xFF00D4AA)),
  (ticker: 'FBTC', name: 'Fidelity Wise Origin Bitcoin', color: Color(0xFF6B8EFF)),
  (ticker: 'ARKB', name: 'ARK 21Shares Bitcoin ETF', color: Color(0xFFFF8C00)),
  (ticker: 'BITB', name: 'Bitwise Bitcoin ETF', color: Color(0xFFFFD700)),
  (ticker: 'GBTC', name: 'Grayscale Bitcoin Trust', color: Color(0xFFFF4444)),
  (ticker: 'HODL', name: 'VanEck Bitcoin ETF', color: Color(0xFF00BFFF)),
];

class EtfPage extends ConsumerWidget {
  const EtfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.account_balance_outlined,
              color: AppColors.btcOrange, size: 20),
          const SizedBox(width: 8),
          const Text('BTC SPOT ETFs',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          const Spacer(),
          const Text('Yahoo Finance',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _etfs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final etf = _etfs[i];
              return _EtfTile(
                ticker: etf.ticker,
                name: etf.name,
                color: etf.color,
                quoteAsync: ref.watch(stockQuoteProvider(etf.ticker)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

class _EtfTile extends StatelessWidget {
  final String ticker;
  final String name;
  final Color color;
  final AsyncValue quoteAsync;

  const _EtfTile({
    required this.ticker,
    required this.name,
    required this.color,
    required this.quoteAsync,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: quoteAsync.when(
        loading: () => Row(children: [
          _dot(color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ticker,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(name,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10)),
            ]),
          ),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: AppColors.textMuted, strokeWidth: 1.5),
          ),
        ]),
        error: (_, __) => Row(children: [
          _dot(AppColors.textMuted),
          const SizedBox(width: 12),
          Text(ticker,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(width: 8),
          const Text('Unavailable',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
        data: (quote) {
          if (quote == null) {
            return Row(children: [
              _dot(AppColors.textMuted),
              const SizedBox(width: 12),
              Text(ticker,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            ]);
          }
          final changeColor =
              quote.changePct >= 0 ? AppColors.positive : AppColors.negative;
          return Row(children: [
            _dot(color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticker,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(name,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${_fmt.format(quote.price)}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text(
                '${quote.changePct >= 0 ? '+' : ''}${(quote.changePct * 100).toStringAsFixed(2)}%',
                style: TextStyle(
                    color: changeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ]);
        },
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
