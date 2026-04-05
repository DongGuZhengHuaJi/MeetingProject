import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'webrtc_mgr.dart';

class MeetingPage extends StatefulWidget {
  final String selfId;
  final String roomId;
  final bool isHost;

  const MeetingPage({
    super.key,
    required this.selfId,
    required this.roomId,
    this.isHost = false,
  });

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  final _webRTCManager = WebRTCManager();

  @override
  void initState() {
    super.initState();
    _webRTCManager.addListener(_onUpdate);
    Future.microtask(() {
      _webRTCManager.startMeeting(roomId: widget.roomId, isCreate: widget.isHost);
    });
  }

  void _onUpdate() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _webRTCManager.removeListener(_onUpdate);
    _webRTCManager.leaveCurrentRoom();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 汇总参会者
    final me = _Participant(
      id: widget.selfId,
      name: "我",
      renderer: _webRTCManager.localRenderer,
      isVideoOn: _webRTCManager.isCamOn,
      isAudioOn: _webRTCManager.isMicOn,
    );

    final List<_Participant> others = _webRTCManager.remoteRenderers.entries.map((e) {
      return _Participant(
        id: e.key,
        name: e.key,
        renderer: e.value,
        // 这里需要从 manager 的状态 Map 中取值，演示先设为 false 测试效果
        isVideoOn: _webRTCManager.remoteVideoStates[e.key] ?? false, 
        isAudioOn: true,
      );
    }).toList();

    final allParticipants = [me, ...others];

    // 【核心逻辑】是否所有人（我+他人）都关闭了视频
    bool allVideosOff = allParticipants.every((p) => !p.isVideoOn);

    return Scaffold(
      backgroundColor: Colors.white, // 腾讯会议白色调
      appBar: _buildWhiteAppBar(),
      body: Column(
        children: [
          Expanded(
            child: allVideosOff 
              ? _buildAvatarGrid(allParticipants) // 所有人关闭时的头像阵列
              : _buildVideoGrid(allParticipants), // 有人开启时的视频网格
          ),
          _buildWhiteBottomBar(),
        ],
      ),
    );
  }

  // 1. 白色顶部栏
  PreferredSizeWidget _buildWhiteAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Column(
        children: [
          Text("视频会议", style: TextStyle(color: Colors.black.withOpacity(0.8), fontSize: 16)),
          Text("ID: ${widget.roomId}", style: const TextStyle(color: Colors.black45, fontSize: 11)),
        ],
      ),
      leading: const Icon(Icons.info_outline, color: Colors.black45),
      actions: [
        IconButton(icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.black45), onPressed: () {}),
      ],
    );
  }

  // 2. 【重点实现】所有人关闭视频时的“头像格阵” (白色背景，无黑框)
  Widget _buildAvatarGrid(List<_Participant> participants) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Wrap(
          spacing: 30,
          runSpacing: 30,
          alignment: WrapAlignment.center,
          children: participants.map((p) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCircularAvatar(p.name, 70),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!p.isAudioOn) const Icon(Icons.mic_off, color: Colors.red, size: 12),
                  const SizedBox(width: 4),
                  Text(p.name, style: const TextStyle(color: Colors.black87, fontSize: 12)),
                ],
              )
            ],
          )).toList(),
        ),
      ),
    );
  }

  // 3. 正常视频网格 (有人开视频时显示，背景是淡灰色，视频窗口之间有细白边隔开)
   Widget _buildVideoGrid(List<_Participant> participants) {
    int count = participants.length;
    double screenRatio = MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
    double videoAspectRatio = 16 / 9; // 标准视频比例

    return GridView.builder(
      padding: const EdgeInsets.all(0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count <= 1 ? 1 : 2,
        childAspectRatio: count <= 1 ? screenRatio : videoAspectRatio,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final p = participants[index];
        return Container(
          margin: EdgeInsets.zero,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (p.isVideoOn)
                webrtc.RTCVideoView(
                  p.renderer,
                  mirror: p.id == "我" || p.id == widget.selfId,
                  objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Center(child: _buildCircularAvatar(p.name, 60)),
              
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
                      Icon(p.isAudioOn ? Icons.mic : Icons.mic_off, 
                          color: p.isAudioOn ? Colors.white : Colors.red, 
                          size: 10),
                      const SizedBox(width: 4),
                      Text(p.name, 
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // 圆形蓝色头像组件
  Widget _buildCircularAvatar(String name, double size) {
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(color: Color(0xFF0052D9), shape: BoxShape.circle),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : "?",
          style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // 4. 白色底栏
  Widget _buildWhiteBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 10, top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolBtn(_webRTCManager.isMicOn ? Icons.mic_none : Icons.mic_off, "静音", _webRTCManager.isMicOn ? Colors.black87 : Colors.red, _webRTCManager.toggleAudio),
          _buildToolBtn(_webRTCManager.isCamOn ? Icons.videocam_outlined : Icons.videocam_off, "视频", _webRTCManager.isCamOn ? Colors.black87 : Colors.red, _webRTCManager.toggleVideo),
          _buildToolBtn(Icons.screen_share_outlined, "共享屏幕", Colors.black87, () {}),
          _buildToolBtn(Icons.group_outlined, "成员", Colors.black87, () {}),
          
          // 红色离开按钮
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFE54545), borderRadius: BorderRadius.circular(6)),
              child: const Text("结束会议", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildToolBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
        ],
      ),
    );
  }
}

class _Participant {
  final String id;
  final String name;
  final webrtc.RTCVideoRenderer renderer;
  final bool isVideoOn;
  final bool isAudioOn;
  _Participant({required this.id, required this.name, required this.renderer, required this.isVideoOn, required this.isAudioOn});
}