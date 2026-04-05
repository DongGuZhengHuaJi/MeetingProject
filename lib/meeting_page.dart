import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'webrtc_mgr.dart';

class MeetingPage extends StatefulWidget {
  final String selfId;
  final String roomId;
  final bool isHost; // 是否是创建者

  const MeetingPage({
    super.key, 
    required this.selfId, 
    required this.roomId, 
    this.isHost = false
  });

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  final _webRTCManager = WebRTCManager();
  bool _isMicOn = true;
  bool _isCamOn = true;

  @override
  void initState() {
    super.initState();
    _webRTCManager.addListener(_onManagerUpdate);
    
    Future.microtask(() {
      // 这里的 roomId 现在是动态传入的了
      _webRTCManager.startMeeting(
        roomId: widget.roomId,
        isCreate: widget.isHost, // 如果是快速会议，发 create；否则发 join
      );
    });
  }
  

  void _onManagerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _webRTCManager.removeListener(_onManagerUpdate);
    // 退出页面时，自动清理资源并离开房间
    _webRTCManager.leaveCurrentRoom();
    super.dispose();
  }

  void _toggleMic() {
    setState(() => _isMicOn = !_isMicOn);
    _webRTCManager.toggleAudio(!_isMicOn);
    
  }

  void _toggleCam() {
    setState(() => _isCamOn = !_isCamOn);
    _webRTCManager.toggleVideo(!_isCamOn);
  }

  @override
  Widget build(BuildContext context) {
    // 整合所有画面：本地画面 + 远程画面列表
    List<Widget> videoViews = [];

    // 1. 添加本地画面 (永远在第一位)
    videoViews.add(_buildVideoContainer(
      renderer: _webRTCManager.localRenderer,
      label: "${widget.selfId} (我)",
      isMirror: true,
    ));

    // 2. 添加所有远程画面
    _webRTCManager.remoteRenderers.forEach((peerId, renderer) {
      videoViews.add(_buildVideoContainer(
        renderer: renderer,
        label: peerId,
        isMirror: false,
      ));
    });

    // 3. 动态计算网格列数 (腾讯会议风格：1人全屏，2-4人两列，超过4人可扩展)
    int crossAxisCount = videoViews.length == 1 ? 1 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFF191919), // 腾讯会议暗色背景
      appBar: AppBar(
        title: Row(
          children: [
            const Text("会议室", style: TextStyle(fontSize: 16)),
            const Text("房间号: ", style: TextStyle(fontSize: 12, color: Colors.white70)),
            Text(widget.roomId, style: const TextStyle(fontSize: 12, color: Colors.white54))  
          ],
        ),
        backgroundColor: const Color(0xFF292929),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // ================= 视频网格区 =================
            GridView.builder(
              padding: const EdgeInsets.only(bottom: 80), // 留出底部工具栏的空间
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: videoViews.length == 1 ? 0.6 : 1.0, // 1人全屏长宽比，多人方形
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: videoViews.length,
              itemBuilder: (context, index) => videoViews[index],
            ),

            // ================= 底部工具栏 =================
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                height: 80,
                color: const Color(0xFF292929),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildToolButton(_isMicOn ? Icons.mic : Icons.mic_off, _isMicOn ? "静音" : "解除静音", _isMicOn ? Colors.white : Colors.red, _toggleMic),
                    _buildToolButton(_isCamOn ? Icons.videocam : Icons.videocam_off, _isCamOn ? "停止视频" : "开启视频", _isCamOn ? Colors.white : Colors.red, _toggleCam),
                    _buildToolButton(Icons.screen_share, "共享屏幕", Colors.white, () {}),
                    // 挂断按钮
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                        child: const Text("离开", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 辅助组件：构建单个视频画面框
  Widget _buildVideoContainer({required webrtc.RTCVideoRenderer renderer, required String label, required bool isMirror}) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频渲染
          webrtc.RTCVideoView(
            renderer,
            mirror: isMirror,
            objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          // 名字标签 (左下角)
          Positioned(
            left: 10, bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // 辅助组件：底部小工具按钮
  Widget _buildToolButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}