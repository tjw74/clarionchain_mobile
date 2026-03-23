import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import 'pages/price_page.dart';
import 'pages/market_page.dart';
import 'pages/pnl_page.dart';
import 'pages/derivatives_page.dart';
import 'pages/etf_page.dart';
import 'pages/overview_page.dart';
import 'pages/stock_page.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class _PageDef {
  final String title;
  final IconData icon;
  final Widget widget;
  const _PageDef(this.title, this.icon, this.widget);
}

class _Category {
  final String label;
  final IconData icon;
  final Color accent;
  final List<_PageDef> pages;
  const _Category(this.label, this.icon, this.accent, this.pages);
}

final _categories = <_Category>[
  _Category('BTC', Icons.currency_bitcoin_rounded, AppColors.btcOrange, [
    const _PageDef('Price',       Icons.show_chart_rounded,          PricePage()),
    const _PageDef('P&L',         Icons.waterfall_chart_rounded,     PnlPage()),
    const _PageDef('Market',      Icons.pie_chart_outline_rounded,   MarketPage()),
    const _PageDef('Derivatives', Icons.candlestick_chart_outlined,  DerivativesPage()),
    const _PageDef('ETFs',        Icons.account_balance_outlined,    EtfPage()),
  ]),
  _Category('Overview', Icons.dashboard_outlined, AppColors.btcOrange, [
    const _PageDef('Overview', Icons.dashboard_outlined, OverviewPage()),
  ]),
  _Category('MSTR', Icons.business_rounded, const Color(0xFFFF6B35), [
    _PageDef('MSTR', Icons.show_chart_rounded,
      const StockPage(ticker: 'MSTR', displayName: 'MicroStrategy',
          accentColor: Color(0xFFFF6B35))),
  ]),
  _Category('STRK', Icons.toll_rounded, const Color(0xFF6B8EFF), [
    _PageDef('STRK', Icons.show_chart_rounded,
      const StockPage(ticker: 'STRK', displayName: 'Strategy Series A Strike',
          accentColor: Color(0xFF6B8EFF))),
  ]),
  _Category('STRF', Icons.toll_rounded, const Color(0xFFFF8C00), [
    _PageDef('STRF', Icons.show_chart_rounded,
      const StockPage(ticker: 'STRF', displayName: 'Strategy Series A Strife',
          accentColor: Color(0xFFFF8C00))),
  ]),
];

// ─── Main screen ─────────────────────────────────────────────────────────────

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late final PageController _categoryController;
  late final List<PageController> _pageControllers;

  int _currentCategory = 0;
  late final List<int> _currentPagePerCategory;

  @override
  void initState() {
    super.initState();
    _categoryController = PageController();
    _pageControllers =
        List.generate(_categories.length, (_) => PageController());
    _currentPagePerCategory = List.filled(_categories.length, 0);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    for (final c in _pageControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _goToCategory(int i) {
    _categoryController.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _goToPage(int i) {
    _pageControllers[_currentCategory].animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _categories[_currentCategory];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        // ── Top bar ──────────────────────────────────────────────────────────
        _TopBar(
          category: cat,
          currentPage: _currentPagePerCategory[_currentCategory],
          onPageTap: _goToPage,
        ),

        // ── Content area ─────────────────────────────────────────────────────
        Expanded(
          child: Row(children: [
            // Category indicator (vertical dots on left)
            _CategoryDots(
              categories: _categories,
              current: _currentCategory,
              onTap: _goToCategory,
            ),

            // Outer vertical PageView (categories)
            Expanded(
              child: PageView.builder(
                controller: _categoryController,
                scrollDirection: Axis.vertical,
                itemCount: _categories.length,
                onPageChanged: (i) =>
                    setState(() => _currentCategory = i),
                itemBuilder: (context, catIdx) {
                  final c = _categories[catIdx];

                  // Inner horizontal PageView (pages within category)
                  return PageView.builder(
                    controller: _pageControllers[catIdx],
                    itemCount: c.pages.length,
                    onPageChanged: (pi) => setState(
                        () => _currentPagePerCategory[catIdx] = pi),
                    itemBuilder: (context, pageIdx) =>
                        c.pages[pageIdx].widget,
                  );
                },
              ),
            ),
          ]),
        ),

        // ── Page indicator (dots) ────────────────────────────────────────────
        if (cat.pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: _PageDots(
              count: cat.pages.length,
              current: _currentPagePerCategory[_currentCategory],
              color: cat.accent,
            ),
          )
        else
          const SizedBox(height: 14),
      ]),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final _Category category;
  final int currentPage;
  final void Function(int) onPageTap;

  const _TopBar({
    required this.category,
    required this.currentPage,
    required this.onPageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 16,
        right: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(children: [
        // Logo
        Image.asset('assets/clarionchain_logo.png', width: 26, height: 26),
        const SizedBox(width: 8),
        // Category label
        Text(
          category.label,
          style: TextStyle(
            color: category.accent,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),

        const Spacer(),

        // Page icon tabs
        ...List.generate(category.pages.length, (i) {
          final isActive = i == currentPage;
          return GestureDetector(
            onTap: () => onPageTap(i),
            child: Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isActive
                    ? category.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                category.pages[i].icon,
                size: 19,
                color: isActive ? category.accent : AppColors.textMuted,
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ─── Category dots (left side) ───────────────────────────────────────────────

class _CategoryDots extends StatelessWidget {
  final List<_Category> categories;
  final int current;
  final void Function(int) onTap;

  const _CategoryDots({
    required this.categories,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(categories.length, (i) {
          final isActive = i == current;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isActive ? 8 : 5,
                height: isActive ? 8 : 5,
                decoration: BoxDecoration(
                  color: isActive
                      ? categories[i].accent
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

// ─── Page dots (bottom) ──────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int count;
  final int current;
  final Color color;

  const _PageDots({
    required this.count,
    required this.current,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 16 : 5,
          height: 5,
          decoration: BoxDecoration(
            color: isActive
                ? color
                : AppColors.textMuted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
