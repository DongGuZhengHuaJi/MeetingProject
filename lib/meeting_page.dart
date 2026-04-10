// pages/meeting_page.dart
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'webrtc_mgr.dart';


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
  bool _joinWithMic = false;
  bool _errorSnackBarShown = false;

  static const Color _pageBg = Color(0xFFF6F8FC);
  static const Color _brandBlue = Color(0xFF1677FF);
  static const Color _textPrimary = Color(0xFF1F2329);
  static const Color _textSecondary = Color(0xFF6B7280);
  
  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeMeeting();
    });
  }
  
  /// 初始化会议
  Future<void> _initializeMeeting() async {
    try {
      final shouldJoin = await _showPreJoinDialog();
      if (!mounted) return;

      if (!shouldJoin) {
        Navigator.pop(context);
        return;
      }

      // 1. 初始化信令
      await _manager.initializeSignaling(
        selfId: widget.selfId,
        signalingUrl: widget.signalingUrl,
      );

      // 2. 按用户选择进行设备权限预热，并刷新设备列表
      await _manager.prepareDevicesForJoin(
        requestMicPermission: _joinWithMic,
        requestCameraPermission: false,
      );
      
      // 3. 进入房间
      await _manager.joinRoom(
        roomId: widget.roomId,
        isHost: widget.isHost,
      );

      // 4. 仅在用户选择开麦时尝试打开麦克风
      if (_joinWithMic) {
        await _manager.toggleMicrophone();
        if (mounted && !_manager.isMicrophoneOn) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('麦克风权限未授予或设备不可用，已静音入会')),
          );
        }
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }

  Future<bool> _showPreJoinDialog() async {
    bool joinWithMic = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              constraints: BoxConstraints(maxWidth: 400),
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                constraints: BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '入会设置',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE6EAF2)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '加入时开启麦克风',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '默认关闭，避免误收音',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: joinWithMic,
                            activeColor: _brandBlue,
                            onChanged: (value) {
                              setDialogState(() {
                                joinWithMic = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(42),
                              side: const BorderSide(color: Color(0xFFD9E1EE)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              '取消',
                              style: TextStyle(color: _textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _joinWithMic = joinWithMic;
                              Navigator.of(dialogContext).pop(true);
                            },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(42),
                              backgroundColor: _brandBlue,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              '加入会议',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result ?? false;
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
    if (state.errorMessage != null && !_errorSnackBarShown) {
      _errorSnackBarShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
        _manager.clearMeetingError();
        _errorSnackBarShown = false;
      });
    }
    
    // 构建参会者列表
    final participants = _buildParticipantList();
    final allVideosOff = participants.every((p) => !p.isVideoOn);

    return Scaffold(
      backgroundColor: _pageBg,
      // appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTopWindowBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: allVideosOff
                    ? _buildAvatarGrid(participants)
                    : _buildVideoGrid(participants),
              ),
            ),
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

  // 顶部拖拽栏
  Widget _buildTopWindowBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) => windowManager.startDragging(), // 实现窗口拖拽
      onDoubleTap: () async {
        bool isMaximized = await windowManager.isMaximized();
        if (isMaximized) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.videocam_rounded, color: _brandBlue, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              "会议号: ${widget.roomId}",
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // 窗口操作按钮
            IconButton(
              icon: const Icon(Icons.minimize, color: Color(0xFF6B7280), size: 18),
              onPressed: () => windowManager.minimize(),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF6B7280), size: 18),
              // onPressed: () => _handleExit(),
              onPressed: () => _showLeaveConfirmDialog(),
            ),
          ],
        ),
      ),
    );
  }

  /// 所有人关闭视频时显示头像网格
  Widget _buildAvatarGrid(List<_ParticipantViewModel> participants) {
    return Container(
      color: const Color(0xFFF8FAFD),
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
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCircularAvatar(p.name, 68),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p.isAudioOn ? Icons.mic : Icons.mic_off,
                color: p.isAudioOn ? const Color(0xFF18A058) : const Color(0xFFE6504F),
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                p.name,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
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

        double currentRatio;
        if (count <= 1) {
          currentRatio = exactAvailableRatio; // 单人完全填满
        } else if (count == 2) {
          // 两人时，平分宽度，并向下填满整个高度
          currentRatio = (constraints.maxWidth / 2) / constraints.maxHeight;
        } else {
          currentRatio = videoAspectRatio; // 多人时回到 16:9
        }

        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: count <= 2 
              ? const NeverScrollableScrollPhysics() 
              : const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count <= 1 ? 1 : 2,
            // 3. 单人时使用 LayoutBuilder 提供的精准可用空间比例，彻底填满且不溢出
            childAspectRatio: currentRatio,
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
      margin: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(12),
      ),
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
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.isAudioOn ? Icons.mic : Icons.mic_off,
                    color: p.isAudioOn ? const Color(0xFF18A058) : const Color(0xFFE6504F),
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    p.name,
                    style: const TextStyle(color: _textPrimary, fontSize: 10),
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
        color: _brandBlue,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 12,
        left: 12,
        right: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildDeviceControlButton(
            isOn: _manager.isMicrophoneOn, 
            onIcon: Icons.mic_none, 
            offIcon: Icons.mic_off, 
            label: '音频', 
            onToggle: _manager.toggleMicrophone, 
            onSelectDevice: () => _showDevicePicker('microphone'),
          ),
          _buildDeviceControlButton(
            isOn: _manager.isCameraOn, 
            onIcon: Icons.videocam_outlined, 
            offIcon: Icons.videocam_off, 
            label: '视频', 
            onToggle: _manager.toggleCamera, 
            onSelectDevice: _manager.cameraDevices.isNotEmpty ? () => _showDevicePicker('camera') : () {},
          ),
          _buildToolButton(
            icon: _manager.isScreenSharing ? Icons.screen_share : Icons.screen_share_outlined,
            label: '共享屏幕',
            isActive: _manager.isScreenSharing,
            onTap: _manager.toggleScreenSharing,
          ),
          _buildToolButton(
            icon: Icons.group_outlined,
            label: '成员',
            isActive: false,
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
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final iconColor = isActive ? _brandBlue : _textPrimary;
    final bgColor = isActive ? const Color(0xFFEAF2FF) : const Color(0xFFF3F5F9);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(color: iconColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // 带有下拉箭头的控制按钮
  Widget _buildDeviceControlButton({
    required bool isOn,
    required IconData onIcon,
    required IconData offIcon,
    required String label,
    required VoidCallback onToggle,
    required VoidCallback onSelectDevice,
  }) {
    final iconColor = isOn ? _brandBlue : const Color(0xFFE6504F);
    final bgColor = isOn ? const Color(0xFFEAF2FF) : const Color(0xFFFFF0F0);

    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onToggle,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(isOn ? onIcon : offIcon, color: iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onSelectDevice,
                child: const Icon(Icons.keyboard_arrow_up, color: _textSecondary, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(color: iconColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveButton() {
    return GestureDetector(
      onTap: () => _showLeaveConfirmDialog(),
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFCEBEC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '离开',
          style: TextStyle(
            color: Color(0xFFE6504F),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
  
  void _showLeaveConfirmDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '离开会议',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '确定要离开当前会议吗？',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        side: const BorderSide(color: Color(0xFFD9E1EE)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: _textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        backgroundColor: _brandBlue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '确认离开',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showDevicePicker(String type) async {
    await _manager.loadDevices(); // 实时获取最新设备
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final List<_DevicePickerItem> devices = type == 'camera'
            ? _manager.cameraDevices
                .map(
                  (device) => _DevicePickerItem(
                    deviceId: device.deviceId,
                    label: device.label.isNotEmpty ? device.label : device.deviceId,
                    isDefault: false,
                  ),
                )
                .toList()
            : [
                const _DevicePickerItem(
                  deviceId: 'default',
                  label: '系统默认麦克风',
                  isDefault: true,
                ),
                ..._manager.microphoneDevices.map(
                  (device) => _DevicePickerItem(
                    deviceId: device.deviceId,
                    label: device.label.isNotEmpty ? device.label : device.deviceId,
                    isDefault: false,
                  ),
                ),
              ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE3EF),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  type == 'camera' ? '选择摄像头' : '选择麦克风',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: type == 'microphone' ? devices.length + 1 : devices.length,
                    itemBuilder: (context, index) {
                      if (type == 'microphone' && index == 0) {
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          leading: const Icon(Icons.hearing, color: _brandBlue),
                          title: const Text('测试系统默认麦克风', style: TextStyle(color: _textPrimary)),
                          subtitle: const Text(
                            '会短暂打开再立即关闭，用于检测是否可用',
                            style: TextStyle(color: _textSecondary, fontSize: 12),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            final available = await _manager.probeMicrophoneAvailability();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(available ? '系统默认麦克风可用' : '系统默认麦克风不可用'),
                              ),
                            );
                          },
                        );
                      }

                      final deviceIndex = type == 'microphone' ? index - 1 : index;
                      final d = devices[deviceIndex];
                      final currentId = type == 'camera' ? _manager.selectedCameraId : _manager.selectedMicrophoneId;

                      bool isSelected = currentId != null &&
                          currentId.isNotEmpty &&
                          d.deviceId.isNotEmpty &&
                          currentId == d.deviceId;
                      if (type == 'microphone' && d.isDefault && (currentId == null || currentId == 'default')) {
                        isSelected = true;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF5FF) : const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFBFD7FF) : const Color(0xFFE7ECF5),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? _brandBlue : const Color(0xFFB6BFCC),
                          ),
                          title: Text(d.label, style: const TextStyle(color: _textPrimary)),
                          onTap: () {
                            if (type == 'camera') {
                              _manager.switchCamera(d.deviceId);
                            } else if (type == 'microphone') {
                              _manager.switchMicrophone(d.deviceId);
                            }
                            Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showParticipantsList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE3EF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '参会成员 (${_manager.remotePeers.length + 1})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildParticipantListTile(
                      name: '${widget.selfId} (我)',
                      audioOn: _manager.isMicrophoneOn,
                      videoOn: _manager.isCameraOn,
                      isSelf: true,
                    ),
                    ..._manager.remotePeers.values.map(
                      (peer) => _buildParticipantListTile(
                        name: peer.name,
                        audioOn: peer.isAudioOn,
                        videoOn: peer.isVideoOn,
                        isSelf: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantListTile({
    required String name,
    required bool audioOn,
    required bool videoOn,
    required bool isSelf,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7ECF5)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: isSelf ? const Color(0xFFEAF2FF) : const Color(0xFFEFF2F7),
          child: Icon(
            isSelf ? Icons.person : Icons.person_outline,
            size: 16,
            color: isSelf ? _brandBlue : _textSecondary,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(color: _textPrimary, fontSize: 14),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              audioOn ? Icons.mic : Icons.mic_off,
              size: 19,
              color: audioOn ? const Color(0xFF18A058) : const Color(0xFFE6504F),
            ),
            const SizedBox(width: 10),
            Icon(
              videoOn ? Icons.videocam : Icons.videocam_off,
              size: 19,
              color: videoOn ? const Color(0xFF18A058) : const Color(0xFFE6504F),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePickerItem {
  final String deviceId;
  final String label;
  final bool isDefault;

  const _DevicePickerItem({
    required this.deviceId,
    required this.label,
    required this.isDefault,
  });
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