import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket/web_socket.dart';
import 'package:logger/logger.dart';

final logger = Logger();

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebsocketMgr {
  static final WebsocketMgr _instance = WebsocketMgr._internal();
  WebsocketMgr._internal();
  factory WebsocketMgr() => _instance;

  static const Duration _heartbeatInterval = Duration(seconds: 15);
  static const Duration _heartbeatTimeout = Duration(seconds: 10);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  static const int _maxReconnectAttempts = 10;

  final Connectivity _connectivity = Connectivity();
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsEventSub;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  String? _url;
  bool _isManuallyClosed = false;
  bool _isDisposed = false;
  bool _isConnecting = false; // 💡 独占锁，防止并发连接
  ConnectivityResult _lastConnectivityResult = ConnectivityResult.none;

  int _connectEpoch = 0;
  int _reconnectAttempts = 0;
  WsConnectionState _connectionState = WsConnectionState.disconnected;

  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  DateTime? _lastHeartbeatTime;
  Timer? _reconnectTimer;

  void Function()? _onConnected;
  void Function()? _onClosed;
  void Function(dynamic error)? _onError;

  final StreamController<String> _messageController = StreamController.broadcast();
  final StreamController<WsConnectionState> _connectionStateController = StreamController.broadcast();

  Stream<String> get messages => _messageController.stream;
  Stream<WsConnectionState> get connectionStateStream => _connectionStateController.stream;
  WsConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == WsConnectionState.connected;

  Future<void> connect(String url, {
    void Function()? onConnected,
    void Function()? onClosed,
    void Function(dynamic error)? onError,
  }) async {
    if (_isDisposed) throw StateError("WebSocket manager is disposed");

    _url = url;
    _isManuallyClosed = false;
    _reconnectAttempts = 0;
    _onConnected = onConnected;
    _onClosed = onClosed;
    _onError = onError;

    await _startConnectivityListener();
    _performConnect(); // 开始第一次连接
  }

  void _setState(WsConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(newState);
    }
  }

  Future<void> _performConnect() async {
    // 💡 核心保护：如果正在连接、已手动关闭、或已经连上，则退出
    if (_isConnecting || _isDisposed || _isManuallyClosed || _url == null) return;
    if (_connectionState == WsConnectionState.connected) return;

    _isConnecting = true;
    final epoch = ++_connectEpoch;
    
    _reconnectTimer?.cancel();
    await _cleanupSocket();

    _setState(_reconnectAttempts > 0 ? WsConnectionState.reconnecting : WsConnectionState.connecting);

    try {
      logger.i("Attempting to connect to WebSocket: $_url (epoch: $epoch, attempt: $_reconnectAttempts)");
      
      final socket = await WebSocket.connect(Uri.parse(_url!))
          .timeout(const Duration(seconds: 10));

      if (epoch != _connectEpoch || _isManuallyClosed || _isDisposed) {
        logger.w("Connection attempt $epoch is outdated, closing socket");
        await socket.close();
        return;
      }

      _ws = socket;
      _reconnectAttempts = 0;
      _lastHeartbeatTime = DateTime.now();

      // 💡 先挂载监听
      _wsEventSub = _ws!.events.listen(
        (event) {
          if (event is TextDataReceived) _handleTextMessage(event.text);
        },
        onError: (error) {
          logger.e("WebSocket error: $error");
          _scheduleReconnect(reason: "socket_error");
        },
        onDone: () {
          logger.i("WebSocket connection closed by server");
          _scheduleReconnect(reason: "socket_done");
        },
      );

      _setState(WsConnectionState.connected);
      logger.i("WebSocket connected");

      _startHeartbeat();
      _onConnected?.call();
    } catch (e) {
      logger.e("WebSocket connection failed: $e");
      if (epoch == _connectEpoch) {
        _onError?.call(e);
        _scheduleReconnect(reason: e is TimeoutException ? "connection_timeout" : "connect_failed");
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _handleTextMessage(String message) {
    if (message == "pong" || message.contains('"type":"pong"')) {
      _lastHeartbeatTime = DateTime.now();
      _cleanupHeartbeatTimeout();
      return;
    }
    if (message == "ping" || message.contains('"type":"ping"')) {
      _ws?.sendText(jsonEncode({"type": "pong"}));
      return;
    }
    _messageController.add(message);
  }

  void _scheduleReconnect({required String reason}) {
    if (_isManuallyClosed || _isDisposed) return;
    
    if (_reconnectTimer?.isActive ?? false) return;

    unawaited(_cleanupSocket());
    _setState(WsConnectionState.reconnecting);

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      logger.e("Max reconnect attempts reached");
      _setState(WsConnectionState.disconnected);
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(milliseconds: min(1000 * (1 << min(_reconnectAttempts - 1, 5)), 30000));

    logger.i('⏱️ ${delay.inSeconds}s 后第 $_reconnectAttempts 次重连 (原因: $reason)');
    _reconnectTimer = Timer(delay, _performConnect);
  }

  Future<void> _startConnectivityListener() async {
    await _connectivitySub?.cancel();
    
    // 💡 获取当前网络状态作为初始值，防止 Stream 第一次吐出当前状态时触发重连
    _lastConnectivityResult = await _connectivity.checkConnectivity(); 

    _connectivitySub = _connectivity.onConnectivityChanged.listen((ConnectivityResult result) { 
      logger.i("Connectivity changed: $result");
      
      if (result == _lastConnectivityResult) {
        return;
      }
      _lastConnectivityResult = result;

      final hasNetwork = result != ConnectivityResult.none;

      if (!hasNetwork) {
        logger.w("Connectivity lost, stop reconnect attempts");
        _reconnectTimer?.cancel();
        _setState(WsConnectionState.disconnected);
        return;
      }

      if (_connectionState == WsConnectionState.connected || 
          _connectionState == WsConnectionState.reconnecting) {
        logger.i("Network environment changed, forcing reconnect...");
        _scheduleReconnect(reason: "network_switched");
      }
    });
  }

  bool send(String message) {
    if (_ws != null && _connectionState == WsConnectionState.connected) {
      try {
        _ws!.sendText(message);
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_connectionState == WsConnectionState.connected) {
        _ws?.sendText(jsonEncode({"type": "ping"}));
        _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
          if (DateTime.now().difference(_lastHeartbeatTime!) >= _heartbeatTimeout) {
            logger.w("Heartbeat timeout");
            _scheduleReconnect(reason: "heartbeat_timeout");
          }
        });
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _cleanupHeartbeatTimeout();
  }

  void _cleanupHeartbeatTimeout() => _heartbeatTimeoutTimer?.cancel();

  Future<void> _cleanupSocket() async {
    _wsEventSub?.cancel();
    _wsEventSub = null;
    if (_ws != null) {
      try { await _ws!.close(); } catch (_) {}
      _ws = null;
    }
    _stopHeartbeat();
  }

  Future<void> close() async {
    _isManuallyClosed = true;
    await _cleanupSocket();
    await _connectivitySub?.cancel();
    _setState(WsConnectionState.disconnected);
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await close();
    _messageController.close();
    _connectionStateController.close();
  }
}