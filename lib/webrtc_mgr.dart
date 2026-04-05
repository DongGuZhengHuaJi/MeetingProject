
// managers/webrtc_manager.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'peer_models.dart';
import 'websocket_mgr.dart';

/// WebRTC 会议管理器
/// 
/// 职责：
/// 1. 管理信令连接
/// 2. 管理本地媒体流
/// 3. 管理所有远端 Peer 连接
/// 4. 处理信令消息并分发
class WebRTCManager extends ChangeNotifier {
  // ==================== 单例 ====================
  static final WebRTCManager _instance = WebRTCManager._internal();
  factory WebRTCManager() => _instance;
  WebRTCManager._internal();
  
  // ==================== 依赖服务 ====================
  final WebsocketMgr _ws = WebsocketMgr();
  
  // ==================== 本地状态 ====================
  String _selfId = '';
  final webrtc.RTCVideoRenderer _localRenderer = webrtc.RTCVideoRenderer();
  webrtc.MediaStream? _localStream;
  webrtc.MediaStream? _screenStream;  // 屏幕流
  webrtc.MediaStream? _cameraStream;
  bool _isCameraOn = false;
  bool _isMicrophoneOn = false;
  bool _isScreenSharing = false;
  
  // ==================== 会议状态 ====================
  MeetingState _meetingState = const MeetingState();
  final Map<String, RemotePeer> _remotePeers = {};
  StreamSubscription<String>? _wsSubscription;
  
  // ==================== 常量配置 ====================
  static const Map<String, dynamic> _defaultVideoConstraints = {
    'width': {'ideal': 1280},
    'height': {'ideal': 720},
    'facingMode': 'user',
  };
  
  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };
  
  // ==================== 公共 Getter ====================
  String get selfId => _selfId;
  webrtc.RTCVideoRenderer get localRenderer => _localRenderer;
  bool get isCameraOn => _isCameraOn;
  bool get isMicrophoneOn => _isMicrophoneOn;
  MeetingState get meetingState => _meetingState;
  bool get isScreenSharing => _isScreenSharing;
  
  /// 获取所有远端参会者（不可修改的视图）
  Map<String, RemotePeer> get remotePeers => Map.unmodifiable(_remotePeers);
  
  /// 是否已在房间中
  bool get isInRoom => _meetingState.isInRoom;
  
  // ==================== 生命周期管理 ====================
  
  /// 初始化信令连接
  /// 
  /// [selfId] 当前用户唯一标识
  /// [signalingUrl] WebSocket 服务器地址
  Future<void> initializeSignaling({
    required String selfId,
    required String signalingUrl,
  }) async {
    if (_meetingState.isSignalingConnected) {
      logger.w('信令已初始化，跳过');
      return;
    }
    
    _selfId = selfId;
    
    try {
      await _ws.connect(signalingUrl);
      
      // 监听信令消息
      _wsSubscription = _ws.messages.listen(
        _handleSignalingMessage,
        onError: (error) {
          logger.e('WebSocket 错误: $error');
          _updateMeetingState(errorMessage: '信令连接错误: $error');
        },
        onDone: () {
          logger.w('WebSocket 连接关闭');
          _updateMeetingState(isSignalingConnected: false);
        },
      );
      
      // 注册身份
      _sendSignalingMessage({
        'type': 'register',
        'session_id': _selfId,
      });
      
      _updateMeetingState(isSignalingConnected: true);
      logger.i('✅ 信令初始化完成，用户ID: $_selfId');
      
    } catch (e) {
      logger.e('❌ 信令初始化失败: $e');
      _updateMeetingState(errorMessage: '初始化失败: $e');
      rethrow;
    }
  }
  
  /// 进入会议房间
  /// 
  /// [roomId] 房间号
  /// [isHost] 是否为创建者（房主）
  Future<void> joinRoom({
    required String roomId,
    bool isHost = false,
  }) async {
    _ensureSignalingReady();
    
    if (_meetingState.isInRoom) {
      throw StateError('已在房间中，请先调用 leaveRoom()');
    }
    
    try {
      // 1. 初始化本地媒体
      await _initializeLocalMedia();
      
      // 2. 发送进房信令
      _sendSignalingMessage({
        'type': isHost ? 'create' : 'join',
        'room': roomId,
      });
      
      _updateMeetingState(
        isInRoom: true,
        currentRoomId: roomId,
      );
      
      logger.i('🚪 已进入房间: $roomId');
      
    } catch (e) {
      logger.e('❌ 进入房间失败: $e');
      await _cleanupLocalMedia();
      rethrow;
    }
  }
  
  /// 离开当前房间
  Future<void> leaveRoom() async {
    if (!_meetingState.isInRoom) return;
    
    final roomId = _meetingState.currentRoomId;
    
    // 1. 通知服务器
    if (roomId != null) {
      _sendSignalingMessage({
        'type': 'leave',
        'room': roomId,
      });
    }
    
    // 2. 清理所有远端连接
    await _cleanupAllRemotePeers();
    
    // 3. 清理本地媒体
    await _cleanupLocalMedia();
    
    _updateMeetingState(
      isInRoom: false,
      currentRoomId: null,
    );
    
    logger.i('🚪 已离开房间');
  }
  
  /// 切换麦克风状态
  Future<void> toggleMicrophone() async {
    final audioTracks = _localStream?.getAudioTracks() ?? [];
    if (audioTracks.isEmpty) {
      logger.w('没有可用的音频轨道');
      return;
    }
    
    final newState = !_isMicrophoneOn;
    for (final track in audioTracks) {
      track.enabled = newState;
    }
    
    _isMicrophoneOn = newState;
    _broadcastMediaState();
    notifyListeners();
    
    logger.i('🎤 麦克风: ${_isMicrophoneOn ? "开启" : "关闭"}');
  }
  
  /// 切换摄像头状态
  Future<void> toggleCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) {
      logger.w('没有可用的视频轨道');
      return;
    }
    
    final newState = !_isCameraOn;
    for (final track in videoTracks) {
      track.enabled = newState;
    }
    
    _isCameraOn = newState;
    _broadcastMediaState();
    notifyListeners();
    
    logger.i('📹 摄像头: ${_isCameraOn ? "开启" : "关闭"}');
  }
  
  /// 动态调整摄像头分辨率
  Future<void> changeCameraQuality({
    required int width,
    required int height,
  }) async {
    if (_localStream == null) return;
    
    try {
      // 1. 获取新分辨率的视频轨道
      final newStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': width},
          'height': {'ideal': height},
        },
      });
      
      final newTrack = newStream.getVideoTracks().firstOrNull;
      if (newTrack == null) throw Exception('无法获取新视频轨道');
      
      newTrack.enabled = _isCameraOn;
      
      // 2. 替换旧轨道
      final oldTracks = _localStream!.getVideoTracks();
      if (oldTracks.isNotEmpty) {
        final oldTrack = oldTracks.first;
        try {
          await _localStream!.removeTrack(oldTrack);
        } catch (e) {
          logger.w('移除旧轨道时发生非致命错误: $e');
        }
        await oldTrack.stop();
      }
      
      await _localStream!.addTrack(newTrack);
      
      // 3. 刷新本地渲染器
      _localRenderer.srcObject = null;
      _localRenderer.srcObject = _localStream;
      
      // 4. 同步给所有远端
      await _replaceTrackOnAllConnections(newTrack);
      
      logger.i('✅ 分辨率切换成功: ${width}x${height}');
      notifyListeners();
      
    } catch (e) {
      logger.e('❌ 切换分辨率失败: $e');
      rethrow;
    }
  }
  
  /// 调整指定连接的发送画质
  Future<void> adjustSendQuality(
    String peerId, {
    double scaleDownBy = 1.0,
    int? maxBitrate,
  }) async {
    final peer = _remotePeers[peerId];
    if (peer?.connection == null) return;
    
    try {
      final senders = await peer!.connection!.getSenders();
      final videoSender = senders.cast<webrtc.RTCRtpSender?>().firstWhere(
        (s) => s?.track?.kind == 'video',
        orElse: () => null,
      );
      
      if (videoSender == null) return;
      
      final params = videoSender.parameters;
      if (params.encodings?.isNotEmpty ?? false) {
        params.encodings![0].scaleResolutionDownBy = scaleDownBy;
        if (maxBitrate != null) {
          params.encodings![0].maxBitrate = maxBitrate;
        }
        await videoSender.setParameters(params);
        
        logger.i('📊 发送画质调整 (给 $peerId): 缩放=$scaleDownBy, 码率=$maxBitrate');
      }
    } catch (e) {
      logger.e('调整发送画质失败: $e');
    }
  }
  
  /// 获取远端参会者的视频状态
  bool isRemoteVideoOn(String peerId) {
    return _remotePeers[peerId]?.isVideoOn ?? false;
  }
  
  /// 获取远端参会者的音频状态
  bool isRemoteAudioOn(String peerId) {
    return _remotePeers[peerId]?.isAudioOn ?? false;
  }

  Future<void> toggleScreenSharing() async {
    if (_isScreenSharing) {
      // 停止屏幕共享
      await _stopScreenSharing();
    } else {
      if(_isCameraOn){
        // 如果摄像头正在开启，先关闭它
        await toggleCamera();
      }
      // 开始屏幕共享
      await _startScreenSharing();
    }
  }
  
  // ==================== 私有方法：本地媒体管理 ====================
  
  Future<void> _initializeLocalMedia() async {
    // 初始化渲染器
    if (_localRenderer.textureId == null) {
      await _localRenderer.initialize();
    }
    
    // 清理旧流
    await _cleanupLocalMedia();
    
    try {
      // 获取新流
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _defaultVideoConstraints,
      });
      
      // 安全地设置轨道状态（默认关闭，等用户手动开启）
      final audioTracks = _localStream!.getAudioTracks();
      final videoTracks = _localStream!.getVideoTracks();
      
      if (audioTracks.isNotEmpty) {
        audioTracks.first.enabled = false;
        _isMicrophoneOn = false;
      }
      
      if (videoTracks.isNotEmpty) {
        videoTracks.first.enabled = false;
        _isCameraOn = false;
      }
      
      _localRenderer.srcObject = _localStream;
      logger.i('✅ 本地媒体初始化完成');
      
    } catch (e) {
      logger.e('❌ 本地媒体初始化失败: $e');
      rethrow;
    }
  }
  
  Future<void> _cleanupLocalMedia() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    
    _localRenderer.srcObject = null;
    _isCameraOn = false;
    _isMicrophoneOn = false;
  }
  
  Future<void> _startScreenSharing() async {
    if(_isScreenSharing) return;

    try{

      if (webrtc.WebRTC.platformIsAndroid || webrtc.WebRTC.platformIsIOS) {
        // 移动端：提示用户暂不支持，或引导使用"文件选择"分享图片
        throw Exception('移动端屏幕共享需要额外配置，请先使用桌面端测试');
      }
    
      _screenStream = await webrtc.navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': true,
      });

      _cameraStream = _localStream; // 备份当前摄像头流
      _localStream = _screenStream; // 切换到屏幕流
      _localRenderer.srcObject = _localStream;

      await _replaceTrackOnAllConnections(_screenStream!.getVideoTracks().first);

      _isScreenSharing = true;
      notifyListeners();
      logger.i('🖥️ 屏幕共享已开始');

      _screenStream!.getVideoTracks().first.onEnded = () {
        toggleScreenSharing();
      };

    }catch(e){
      logger.e('屏幕共享失败: $e');
      rethrow;
    }
  }

  Future<void> _stopScreenSharing() async {
    if(!_isScreenSharing) return;

    try{
      await _screenStream?.dispose();
      _screenStream = null;

      if(_cameraStream != null){
        _localStream = _cameraStream; // 切回摄像头流
        _localRenderer.srcObject = _localStream;
        await _replaceTrackOnAllConnections(_cameraStream!.getVideoTracks().first);
      }

      _isScreenSharing = false;
      notifyListeners();
      logger.i('🖥️ 屏幕共享已停止');
    }catch(e){
      logger.e('停止屏幕共享失败: $e');
    }
  }
  // ==================== 私有方法：远端 Peer 管理 ====================
  
  Future<RemotePeer> _getOrCreateRemotePeer(String peerId) async {
    if (_remotePeers.containsKey(peerId)) {
      return _remotePeers[peerId]!;
    }
    
    final peer = RemotePeer(id: peerId, name: peerId);
    
    // 初始化渲染器
    final renderer = webrtc.RTCVideoRenderer();
    await renderer.initialize();
    peer.renderer = renderer;
    
    _remotePeers[peerId] = peer;
    notifyListeners();
    
    return peer;
  }
  
  Future<void> _createPeerConnection(RemotePeer peer) async {
    if (peer.connection != null) return;
    
    peer.state = PeerConnectionState.connecting;
    
    final pc = await webrtc.createPeerConnection(_iceServers);
    peer.connection = pc;
    
    // ICE 候选处理
    pc.onIceCandidate = (candidate) {
      _sendSignalingMessage({
        'type': 'candidate',
        'from': _selfId,
        'to': peer.id,
        'candidate': candidate.toMap(),
      });
    };
    
    // 轨道接收处理
    pc.onTrack = (event) async {
      logger.i('📥 收到远端轨道 [${peer.id}]: ${event.track.kind}');
      
      if (event.streams.isNotEmpty) {
        peer.renderer?.srcObject = event.streams.first;
      }
      
      notifyListeners();
    };
    
    // 连接状态监听
    pc.onConnectionState = (state) {
      logger.i('🔗 连接状态 [${peer.id}]: $state');
      switch (state) {
        case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          peer.state = PeerConnectionState.connected;
          break;
        case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          peer.state = PeerConnectionState.disconnected;
          break;
        case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          peer.state = PeerConnectionState.failed;
          break;
        default:
          break;
      }
      notifyListeners();
    };
    
    // 添加本地轨道
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }
  }
  
  Future<void> _removeRemotePeer(String peerId) async {
    final peer = _remotePeers.remove(peerId);
    if (peer != null) {
      peer.dispose();
      logger.i('👋 移除远端用户: $peerId');
      notifyListeners();
    }
  }
  
  Future<void> _cleanupAllRemotePeers() async {
    for (final peer in _remotePeers.values) {
      peer.dispose();
    }
    _remotePeers.clear();
  }
  
  Future<void> _replaceTrackOnAllConnections(webrtc.MediaStreamTrack newTrack) async {
    for (final peer in _remotePeers.values) {
      if (peer.connection == null) continue;
      
      try {
        final senders = await peer.connection!.getSenders();
        final videoSender = senders.cast<webrtc.RTCRtpSender?>().firstWhere(
          (s) => s?.track?.kind == 'video',
          orElse: () => null,
        );
        
        if (videoSender != null) {
          await videoSender.replaceTrack(newTrack);
        }
      } catch (e) {
        logger.w('替换轨道失败 [${peer.id}]: $e');
      }
    }
  }
  
  // ==================== 私有方法：信令处理 ====================
  
  void _handleSignalingMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final fromId = (data['from'] ?? data['session_id'])?.toString();
      
      logger.d('📨 收到信令: $type from: $fromId');
      
      switch (type) {
        case 'register_success':
          logger.i('✅ 服务器注册成功');
          break;
          
        case 'user_joined':
          if (fromId != null && fromId != _selfId) {
            _handleUserJoined(fromId);
          }
          break;
          
        case 'media_state':
          if (fromId != null) {
            _handleMediaState(fromId, data);
          }
          break;
          
        case 'offer':
          if (fromId != null) {
            _handleOffer(fromId, data['sdp']);
          }
          break;
          
        case 'answer':
          if (fromId != null) {
            _handleAnswer(fromId, data['sdp']);
          }
          break;
          
        case 'candidate':
          if (fromId != null) {
            _handleCandidate(fromId, data['candidate']);
          }
          break;
          
        case 'leave':
          if (fromId != null) {
            _removeRemotePeer(fromId);
          }
          break;
          
        case 'error':
          logger.e('服务器错误: ${data['message']}');
          _updateMeetingState(errorMessage: data['message']);
          break;
          
        default:
          logger.w('未知信令类型: $type');
      }
      
      notifyListeners();
      
    } catch (e) {
      logger.e('处理信令消息失败: $e');
    }
  }
  
  Future<void> _handleUserJoined(String peerId) async {
    logger.i('👤 新用户加入: $peerId');
    await _initiateCall(peerId);
  }
  
  Future<void> _handleMediaState(String peerId, Map<String, dynamic> data) async {
    final peer = _remotePeers[peerId];
    if (peer == null) return;
    
    peer.isVideoOn = data['videoOn'] ?? false;
    peer.isAudioOn = data['audioOn'] ?? false;
    
    logger.i('📢 媒体状态更新 [$peerId]: 视频=${peer.isVideoOn}, 音频=${peer.isAudioOn}');
  }
  
  Future<void> _initiateCall(String peerId) async {
    try {
      final peer = await _getOrCreateRemotePeer(peerId);
      await _createPeerConnection(peer);
      
      final offer = await peer.connection!.createOffer();
      await peer.connection!.setLocalDescription(offer);
      
      _sendSignalingMessage({
        'type': 'offer',
        'from': _selfId,
        'to': peerId,
        'sdp': offer.sdp,
      });
      
      logger.i('📤 发送 Offer 给: $peerId');
      
    } catch (e) {
      logger.e('发起呼叫失败: $e');
    }
  }
  
  Future<void> _handleOffer(String peerId, String sdp) async {
    try {
      final peer = await _getOrCreateRemotePeer(peerId);
      await _createPeerConnection(peer);
      
      await peer.connection!.setRemoteDescription(
        webrtc.RTCSessionDescription(sdp, 'offer'),
      );
      
      // 处理缓冲的 ICE 候选
      await _processBufferedCandidates(peer);
      
      final answer = await peer.connection!.createAnswer();
      await peer.connection!.setLocalDescription(answer);
      
      _sendSignalingMessage({
        'type': 'answer',
        'from': _selfId,
        'to': peerId,
        'sdp': answer.sdp,
      });
      
      logger.i('📤 发送 Answer 给: $peerId');
      
    } catch (e) {
      logger.e('处理 Offer 失败: $e');
    }
  }
  
  Future<void> _handleAnswer(String peerId, String sdp) async {
    try {
      final peer = _remotePeers[peerId];
      if (peer?.connection == null) return;
      
      await peer!.connection!.setRemoteDescription(
        webrtc.RTCSessionDescription(sdp, 'answer'),
      );
      
      await _processBufferedCandidates(peer);
      
      logger.i('✅ Answer 处理完成: $peerId');
      
    } catch (e) {
      logger.e('处理 Answer 失败: $e');
    }
  }
  
  Future<void> _handleCandidate(String peerId, Map<String, dynamic> candidateMap) async {
    try {
      final peer = _remotePeers[peerId];
      final candidate = webrtc.RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      
      // 如果连接还没建立，先缓冲
      if (peer?.connection == null || await peer!.connection!.getRemoteDescription() == null) {
        peer!.iceBuffer.add(candidate);
        logger.d('⏳ 缓冲 ICE 候选: $peerId');
        return;
      }
      
      await peer.connection!.addCandidate(candidate);
      logger.d('✅ 添加 ICE 候选: $peerId');
      
    } catch (e) {
      logger.e('处理 ICE 候选失败: $e');
    }
  }
  
  Future<void> _processBufferedCandidates(RemotePeer peer) async {
    if (peer.connection == null || peer.iceBuffer.isEmpty) return;
    
    for (final candidate in peer.iceBuffer) {
      try {
        await peer.connection!.addCandidate(candidate);
      } catch (e) {
        logger.w('添加缓冲 ICE 候选失败: $e');
      }
    }
    
    peer.iceBuffer.clear();
    logger.i('🔄 处理缓冲 ICE 候选完成: ${peer.id}');
  }
  
  void _broadcastMediaState() {
    _sendSignalingMessage({
      'type': 'media_state',
      'from': _selfId,
      'videoOn': _isCameraOn,
      'audioOn': _isMicrophoneOn,
    });
  }
  
  void _sendSignalingMessage(Map<String, dynamic> data) {
    _ws.send(jsonEncode(data));
  }
  
  void _updateMeetingState({
    bool? isInRoom,
    String? currentRoomId,
    bool? isSignalingConnected,
    String? errorMessage,
  }) {
    _meetingState = _meetingState.copyWith(
      isInRoom: isInRoom,
      currentRoomId: currentRoomId,
      isSignalingConnected: isSignalingConnected,
      errorMessage: errorMessage,
    );
    notifyListeners();
  }
  
  void _ensureSignalingReady() {
    if (!_meetingState.isSignalingConnected) {
      throw StateError('信令未初始化，请先调用 initializeSignaling()');
    }
  }
  
  @override
  void dispose() {
    _wsSubscription?.cancel();
    _cleanupAllRemotePeers();
    _cleanupLocalMedia();
    _localRenderer.dispose();
    super.dispose();
  }
}