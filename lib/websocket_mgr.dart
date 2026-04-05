import 'dart:async';

import 'package:web_socket/web_socket.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class WebsocketMgr {
  static final WebsocketMgr _instance = WebsocketMgr._internal();

  factory WebsocketMgr() {
    return _instance;
  }

  WebsocketMgr._internal();

  WebSocket? _ws;

  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  Future<void> connect(String url) async {
    try {
      
      await _ws?.close(); // 先关闭已有连接

      _ws = await WebSocket.connect(Uri.parse(url));
      logger.i('WebSocket connected to $url');

      _ws!.events.listen((event) {
        if (event is TextDataReceived) {
          logger.i('Message received: ${event.text}');
          _messageController.add(event.text);
        }
      }, onError: (error) {
        logger.e('WebSocket error: $error');
        // todo:后期补全错误处理逻辑，比如重试连接等
      }, onDone: () {
        logger.w('WebSocket connection closed');
        // todo:后期补全连接关闭处理逻辑，比如自动重连等
      });
    } catch (e) {
      logger.e('Failed to connect to WebSocket: $e');
    }
  }
  
  void send(String message) {
    try{
      if (_ws == null) {
        throw Exception('WebSocket is not connected');
      }
      _ws!.sendText(message);
      logger.i('Message sent: $message');
    } catch (e) {
      logger.e('Error sending message: $e');
      return;
    }
  }



  void close() {
    try {
      if (_ws != null) {
        _ws!.close();
        logger.i('WebSocket connection closed');
      }
    } catch (e) {
      logger.e('Error closing WebSocket: $e');
    }
  }


}