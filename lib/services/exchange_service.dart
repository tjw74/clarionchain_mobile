import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/exchange_tick.dart';

class _ExchangeConfig {
  final String name;
  final String url;
  final Map<String, dynamic>? subscribeMessage;

  const _ExchangeConfig({
    required this.name,
    required this.url,
    this.subscribeMessage,
  });
}

const _exchanges = [
  _ExchangeConfig(
    name: 'Binance',
    url: 'wss://stream.binance.com:9443/ws/btcusdt@ticker',
  ),
  _ExchangeConfig(
    name: 'Coinbase',
    url: 'wss://advanced-trade-ws.coinbase.com',
    subscribeMessage: {
      'type': 'subscribe',
      'product_ids': ['BTC-USD'],
      'channel': 'ticker',
    },
  ),
  _ExchangeConfig(
    name: 'Bybit',
    url: 'wss://stream.bybit.com/v5/public/spot',
    subscribeMessage: {
      'op': 'subscribe',
      'args': ['tickers.BTCUSDT'],
    },
  ),
  _ExchangeConfig(
    name: 'OKX',
    url: 'wss://ws.okx.com:8443/ws/v5/public',
    subscribeMessage: {
      'op': 'subscribe',
      'args': [
        {'channel': 'tickers', 'instId': 'BTC-USDT'},
      ],
    },
  ),
  _ExchangeConfig(
    name: 'Kraken',
    url: 'wss://ws.kraken.com/v2',
    subscribeMessage: {
      'method': 'subscribe',
      'params': {
        'channel': 'ticker',
        'symbol': ['BTC/USD'],
      },
    },
  ),
];

class ExchangeService {
  final _controller = StreamController<ExchangeTick>.broadcast();
  final _connections = <String, WebSocketChannel>{};
  final _reconnectTimers = <String, Timer>{};
  bool _disposed = false;

  Stream<ExchangeTick> get ticks => _controller.stream;

  ExchangeService() {
    for (final config in _exchanges) {
      _connect(config);
    }
  }

  void _connect(_ExchangeConfig config) {
    if (_disposed) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(config.url));
      _connections[config.name] = channel;

      if (config.subscribeMessage != null) {
        channel.sink.add(jsonEncode(config.subscribeMessage));
      }

      channel.stream.listen(
        (message) => _handleMessage(config.name, message),
        onError: (_) => _scheduleReconnect(config),
        onDone: () => _scheduleReconnect(config),
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect(config);
    }
  }

  void _scheduleReconnect(_ExchangeConfig config) {
    if (_disposed) return;
    _reconnectTimers[config.name]?.cancel();
    _reconnectTimers[config.name] =
        Timer(const Duration(seconds: 5), () => _connect(config));
  }

  void _handleMessage(String exchange, dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final tick = _parse(exchange, data);
      if (tick != null) _controller.add(tick);
    } catch (_) {}
  }

  ExchangeTick? _parse(String exchange, Map<String, dynamic> data) {
    try {
      switch (exchange) {
        case 'Binance':
          if (data['e'] != '24hrTicker') return null;
          return ExchangeTick(
            exchange: exchange,
            price: double.parse(data['c'] as String),
            volume24h: double.parse(data['v'] as String),
            timestamp: DateTime.now(),
          );

        case 'Coinbase':
          final events = data['events'] as List?;
          if (events == null || events.isEmpty) return null;
          final event = events.first as Map<String, dynamic>;
          final tickers = event['tickers'] as List?;
          if (tickers == null || tickers.isEmpty) return null;
          final ticker = tickers.first as Map<String, dynamic>;
          final price = double.tryParse(ticker['price'] as String? ?? '');
          final vol = double.tryParse(ticker['volume_24_h'] as String? ?? '');
          if (price == null || vol == null) return null;
          return ExchangeTick(
            exchange: exchange,
            price: price,
            volume24h: vol,
            timestamp: DateTime.now(),
          );

        case 'Bybit':
          final topicData = data['data'] as Map<String, dynamic>?;
          if (topicData == null) return null;
          final price = double.tryParse(topicData['lastPrice'] as String? ?? '');
          final vol = double.tryParse(topicData['volume24h'] as String? ?? '');
          if (price == null || vol == null) return null;
          return ExchangeTick(
            exchange: exchange,
            price: price,
            volume24h: vol,
            timestamp: DateTime.now(),
          );

        case 'OKX':
          final dataList = data['data'] as List?;
          if (dataList == null || dataList.isEmpty) return null;
          final item = dataList.first as Map<String, dynamic>;
          final price = double.tryParse(item['last'] as String? ?? '');
          final vol = double.tryParse(item['vol24h'] as String? ?? '');
          if (price == null || vol == null) return null;
          return ExchangeTick(
            exchange: exchange,
            price: price,
            volume24h: vol,
            timestamp: DateTime.now(),
          );

        case 'Kraken':
          if (data['channel'] != 'ticker') return null;
          final dataList = data['data'] as List?;
          if (dataList == null || dataList.isEmpty) return null;
          final item = dataList.first as Map<String, dynamic>;
          final price = (item['last'] as num?)?.toDouble();
          final vol = (item['volume'] as num?)?.toDouble();
          if (price == null || vol == null) return null;
          return ExchangeTick(
            exchange: exchange,
            price: price,
            volume24h: vol,
            timestamp: DateTime.now(),
          );
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _disposed = true;
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    for (final channel in _connections.values) {
      channel.sink.close();
    }
    _controller.close();
  }
}
