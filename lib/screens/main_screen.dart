import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/price_provider.dart';
import 'pages/btc_overview_page.dart';
import 'pages/mean_reversion_page.dart';
import 'pages/mvrv_page.dart';
import 'pages/pnl_page.dart';
import 'pages/derivatives_page.dart';
import 'pages/etf_overview_page.dart';
import 'pages/stock_page.dart';
import 'pages/mstr_price_page.dart';
import 'pages/mstr_nav_page.dart';
import 'pages/mstr_dilution_page.dart';
import 'pages/preferred_page.dart';

// ── Grid definition ───────────────────────────────────────────────────────────

class _Page {
  final String name;
  final IconData icon;
  final Widget widget;
  const _Page(this.name, this.icon, this.widget);
}

class _Row {
  final String label;
  final Color accent;
  final List<_Page> pages;
  const _Row(this.label, this.accent, this.pages);
}

final _grid = <_Row>[
  _Row('BTC', AppColors.btcOrange, [
    const _Page('Overview',   Icons.show_chart_rounded,         BtcOverviewPage()),
    const _Page('Mean Rev.',  Icons.timeline_rounded,           MeanReversionPage()),
    const _Page('MVRV',       Icons.compare_arrows_rounded,     MvrvPage()),
    const _Page('P&L',        Icons.waterfall_chart_rounded,    PnlPage()),
    const _Page('Derivatives',Icons.candlestick_chart_outlined, DerivativesPage()),
  ]),
  _Row('ETFs', const Color(0xFF4488FF), [
    const _Page('All ETFs', Icons.account_balance_outlined,     EtfOverviewPage()),
    const _Page('IBIT',  Icons.show_chart_rounded, StockPage(ticker: 'IBIT',  displayName: 'iShares Bitcoin Trust',      accentColor: Color(0xFF00D4AA))),
    const _Page('FBTC',  Icons.show_chart_rounded, StockPage(ticker: 'FBTC',  displayName: 'Fidelity Wise Origin',       accentColor: Color(0xFF6B8EFF))),
    const _Page('ARKB',  Icons.show_chart_rounded, StockPage(ticker: 'ARKB',  displayName: 'ARK 21Shares Bitcoin',      accentColor: Color(0xFFFF8C00))),
    const _Page('BITB',  Icons.show_chart_rounded, StockPage(ticker: 'BITB',  displayName: 'Bitwise Bitcoin',           accentColor: Color(0xFFFFD700))),
    const _Page('GBTC',  Icons.show_chart_rounded, StockPage(ticker: 'GBTC',  displayName: 'Grayscale Bitcoin Trust',   accentColor: Color(0xFFFF4444))),
    const _Page('HODL',  Icons.show_chart_rounded, StockPage(ticker: 'HODL',  displayName: 'VanEck Bitcoin',            accentColor: Color(0xFF00BFFF))),
  ]),
  _Row('MSTR', const Color(0xFFFF6B35), [
    const _Page('Price',    Icons.show_chart_rounded,           MstrPricePage()),
    const _Page('NAV',      Icons.account_balance_wallet_outlined, MstrNavPage()),
    const _Page('Dilution', Icons.people_outline_rounded,       MstrDilutionPage()),
  ]),
  _Row('Preferreds', const Color(0xFF9B59B6), [
    const _Page('STRK', Icons.toll_rounded,
        PreferredPage(ticker: 'STRK', displayName: 'Strategy Series A Strike',
            parValue: 1000.0, dividendRate: 0.08)),
    const _Page('STRF', Icons.toll_rounded,
        PreferredPage(ticker: 'STRF', displayName: 'Strategy Series A Strife',
            parValue: 1000.0, dividendRate: 0.10)),
  ]),
];

// ── Main screen ───────────────────────────────────────────────────────────────

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late final PageController _rowController;
  late final List<PageController> _colControllers;
  int _currentRow = 0;
  late final List<int> _currentCol;

  @override
  void initState() {
    super.initState();
    _rowController = PageController();
    _colControllers = List.generate(_grid.length, (_) => PageController());
    _currentCol = List.filled(_grid.length, 0);
  }

  @override
  void dispose() {
    _rowController.dispose();
    for (final c in _colControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = _grid[_currentRow];
    final col = _currentCol[_currentRow];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [

        // ── Top bar ───────────────────────────────────────────────────────
        _TopBar(
          row: row,
          col: col,
          onColTap: (i) => _colControllers[_currentRow].animateToPage(i,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut),
        ),

        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: Row(children: [

            // Row indicator dots (left edge)
            _RowDots(
              rows: _grid,
              current: _currentRow,
              onTap: (i) => _rowController.animateToPage(i,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOut),
            ),

            // Vertical PageView (rows)
            Expanded(
              child: PageView.builder(
                controller: _rowController,
                scrollDirection: Axis.vertical,
                itemCount: _grid.length,
                onPageChanged: (i) => setState(() => _currentRow = i),
                itemBuilder: (context, ri) {
                  // Horizontal PageView (columns)
                  return PageView.builder(
                    controller: _colControllers[ri],
                    itemCount: _grid[ri].pages.length,
                    onPageChanged: (ci) =>
                        setState(() => _currentCol[ri] = ci),
                    itemBuilder: (context, ci) =>
                        _grid[ri].pages[ci].widget,
                  );
                },
              ),
            ),
          ]),
        ),

        // ── Column indicator dots (bottom) ────────────────────────────────
        _ColDots(
          count: row.pages.length,
          current: col,
          color: row.accent,
        ),

        const SizedBox(height: 6),
      ]),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final _Row row;
  final int col;
  final void Function(int) onColTap;

  const _TopBar({
    required this.row,
    required this.col,
    required this.onColTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceState   = ref.watch(priceStateProvider);
    final priceHistory = ref.watch(priceHistoryProvider);
    final price  = priceState.vwap;
    // 24h change from last two daily closes
    final change = priceHistory.length >= 2
        ? (price - priceHistory[priceHistory.length - 2].price) /
          priceHistory[priceHistory.length - 2].price * 100
        : 0.0;
    final changeColor =
        change >= 0 ? AppColors.positive : AppColors.negative;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 16,
        right: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(children: [
        // Logo
        Image.asset('assets/clarionchain_logo.png',
            width: 24, height: 24),
        const SizedBox(width: 8),

        // Row label
        Text(row.label,
            style: TextStyle(
                color: row.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2)),

        const SizedBox(width: 6),

        // Page name
        Text(row.pages[col].name,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500)),

        const Spacer(),

        // Live BTC price (always shown)
        if (price > 0) ...[
          Text(_fmtPrice(price),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(width: 6),
          Text('${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: changeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
        ],

        // Page icon tabs
        ...List.generate(row.pages.length, (i) {
          final active = i == col;
          return GestureDetector(
            onTap: () => onColTap(i),
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: active
                    ? row.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(row.pages[i].icon,
                  size: 18,
                  color: active ? row.accent : AppColors.textMuted),
            ),
          );
        }),
      ]),
    );
  }

  String _fmtPrice(double p) {
    if (p >= 100000) return '\$${(p / 1000).toStringAsFixed(0)}K';
    if (p >= 10000)  return '\$${(p / 1000).toStringAsFixed(1)}K';
    return '\$${p.toStringAsFixed(0)}';
  }
}

// ── Row dots (left) ───────────────────────────────────────────────────────────

class _RowDots extends StatelessWidget {
  final List<_Row> rows;
  final int current;
  final void Function(int) onTap;

  const _RowDots(
      {required this.rows, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(rows.length, (i) {
          final active = i == current;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 8 : 5,
                height: active ? 8 : 5,
                decoration: BoxDecoration(
                  color: active
                      ? rows[i].accent
                      : AppColors.textMuted.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Column dots (bottom) ──────────────────────────────────────────────────────

class _ColDots extends StatelessWidget {
  final int count;
  final int current;
  final Color color;

  const _ColDots(
      {required this.count, required this.current, required this.color});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 18 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: active
                  ? color
                  : AppColors.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
