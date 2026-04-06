// pages/meeting_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'webrtc_mgr.dart';
import 'peer_models.dart';

class MeetingPage extends StatefulWidget {
  final String selfId;
  final String roomId;
  final bool isHost;
  final String signalingUrl;

  const MeetingPage({
    super.key,
    required this.selfId,
    required this.roomId,
    this.isHost = false,
    required this.signalingUrl,
  });

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  final WebRTCManager _manager = WebRTCManager();
  
  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdate);
    _initializeMeeting();
  }
  
  /// 初始化会议
  Future<void> _initializeMeeting() async {
    try {
      // 1. 初始化信令
      await _manager.initializeSignaling(
        selfId: widget.selfId,
        signalingUrl: widget.signalingUrl,
      );
      
      // 2. 进入房间
      await _manager.joinRoom(
        roomId: widget.roomId,
        isHost: widget.isHost,
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }
  
  void _onManagerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerUpdate);
    _manager.leaveRoom();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _manager.meetingState;
    
    // 处理错误
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
      });
    }
    
    // 构建参会者列表
    final participants = _buildParticipantList();
    final allVideosOff = participants.every((p) => !p.isVideoOn);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: allVideosOff 
              ? _buildAvatarGrid(participants)
              : _buildVideoGrid(participants),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }
  
  /// 构建参会者列表（本地 + 远端）
  List<_ParticipantViewModel> _buildParticipantList() {
    final List<_ParticipantViewModel> list = [];
    
    // 添加自己
    list.add(_ParticipantViewModel(
      id: widget.selfId,
      name: '我',
      renderer: _manager.localRenderer,
      isVideoOn: _manager.isCameraOn,
      isAudioOn: _manager.isMicrophoneOn,
      isLocal: true,
    ));
    
    // 添加远端用户
    for (final peer in _manager.remotePeers.values) {
      list.add(_ParticipantViewModel(
        id: peer.id,
        name: peer.name,
        renderer: peer.renderer,
        isVideoOn: peer.isVideoOn,
        isAudioOn: peer.isAudioOn,
        isLocal: false,
      ));
    }
    
    return list;
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Column(
        children: [
          Text(
            '视频会议',
            style: TextStyle(
              color: Colors.black.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
          Text(
            'ID: ${widget.roomId}',
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 11,
            ),
          ),
        ],
      ),
      leading: const Icon(Icons.info_outline, color: Colors.black45),
      actions: [
        IconButton(
          icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.black45),
          onPressed: () {}, // TODO: 切换摄像头
        ),
      ],
    );
  }

  /// 所有人关闭视频时显示头像网格
  Widget _buildAvatarGrid(List<_ParticipantViewModel> participants) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Wrap(
          spacing: 30,
          runSpacing: 30,
          alignment: WrapAlignment.center,
          children: participants.map((p) => _buildAvatarItem(p)).toList(),
        ),
      ),
    );
  }
  
  Widget _buildAvatarItem(_ParticipantViewModel p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCircularAvatar(p.name, 70),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!p.isAudioOn) 
              const Icon(Icons.mic_off, color: Colors.red, size: 12),
            const SizedBox(width: 4),
            Text(
              p.name,
              style: const TextStyle(color: Colors.black87, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

/// 有人开启视频时显示视频网格
  Widget _buildVideoGrid(List<_ParticipantViewModel> participants) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = participants.length;
        
        // 1. 获取精准的可用区域比例（自动剔除了 AppBar 和 BottomBar 的高度）
        final exactAvailableRatio = constraints.maxWidth / constraints.maxHeight;
        const videoAspectRatio = 16 / 9;

        return GridView.builder(
          padding: EdgeInsets.zero,
          // 2. 核心修复：单人或双人时，彻底禁用物理滚动，把 UI 锁死在可视区域内
          physics: count <= 2 
              ? const NeverScrollableScrollPhysics() 
              : const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count <= 1 ? 1 : 2,
            // 3. 单人时使用 LayoutBuilder 提供的精准可用空间比例，彻底填满且不溢出
            childAspectRatio: count <= 1 ? exactAvailableRatio : videoAspectRatio,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          ),
          itemCount: count,
          itemBuilder: (context, index) => _buildVideoItem(participants[index]),
        );
      },
    );
  }

  Widget _buildVideoItem(_ParticipantViewModel p) {
    return Container(
      key: ValueKey(p.id), // 确保列表刷新时状态正确
      color: const Color(0xFF1A1A1A), // 使用深色背景，减少视觉突变
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 只有当视频开启且渲染器存在时才尝试渲染
          if (p.isVideoOn && p.renderer != null)
            _VideoRendererView(
              renderer: p.renderer!,
              isLocal: p.isLocal,
            )
          else
            Center(child: _buildCircularAvatar(p.name, 60)),
          // 信息浮层
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.isAudioOn ? Icons.mic : Icons.mic_off,
                    color: p.isAudioOn ? Colors.white : Colors.red,
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    p.name,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCircularAvatar(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF0052D9),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 10,
        top: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolButton(
            icon: _manager.isMicrophoneOn ? Icons.mic_none : Icons.mic_off,
            label: '静音',
            color: _manager.isMicrophoneOn ? Colors.black87 : Colors.red,
            onTap: _manager.toggleMicrophone,
          ),
          _buildToolButton(
            icon: _manager.isCameraOn ? Icons.videocam_outlined : Icons.videocam_off,
            label: '视频',
            color: _manager.isCameraOn ? Colors.black87 : Colors.red,
            onTap: _manager.toggleCamera,
          ),
          _buildToolButton(
            icon: _manager.isScreenSharing ? Icons.screen_share : Icons.screen_share_outlined,
            label: '共享屏幕',
            color: _manager.isScreenSharing ? Colors.black87 : Colors.red,
            onTap: _manager.toggleScreenSharing,
          ),
          _buildToolButton(
            icon: Icons.group_outlined,
            label: '成员',
            color: Colors.black87,
            onTap: _showParticipantsList,
          ),
          _buildLeaveButton(),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveButton() {
    return GestureDetector(
      onTap: () => _showLeaveConfirmDialog(),
      child: Container(
        margin: const EdgeInsets.only(left: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE54545),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '离开会议',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  void _showLeaveConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('离开会议'),
        content: const Text('确定要离开当前会议吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('离开', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  void _showParticipantsList() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '参会成员 (${_manager.remotePeers.length + 1})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text('${widget.selfId} (我)'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _manager.isMicrophoneOn ? Icons.mic : Icons.mic_off,
                    size: 20,
                    color: _manager.isMicrophoneOn ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _manager.isCameraOn ? Icons.videocam : Icons.videocam_off,
                    size: 20,
                    color: _manager.isCameraOn ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
            ..._manager.remotePeers.values.map((peer) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(peer.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    peer.isAudioOn ? Icons.mic : Icons.mic_off,
                    size: 20,
                    color: peer.isAudioOn ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    peer.isVideoOn ? Icons.videocam : Icons.videocam_off,
                    size: 20,
                    color: peer.isVideoOn ? Colors.green : Colors.red,
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

/// 参会者视图模型（UI 层专用）
class _ParticipantViewModel {
  final String id;
  final String name;
  final webrtc.RTCVideoRenderer? renderer;
  final bool isVideoOn;
  final bool isAudioOn;
  final bool isLocal;

  _ParticipantViewModel({
    required this.id,
    required this.name,
    this.renderer,
    required this.isVideoOn,
    required this.isAudioOn,
    required this.isLocal,
  });
}

class _VideoRendererView extends StatefulWidget {
  final webrtc.RTCVideoRenderer renderer;
  final bool isLocal;

  const _VideoRendererView({required this.renderer, required this.isLocal});

  @override
  State<_VideoRendererView> createState() => _VideoRendererViewState();
}

class _VideoRendererViewState extends State<_VideoRendererView> {
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // 初始检查：如果渲染器已经有画面了，直接显示
    if (widget.renderer.videoWidth > 0) {
      _isReady = true;
    }
    
    // 监听分辨率变化
    widget.renderer.onResize = () {
      if (mounted && !_isReady && widget.renderer.videoWidth > 0) {
        setState(() {
          _isReady = true;
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      // 如果没准备好，透明度为 0，防止看到那个“比例不对”的瞬间
      opacity: _isReady ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: webrtc.RTCVideoView(
        widget.renderer,
        mirror: widget.isLocal,
        objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}