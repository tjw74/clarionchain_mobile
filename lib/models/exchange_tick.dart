class ExchangeTick {
  final String exchange;
  final double price;
  final double volume24h;
  final DateTime timestamp;

  const ExchangeTick({
    required this.exchange,
    required this.price,
    required this.volume24h,
    required this.timestamp,
  });
}

class PriceState {
  final Map<String, ExchangeTick> ticks;

  const PriceState({required this.ticks});

  const PriceState.empty() : ticks = const {};

  double get simpleAverage {
    if (ticks.isEmpty) return 0;
    final sum = ticks.values.fold(0.0, (acc, t) => acc + t.price);
    return sum / ticks.length;
  }

  double get vwap {
    if (ticks.isEmpty) return 0;
    double totalVolume = ticks.values.fold(0.0, (acc, t) => acc + t.volume24h);
    if (totalVolume == 0) return simpleAverage;
    double weightedSum =
        ticks.values.fold(0.0, (acc, t) => acc + (t.price * t.volume24h));
    return weightedSum / totalVolume;
  }

  double get spread => (simpleAverage - vwap).abs();

  double get totalVolume =>
      ticks.values.fold(0.0, (acc, t) => acc + t.volume24h);

  bool get hasData => ticks.isNotEmpty;
}

class PriceTick {
  final double price;
  final DateTime timestamp;

  const PriceTick({required this.price, required this.timestamp});
}
