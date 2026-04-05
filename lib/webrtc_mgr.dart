import 'dart:async';
import 'dart:convert';
import 'package:change_notifier/change_notifier.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'websocket_mgr.dart';

class WebRTCManager extends ChangeNotifier {
  static final WebRTCManager _instance = WebRTCManager._internal();

  factory WebRTCManager() {
    return _instance;
  }

  WebRTCManager._internal();

  final ws = WebsocketMgr();
  String _selfId = '';
  String _currentRoomId = '';
  bool _isSignalingInitialized = false;
  StreamSubscription<String>? _wsSubscription;

  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  webrtc.MediaStream? _localStream;

  final Map<String, webrtc.RTCPeerConnection> _peerConnections = {};
  final Map<String, webrtc.RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<webrtc.RTCIceCandidate>> _iceCandidatesBuffer = {};

  Map<String, webrtc.RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  webrtc.RTCVideoRenderer get localRenderer => _localRenderer;
  String get selfId => _selfId;



  Future<void> initSignaling(String selfId, String signalingUrl) async {
    if (_isSignalingInitialized) return;
    _selfId = selfId;
    
    await ws.connect(signalingUrl);
    
    // 监听 WebSocket 消息（全局只监听一次）
    _wsSubscription = ws.messages.listen((message) {
      final data = jsonDecode(message);
      _handleSignalingMessage(data);
    });

    // 连接成功后，立刻注册身份
    ws.send(jsonEncode({
      'type': 'register',
      'session_id': _selfId,
    }));

    _isSignalingInitialized = true;
    logger.i("全局信令通道初始化完成，当前用户ID: $_selfId");
  }

  void _handleSignalingMessage(Map<String, dynamic> data) {
    final type = data['type'];
    final fromId = (data['from'] ?? data['session_id'])?.toString();

    switch (type) {
      case 'register_success':
        logger.i('注册成功！');
        break;
      case 'user_joined': // 有人进房，我主动呼叫
        if (fromId != null && fromId != _selfId) {
          logger.i('发现新人 $fromId，发起呼叫');
          _makeCall(fromId); 
        }
        break;
      case 'offer':
        if (fromId != null) handleOffer(fromId, data['sdp']);
        break;
      case 'answer':
        if (fromId != null) handleAnswer(fromId, data['sdp']);
        break;
      case 'candidate':
        if (fromId != null) handleCandidate(fromId, data['candidate']);
        break;
      case 'leave':
        if (fromId != null) handleLeave(fromId);
        break;
      case 'error':
        logger.e('服务器报错: ${data['message']}');
        break;
      // ... 其他处理 ...
    }
    notifyListeners();
  }

  Future<void> startMeeting({required String roomId, bool isCreate = false}) async {
    // 1. 初始化本地摄像头和麦克风
    await _localRenderer.initialize();
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    _localRenderer.srcObject = _localStream;
    notifyListeners();

    // 2. 发送进房或建房指令 (直接使用已经连接好的 ws)
    _currentRoomId = roomId;
    ws.send(jsonEncode({
      'type': isCreate ? 'create' : 'join',
      'room': roomId,
    }));
  }

  Future<void> leaveCurrentRoom() async {
    // 1. 告诉服务器我要退房了
    if (_currentRoomId.isNotEmpty) {
      ws.send(jsonEncode({'type': 'leave', 'room': _currentRoomId}));
      _currentRoomId = '';
    }

    // 2. 清理所有连线和远程渲染器
    for (final pc in _peerConnections.values) { await pc.close(); }
    _peerConnections.clear();
    for (final renderer in _remoteRenderers.values) { await renderer.dispose(); }
    _remoteRenderers.clear();
    
    // 3. 关闭本地摄像头！但不关闭 WebSocket
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    _localRenderer.srcObject = null;

    notifyListeners();
  }


void toggleAudio(bool isEnabled) {
  _localStream?.getAudioTracks().forEach((track) => track.enabled = isEnabled);
  notifyListeners();
}

void toggleVideo(bool isEnabled) {
  _localStream?.getVideoTracks().forEach((track) => track.enabled = isEnabled);
  notifyListeners();
}

  Future<webrtc.RTCPeerConnection> createPeerConnection(String peerId) async {
    if (_peerConnections.containsKey(peerId)) {
      return _peerConnections[peerId]!; // 已经存在连接
    }

    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    final pc = await webrtc.createPeerConnection(config);


    pc.onIceCandidate = (candidate) {
    // candidate 包含了具体的 IP、端口和协议类型等信息，必须发送给对方才能建立连接
    ws.send(jsonEncode({
      'type': 'candidate',
      'from': _selfId,
      'to': peerId,
      'candidate': candidate.toMap(), // 必须转成 Map 才能发 JSON
    }));
  };

  pc.onTrack = (event) async {
    logger.i('收到远端轨道: ${event.track.kind}'); // 加上这句日志，定位起来非常直观

    if (!_remoteRenderers.containsKey(peerId)) {
      final renderer = webrtc.RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderers[peerId] = renderer;
    }

    final renderer = _remoteRenderers[peerId]!;

    // 不要限制 srcObject == null，每次收到新 track 都需要处理
    if (event.streams.isNotEmpty) {
      renderer.srcObject = event.streams.first;
    } else {
      if (renderer.srcObject == null) {
        final remoteStream = await webrtc.createLocalMediaStream('remote_$peerId');
        renderer.srcObject = remoteStream;
      }
      renderer.srcObject!.addTrack(event.track);
    }

    // 必须通知 UI 刷新，否则画面出不来
    Future.microtask(() => notifyListeners());
  };

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        pc.addTrack(track, _localStream!);
      }
    }

    // notifyListeners(); // 通知 UI 更新
    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _makeCall(String peerId) async {
    final pc = await createPeerConnection(peerId);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    ws.send(JsonEncoder().convert({
      'type': 'offer',
      'from': _selfId,
      'to': peerId,
      'sdp': offer.sdp,
    }));
  }

  Future<void> handleCandidate(String peerId, Map<String, dynamic> candidateMap) async {
    final pc = _peerConnections[peerId];
    final candidate = webrtc.RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );
    

    if(pc != null && await pc.getRemoteDescription() != null) {
      await pc.addCandidate(candidate);
    } else {
      // 连接还未建立，先缓存 ICE 候选，等连接建立后再添加
      _iceCandidatesBuffer.putIfAbsent(peerId, () => []).add(candidate);
    }
  }
  

  Future<void> handleOffer(String peerId, String sdp) async {
    final pc = await createPeerConnection(peerId);

    await pc.setRemoteDescription(webrtc.RTCSessionDescription(sdp, 'offer'));

    await _processBufferedCandidates(peerId);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    ws.send(JsonEncoder().convert({
      'type': 'answer',
      'from': _selfId,
      'to': peerId,
      'sdp': answer.sdp,
    }));
  }

  Future<void> handleAnswer(String peerId, String sdp) async {
    final pc = await createPeerConnection(peerId);
    await pc.setRemoteDescription(webrtc.RTCSessionDescription(sdp, 'answer'));
    await _processBufferedCandidates(peerId);
  }

  Future<void> handleLeave(String peerId) async {
    // 1. 关闭连接
    _peerConnections[peerId]?.close();
    _peerConnections.remove(peerId);

    // 2. 销毁渲染器
    final renderer = _remoteRenderers.remove(peerId);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }

    _iceCandidatesBuffer.remove(peerId);

    // 3. 通知 UI 刷新，减少画面坑位！
    notifyListeners();
  }

  Future<void> _processBufferedCandidates(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;

    final candidates = _iceCandidatesBuffer[peerId] ?? [];
    for (var candidate in candidates) {
      await pc.addCandidate(candidate);
    }
    _iceCandidatesBuffer.remove(peerId); // 处理完后清空缓存
  }


  @override
  void dispose() {
    _wsSubscription?.cancel();
    _localRenderer.dispose();
    _peerConnections.values.forEach((pc) => pc.close());
    _remoteRenderers.values.forEach((renderer) => renderer.dispose());
    super.dispose();
  }

  
}