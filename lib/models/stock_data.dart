class StockBar {
  final DateTime timestamp;
  final double close;
  final double volume;
  const StockBar({required this.timestamp, required this.close, required this.volume});
}

class StockQuote {
  final String ticker;
  final String name;
  final double price;
  final double previousClose;
  final double fiftyTwoWeekHigh;
  final double fiftyTwoWeekLow;
  final List<StockBar> history;

  const StockQuote({
    required this.ticker,
    required this.name,
    required this.price,
    required this.previousClose,
    required this.fiftyTwoWeekHigh,
    required this.fiftyTwoWeekLow,
    required this.history,
  });

  double get changePct =>
      previousClose > 0 ? (price - previousClose) / previousClose : 0;
  double get changeDollar => price - previousClose;
}
