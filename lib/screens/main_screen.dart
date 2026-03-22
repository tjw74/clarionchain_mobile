import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/page_indicator.dart';
import 'pages/price_page.dart';
import 'pages/market_page.dart';
import 'pages/mining_page.dart';
import 'pages/mempool_page.dart';
import 'pages/sentiment_page.dart';

const _pages = [
  (title: 'Price', icon: Icons.show_chart_rounded, widget: PricePage()),
  (title: 'Market', icon: Icons.pie_chart_outline_rounded, widget: MarketPage()),
  (title: 'Mining', icon: Icons.memory_rounded, widget: MiningPage()),
  (title: 'Mempool', icon: Icons.inbox_rounded, widget: MempoolPage()),
  (title: 'Sentiment', icon: Icons.psychology_rounded, widget: SentimentPage()),
];

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top nav bar
          _TopBar(
            currentPage: _currentPage,
            onPageTap: (i) {
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: _pages.map((p) => p.widget).toList(),
            ),
          ),

          // Page indicator
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: PageIndicator(
              count: _pages.length,
              current: _currentPage,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int currentPage;
  final void Function(int) onPageTap;

  const _TopBar({required this.currentPage, required this.onPageTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 0,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo / name
          Row(
            children: [
              Image.asset(
                'assets/clarionchain_logo.png',
                width: 28,
                height: 28,
              ),
              const SizedBox(width: 8),
              const Text(
                'ClarionChain',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Tab icons
          ...List.generate(_pages.length, (i) {
            final isActive = i == currentPage;
            return GestureDetector(
              onTap: () => onPageTap(i),
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.btcOrange.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _pages[i].icon,
                  size: 20,
                  color: isActive
                      ? AppColors.btcOrange
                      : AppColors.textMuted,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
