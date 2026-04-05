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
  bool _isMicOn = false;
  bool _isCamOn = false;
  static const Map<String, int> kHDConstraints = {'width': 1280, 'height': 720};

  final Map<String, webrtc.RTCPeerConnection> _peerConnections = {};
  final Map<String, webrtc.RTCVideoRenderer> _remoteRenderers = {};
  Map<String, bool> remoteVideoStates = {};
  final Map<String, List<webrtc.RTCIceCandidate>> _iceCandidatesBuffer = {};

  Map<String, webrtc.RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
  webrtc.RTCVideoRenderer get localRenderer => _localRenderer;
  String get selfId => _selfId;
  bool get isMicOn => _isMicOn;
  bool get isCamOn => _isCamOn;


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
          remoteVideoStates[fromId] = false; // 默认远端视频状态为关闭，等对方更新状态后再刷新 UI
        }
        break;
      case 'media_state':
        if (fromId != null) {
          remoteVideoStates[fromId] = data['videoOn'] ?? false;
          // 这里可以扩展处理音频状态 data['audioOn']
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
    // 1. 初始化本地流和渲染器
    if (_localRenderer.textureId == null) {
      await _localRenderer.initialize();
    }
    
    // 确保旧流已经被彻底清理 (防御性编程)
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream!.dispose();
    }


    try {
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280}, // 只用 ideal，不要用 min
          'height': {'ideal': 720},
        },
      });
      
      // 【关键检查】：确保把流赋给了 renderer
      _localRenderer.srcObject = _localStream;
      _isCamOn = true; // 默认开启视频
      notifyListeners();
    } catch (e) {
      print("摄像头启动失败: $e"); // 如果还有问题，控制台会打印这里
    }
  

    _localStream!.getAudioTracks()[0].enabled = false;
    _localStream!.getVideoTracks()[0].enabled = false;
    _isCamOn = false;
    _isMicOn = false;

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
    for (final renderer in _remoteRenderers.values) { 
      renderer.srcObject = null; // 先置空
      await renderer.dispose(); 
    }
    _remoteRenderers.clear();
    
    // 3. 【核心修复 3】彻底关闭本地摄像头和麦克风硬件
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        track.stop(); // 停止硬件轨道
      }
      _localStream!.dispose(); // 释放流内存
      _localStream = null;
    }
    
    _localRenderer.srcObject = null;

    notifyListeners();
  }

void toggleAudio() {
  _isMicOn = !_isMicOn;
  _localStream?.getAudioTracks().forEach((track) => track.enabled = _isMicOn);

  notifyListeners();
}

void toggleVideo() {
  _isCamOn = !_isCamOn;
  _localStream?.getVideoTracks().forEach((track) {
    track.enabled = _isCamOn;
  });
  
  // 【关键】广播自己的状态给房间其他人
  ws.send(jsonEncode({
    'type': 'media_state',
    'from': _selfId,
    'videoOn': _isCamOn,
    'audioOn': _isMicOn,
  }));
  
  notifyListeners();
}

// 动态调整本地摄像头分辨率
// webrtc_mgr.dart

Future<void> changeCameraQuality({required int width, required int height}) async {
  if (_localStream == null) return;

  try {
    // 1. 先准备好新分辨率的轨道，确保硬件能正常响应
    webrtc.MediaStream newStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': false, // 切换分辨率不需要重新获取音频
      'video': {
        'facingMode': 'user',
        'width': {'ideal': width},
        'height': {'ideal': height},
      },
    });
    var newTrack = newStream.getVideoTracks().first;
    newTrack.enabled = _isCamOn; // 继承当前的开关状态

    // 2. 找到旧轨道
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      var oldTrack = videoTracks.first;

      // 3. 【核心修复】先从流中移除，再停止硬件。并包裹 try-catch 防止崩溃
      try {
        await _localStream!.removeTrack(oldTrack);
      } catch (e) {
        logger.w("移除旧轨道时发生非致命错误: $e");
      }
      await oldTrack.stop(); // 彻底关闭旧硬件占用
    }

    // 4. 将新轨道加入本地流对象
    await _localStream!.addTrack(newTrack);

    // 5. 【关键】强制刷新本地渲染器
    // 必须先置空再重新赋值，否则 Flutter 的 Texture 可能会卡在最后一帧
    _localRenderer.srcObject = null;
    _localRenderer.srcObject = _localStream;

    // 6. 同步给所有远端用户
    for (var pc in _peerConnections.values) {
      final senders = await pc.getSenders();
      final videoSender = senders.cast<webrtc.RTCRtpSender?>().firstWhere(
        (s) => s?.track?.kind == 'video',
        orElse: () => null,
      );

      if (videoSender != null) {
        // replaceTrack 是 WebRTC 提供的无缝替换技术
        await videoSender.replaceTrack(newTrack);
      }
    }

    logger.i("✅ 成功无缝切换分辨率至: ${width}x${height}");
    notifyListeners();
  } catch (e) {
    logger.e("❌ 彻底切换失败: $e");
    // 如果失败了，建议提示用户重启摄像头
  }
}

// 动态调整指定连接的发送画质 (修改编码参数)
Future<void> adjustSendQuality(String peerId, {double scaleDownBy = 1.0, int? maxBitrate}) async {
  final pc = _peerConnections[peerId];
  if (pc == null) return;

  try {
    // 找到视频发送器
    final senders = await pc.getSenders();
    final videoSender = senders.firstWhere((s) => s.track?.kind == 'video');

    // 获取当前参数
    final parameters = videoSender.parameters;
    
    // 修改编码参数
    if (parameters.encodings != null && parameters.encodings!.isNotEmpty) {
      // scaleDownBy: 1.0 表示不缩放，2.0 表示长宽各缩小一倍
      parameters.encodings![0].scaleResolutionDownBy = scaleDownBy;
      
      // maxBitrate: 最大码率 (bps)，例如 1000000 = 1Mbps
      if (maxBitrate != null) {
        parameters.encodings![0].maxBitrate = maxBitrate;
      }

      // 应用新参数
      await videoSender.setParameters(parameters);
      logger.i("发送画质已调整 (给 $peerId): 缩放=$scaleDownBy, 码率=$maxBitrate");
    }
  } catch (e) {
    logger.e("调整发送画质失败: $e");
  }
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