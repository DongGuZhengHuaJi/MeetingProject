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

  factory WebsocketMgr() {
    return _instance;
  }

  static const Duration _heartbeatInterval = Duration(seconds: 15);
  static const Duration _heartbeatTimeout = Duration(seconds: 35);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);
  static const int _maxReconnectAttempts = 10;

  final Connectivity _connectivity = Connectivity();

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsEventSub;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  String? _url;
  bool _isManuallyClosed = false;
  bool _isDisposed = false;
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

  Future<void> connect(
    String url,{
    void Function()? onConnected,
    void Function()? onClosed,
    void Function(dynamic error)? onError,
  }) async {
    if (_isDisposed) {
      throw StateError("WebSocket manager is disposed");
    }

    _url = url;
    _isManuallyClosed = false;
    _reconnectAttempts = 0;
    _onConnected = onConnected;
    _onClosed = onClosed;
    _onError = onError;

    await _startConnectivityListener();
    await _performConnect();
  }

  bool send(String message) {
    if (_ws != null && _connectionState == WsConnectionState.connected) {
      try {
        _ws!.sendText(message);
        return true;
      } catch (e) {
        logger.e("Failed to send message: $e");
        return false;
      }
    } else {
      logger.w("Cannot send message, WebSocket is not connected");
      return false;
    }
  }

  Future<void> close() async {
    if(_isManuallyClosed || _connectionState == WsConnectionState.disconnected) {
      return;
    }
    _isManuallyClosed = true;

    _reconnectTimer?.cancel();
    await _cleanupSocket();
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    _setState(WsConnectionState.disconnected);
    _onClosed?.call();
  }

  void reconnect() {
    if (_isManuallyClosed || _isDisposed || _connectionState == WsConnectionState.connected) {
      return;
    }

    logger.i("Manually triggering reconnect");
    _scheduleReconnect(reason: "external_request");
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _reconnectTimer?.cancel();
    await _cleanupSocket();
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_connectionStateController.isClosed) {
    _connectionStateController.close();
    }
  }

  void _setState(WsConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(newState);
    }
  }

  Future<void> _performConnect() async {
    if (_isDisposed || _isManuallyClosed || _url == null) {
      return;
    }

    await _cleanupSocket();

    final epoch = ++_connectEpoch;
    _setState(_reconnectAttempts > 0 
    ?WsConnectionState.reconnecting
    : WsConnectionState.connecting);

    try {
      logger.i("Attempting to connect to WebSocket: $_url (attempt $_reconnectAttempts)");
      // final socket = await WebSocket.connect(Uri.parse(_url!));
      late WebSocket socket;
      try {
        socket = await WebSocket.connect(Uri.parse(_url!)).timeout(Duration(seconds: 10));
      } on TimeoutException catch (e) {
        logger.e("WebSocket connection timed out: $e");
        _onError?.call(e);
        _scheduleReconnect(reason: "connection_timeout");
        return;
      }

      if (_connectEpoch != epoch || _isManuallyClosed || _isDisposed) {
        logger.w("Connection attempt is outdated, closing new socket");
        await _safeCloseSocket(socket);
        return;
      }

      _ws = socket;
      _reconnectAttempts = 0;
      _lastHeartbeatTime = DateTime.now();
      _setState(WsConnectionState.connected);
      logger.i("WebSocket connected");

      _startHeartbeat();
      _onConnected?.call();

      _wsEventSub = _ws!.events.listen(
        (event){
          if (!identical(_ws, socket) || _isDisposed || _isManuallyClosed) {
            logger.w("Received event for outdated socket, ignoring");
            return;
          }

          if (event is TextDataReceived) {
            _handleTextMessage(event.text);
          }
          else if (event is BinaryDataReceived) {
            logger.w("Binary message received but not supported, ignoring");
          }
        },
        onError: (error) {
          if (!identical(_ws, socket) || _isDisposed || _isManuallyClosed) {
            logger.w("Received error for outdated socket, ignoring");
            return;
          }

          logger.e("WebSocket error: $error");
          _onError?.call(error);
          _scheduleReconnect(reason: "socket_error");
        },
        onDone: () {
          if (!identical(_ws, socket) || _isDisposed || _isManuallyClosed) {
            logger.w("Received done event for outdated socket, ignoring");
            return;
          }

          logger.i("WebSocket connection closed by server");
          _scheduleReconnect(reason: "socket_closed");
        }
      );
    }on SocketException catch (e) {
      logger.e("WebSocket connection failed: $e");
      _onError?.call(e);
      _scheduleReconnect(reason: "socket_exception");
    } on TimeoutException catch (e) {
      logger.e("WebSocket connection timed out: $e");
      _onError?.call(e);
      _scheduleReconnect(reason: "connection_timeout");
    } catch (e) {
      logger.e("Unexpected error during WebSocket connection: $e");
      _onError?.call(e);
      _scheduleReconnect(reason: "unexpected_error");
    }
  }

  void _handleTextMessage(String message) {
    // Any inbound frame proves the transport is alive.
    _lastHeartbeatTime = DateTime.now();

    if (message == "pong" || message.contains('"type":"pong"')) {
      _cleanupHeartbeatTimeout();
      return;
    }

    if (message == "ping" || message.contains('"type":"ping"')) {
      try {
        _ws?.sendText(jsonEncode({"type": "pong"}));
      } catch (e) {
        logger.w("Failed to reply pong: $e");
      }
      return;
    }

    if (!_messageController.isClosed) {
    _messageController.add(message);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_ws != null && _connectionState == WsConnectionState.connected) {
        try {
          _ws!.sendText(jsonEncode({"type": "ping"}));

          _heartbeatTimeoutTimer?.cancel();
          _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
            final lastTime = _lastHeartbeatTime;
            if (lastTime == null || DateTime.now().difference(lastTime) >= _heartbeatTimeout) {
              logger.w("Heartbeat timeout, no response from server");
              _scheduleReconnect(reason: "heartbeat_timeout");
            }
          });
        } catch (e) {
          logger.e("Error sending heartbeat: $e");
          _scheduleReconnect(reason: "heartbeat_error");
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cleanupHeartbeatTimeout();
  }

  void _cleanupHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  Future<void> _startConnectivityListener() async {
    await _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((dynamic results) { 
      logger.i("Connectivity changed: $results");
      final hasNetwork =
          results is List<ConnectivityResult>
              ? results.any((r) => r != ConnectivityResult.none)
              : results != ConnectivityResult.none;

      if (!hasNetwork) {
        logger.w("Connectivity lost, stop reconnect attempts until network recovers");
        _reconnectTimer?.cancel();
        unawaited(_cleanupSocket());
        _setState(WsConnectionState.disconnected);
        return;
      }

      if ((_connectionState == WsConnectionState.disconnected ||
              _connectionState == WsConnectionState.reconnecting) &&
          !_isManuallyClosed &&
          !_isDisposed) {
        logger.i("Connectivity recovered, scheduling reconnect");
        _scheduleReconnect(reason: "connectivity_recovered");
      }
    });
  }

  void _scheduleReconnect({required String reason}) {
    if (_isManuallyClosed || _isDisposed) {
      return;
    }

    unawaited(_cleanupSocket());
    _setState(WsConnectionState.reconnecting);

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      logger.e("Max reconnect attempts reached, giving up");
      _setState(WsConnectionState.disconnected);
      _onClosed?.call();
      return;
    }

    _reconnectAttempts++;

    final delayMs = min(
      1000 * (1 << min(_reconnectAttempts - 1, 5)), // 1s,2s,4s...最大32s
      _maxReconnectDelay.inMilliseconds,
    );
    final delay = Duration(milliseconds: delayMs);

    logger.i('⏱️ ${delay.inSeconds}s 后第 $_reconnectAttempts 次重连 (原因: $reason)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isManuallyClosed &&
          !_isDisposed &&
          _connectionState != WsConnectionState.connected) {
        _performConnect();
      }
    });
    
  }

  Future<void> _cleanupSocket() async {
    _wsEventSub?.cancel();
    _wsEventSub = null;

    if (_ws != null) {
      await _safeCloseSocket(_ws!);
      _ws = null;
    }

    _stopHeartbeat();
  }

  Future<void> _safeCloseSocket(WebSocket socket) async {
    try {
      await socket.close();
    } catch (e) {
      logger.w("Error while closing WebSocket: $e");
    }
  }

}
