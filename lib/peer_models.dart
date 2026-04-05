// models/peer_models.dart
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;


/// 远程参会者模型
class RemotePeer {
  final String id;
  String name;
  
  webrtc.RTCPeerConnection? connection;
  webrtc.RTCVideoRenderer? renderer;
  
  bool isVideoOn = false;
  bool isAudioOn = false;
  
  /// ICE 候选缓冲区（等待远端描述设置完成后再添加）
  final List<webrtc.RTCIceCandidate> iceBuffer = [];
  
  /// 连接状态
  PeerConnectionState state = PeerConnectionState.idle;
  
  RemotePeer({required this.id, this.name = ''});
  
  void dispose() {
    renderer?.srcObject = null;
    renderer?.dispose();
    connection?.close();
  }
}

enum PeerConnectionState {
  idle,           // 初始状态
  connecting,     // 正在建立连接
  connected,      // 连接成功
  disconnected,   // 连接断开
  failed,         // 连接失败
}

/// 本地媒体状态
class LocalMediaState {
  final bool isCameraOn;
  final bool isMicrophoneOn;
  final webrtc.MediaStream? stream;
  final webrtc.RTCVideoRenderer renderer;
  
  const LocalMediaState({
    required this.isCameraOn,
    required this.isMicrophoneOn,
    required this.stream,
    required this.renderer,
  });
  
  LocalMediaState copyWith({
    bool? isCameraOn,
    bool? isMicrophoneOn,
    webrtc.MediaStream? stream,
    webrtc.RTCVideoRenderer? renderer,
  }) {
    return LocalMediaState(
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isMicrophoneOn: isMicrophoneOn ?? this.isMicrophoneOn,
      stream: stream ?? this.stream,
      renderer: renderer ?? this.renderer,
    );
  }
}

/// 会议状态
class MeetingState {
  final bool isInRoom;
  final String? currentRoomId;
  final bool isSignalingConnected;
  final String? errorMessage;
  
  const MeetingState({
    this.isInRoom = false,
    this.currentRoomId,
    this.isSignalingConnected = false,
    this.errorMessage,
  });
  
  MeetingState copyWith({
    bool? isInRoom,
    String? currentRoomId,
    bool? isSignalingConnected,
    String? errorMessage,
  }) {
    return MeetingState(
      isInRoom: isInRoom ?? this.isInRoom,
      currentRoomId: currentRoomId ?? this.currentRoomId,
      isSignalingConnected: isSignalingConnected ?? this.isSignalingConnected,
      errorMessage: errorMessage,
    );
  }
}