// pages/meeting_page.dart
import 'dart:async';

import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'meeting_controller.dart';

class MeetingPage extends StatefulWidget {
  final String selfId;
  final String selfName;
  final String roomId;
  final bool isHost;
  final String signalingUrl;
  final bool alreadyJoined;
  final bool openScreenShare;

  const MeetingPage({
    super.key,
    required this.selfId,
    required this.selfName,
    required this.roomId,
    this.isHost = false,
    required this.signalingUrl,
    this.alreadyJoined = false,
    this.openScreenShare = false,
  });

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  late final MeetingController _controller;
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _joinWithMic = false;
  bool _isLeaving = false;
  bool _isChatPanelVisible = false;
  Size? _windowSizeBeforeChat;
  StreamSubscription<MeetingPageUiEvent>? _controllerEventSub;
  _MeetingLayoutMode _layoutMode = _MeetingLayoutMode.grid;
  String? _activeSpeakerId;

  static const Color _pageBg = Color(0xFFF6F8FC);
  static const Color _brandBlue = Color(0xFF1677FF);
  static const Color _textPrimary = Color(0xFF1F2329);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const double _chatDockWidth = 360;

  @override
  void initState() {
    super.initState();
    _controller = MeetingController(
      selfId: widget.selfId,
      selfName: widget.selfName,
      roomId: widget.roomId,
      isHost: widget.isHost,
      signalingUrl: widget.signalingUrl,
      alreadyJoined: widget.alreadyJoined,
    );
    _controller.addListener(_onControllerUpdate);
    _controllerEventSub = _controller.uiEvents.listen(_handleControllerEvent);
    unawaited(_controller.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeMeeting();
    });
    if (widget.openScreenShare) {
      _controller.manager.toggleScreenSharing();
    }
  }

  void _handleControllerEvent(MeetingPageUiEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case MeetingPageUiEventType.exitPage:
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        break;
      case MeetingPageUiEventType.showMessage:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(event.message)));
        break;
    }
  }

  /// 初始化会议
  Future<void> _initializeMeeting() async {
    try {
      if (widget.alreadyJoined) {
        return;
      }

      final shouldJoin = await _showPreJoinDialog();
      if (!mounted) return;

      if (!shouldJoin) {
        Navigator.pop(context);
        return;
      }

      await _controller.startMeeting(joinWithMic: _joinWithMic);
    } catch (e) {
      // 错误提示由 controller 通过 uiEvents 下发，页面无需重复提示。
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
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
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
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

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controllerEventSub?.cancel();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    _controller.removeListener(_onControllerUpdate);
    if (_controller.manager.isInRoom && !_isLeaving) {
      _isLeaving = true;
      unawaited(_controller.leaveMeeting(endMeetingIfHost: false));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 构建参会者列表
    final participants = _buildParticipantList();
    final allVideosOff = participants.every((p) => !p.isVideoOn);
    final activeSpeaker = _resolveActiveSpeaker(participants);

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: Scaffold(
        backgroundColor: _pageBg,
        // appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildTopWindowBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _layoutMode == _MeetingLayoutMode.grid
                            ? (allVideosOff
                                  ? _buildAvatarGrid(participants)
                                  : _buildVideoGrid(participants))
                            : _buildSpeakerLayout(
                                participants: participants,
                                activeSpeaker: activeSpeaker,
                              ),
                      ),
                    ),
                  ),
                  if (_isChatPanelVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 12, 8),
                      child: _buildDockedChatPanel(),
                    ),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(
        _chatScrollController.position.maxScrollExtent,
      );
    });
  }

  void _sendChatMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) return;

    _controller.addChatMessage(
      senderName: widget.selfName,
      content: text,
      isSentBySelf: true,
    );
    _chatInputController.clear();
    _scrollChatToBottom();
  }

  Future<void> _showChatPanel() async {
    if (_isChatPanelVisible) {
      _scrollChatToBottom();
      return;
    }

    final isMaximized = await windowManager.isMaximized();
    if (!isMaximized) {
      _windowSizeBeforeChat ??= await windowManager.getSize();
      await windowManager.setSize(
        Size(
          _windowSizeBeforeChat!.width + _chatDockWidth,
          _windowSizeBeforeChat!.height,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _isChatPanelVisible = true;
    });
    _scrollChatToBottom();
  }

  Future<void> _hideChatPanel() async {
    if (!_isChatPanelVisible) return;

    setState(() {
      _isChatPanelVisible = false;
    });

    final isMaximized = await windowManager.isMaximized();
    if (!isMaximized && _windowSizeBeforeChat != null) {
      await windowManager.setSize(_windowSizeBeforeChat!);
    }
    _windowSizeBeforeChat = null;
  }

  /// 构建参会者列表（本地 + 远端）
  List<_ParticipantViewModel> _buildParticipantList() {
    final List<_ParticipantViewModel> list = [];

    // 添加自己
    list.add(
      _ParticipantViewModel(
        id: widget.selfId,
        name: widget.selfName,
        renderer: _controller.manager.localRenderer,
        isVideoOn:
            _controller.manager.isCameraOn ||
            _controller.manager.isScreenSharing,
        isAudioOn: _controller.manager.isMicrophoneOn,
        isLocal: true,
      ),
    );

    // 添加远端用户
    for (final peer in _controller.manager.remotePeers.values) {
      list.add(
        _ParticipantViewModel(
          id: peer.id,
          name: peer.name,
          renderer: peer.renderer,
          isVideoOn: peer.isVideoOn,
          isAudioOn: peer.isAudioOn,
          isLocal: false,
        ),
      );
    }

    return list;
  }

  _ParticipantViewModel _resolveActiveSpeaker(
    List<_ParticipantViewModel> participants,
  ) {
    if (participants.isEmpty) {
      return _ParticipantViewModel(
        id: 'empty',
        name: '无参会者',
        renderer: null,
        isVideoOn: false,
        isAudioOn: false,
        isLocal: false,
      );
    }

    final current = _activeSpeakerId == null
        ? null
        : participants.where((p) => p.id == _activeSpeakerId).firstOrNull;
    if (current != null) {
      return current;
    }

    final firstVideoOn = participants.where((p) => p.isVideoOn).firstOrNull;
    final fallback = firstVideoOn ?? participants.first;
    _activeSpeakerId = fallback.id;
    return fallback;
  }

  void _switchActiveSpeaker(
    List<_ParticipantViewModel> participants,
    int step,
  ) {
    if (participants.length <= 1) return;
    final currentIndex = participants.indexWhere(
      (p) => p.id == _activeSpeakerId,
    );
    final normalizedIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex =
        (normalizedIndex + step + participants.length) % participants.length;
    setState(() {
      _activeSpeakerId = participants[nextIndex].id;
    });
  }

  Widget _buildSpeakerLayout({
    required List<_ParticipantViewModel> participants,
    required _ParticipantViewModel activeSpeaker,
  }) {
    final thumbnailParticipants = participants
        .where((p) => p.id != activeSpeaker.id)
        .toList();

    return Container(
      color: const Color(0xFFEEF2F8),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: _buildSpeakerMain(
                participants: participants,
                activeSpeaker: activeSpeaker,
              ),
            ),
          ),
          if (thumbnailParticipants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              child: _buildSpeakerThumbnails(
                participants: thumbnailParticipants,
                activeSpeakerId: activeSpeaker.id,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeakerMain({
    required List<_ParticipantViewModel> participants,
    required _ParticipantViewModel activeSpeaker,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFDDE4F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (activeSpeaker.isVideoOn && activeSpeaker.renderer != null)
            _VideoRendererView(
              renderer: activeSpeaker.renderer!,
              mirror:
                  activeSpeaker.isLocal && !_controller.manager.isScreenSharing,
            )
          else
            Center(child: _buildCircularAvatar(activeSpeaker.name, 104)),
          Positioned(
            left: 14,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    activeSpeaker.isAudioOn ? Icons.mic : Icons.mic_off,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    activeSpeaker.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildSpeakerSwitchButton(
                icon: Icons.chevron_left,
                onTap: () => _switchActiveSpeaker(participants, -1),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildSpeakerSwitchButton(
                icon: Icons.chevron_right,
                onTap: () => _switchActiveSpeaker(participants, 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerSwitchButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.4)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildSpeakerThumbnails({
    required List<_ParticipantViewModel> participants,
    required String activeSpeakerId,
  }) {
    return Container(
      width: 118,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8DEEA)),
      ),
      child: ListView.separated(
        itemCount: participants.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final p = participants[index];
          final isActive = p.id == activeSpeakerId;
          return GestureDetector(
            onTap: () {
              setState(() {
                _activeSpeakerId = p.id;
              });
            },
            child: _buildSpeakerThumbnailItem(
              participant: p,
              isActive: isActive,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpeakerThumbnailItem({
    required _ParticipantViewModel participant,
    required bool isActive,
  }) {
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: const Color(0xFFDCE3F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? _brandBlue : const Color(0xFFC8D1DF),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (participant.isVideoOn && participant.renderer != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _VideoRendererView(
                renderer: participant.renderer!,
                mirror:
                    participant.isLocal && !_controller.manager.isScreenSharing,
              ),
            )
          else
            Center(child: _buildCircularAvatar(participant.name, 34)),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                participant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
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
              child: const Icon(
                Icons.videocam_rounded,
                color: _brandBlue,
                size: 18,
              ),
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
              icon: const Icon(
                Icons.minimize,
                color: Color(0xFF6B7280),
                size: 18,
              ),
              onPressed: () => windowManager.minimize(),
            ),
            IconButton(
              icon: const Icon(
                Icons.maximize,
                color: Color(0xFF6B7280),
                size: 18,
              ),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
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
                color: p.isAudioOn
                    ? const Color(0xFF18A058)
                    : const Color(0xFFE6504F),
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
        final exactAvailableRatio =
            constraints.maxWidth / constraints.maxHeight;
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
              mirror: p.isLocal && !_controller.manager.isScreenSharing,
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
                    color: p.isAudioOn
                        ? const Color(0xFF18A058)
                        : const Color(0xFFE6504F),
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
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
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
            isOn: _controller.manager.isMicrophoneOn,
            onIcon: Icons.mic_none,
            offIcon: Icons.mic_off,
            label: '音频',
            onToggle: _controller.manager.toggleMicrophone,
            onSelectDevice: () => _showDevicePicker('microphone'),
          ),
          _buildDeviceControlButton(
            isOn: _controller.manager.isCameraOn,
            onIcon: Icons.videocam_outlined,
            offIcon: Icons.videocam_off,
            label: '视频',
            onToggle: _controller.manager.toggleCamera,
            onSelectDevice: _controller.manager.cameraDevices.isNotEmpty
                ? () => _showDevicePicker('camera')
                : () {},
          ),
          _buildToolButton(
            icon: _controller.manager.isScreenSharing
                ? Icons.screen_share
                : Icons.screen_share_outlined,
            label: '共享屏幕',
            isActive: _controller.manager.isScreenSharing,
            onTap: _controller.manager.toggleScreenSharing,
          ),
          _buildToolButton(
            icon: Icons.chat_bubble_outline,
            label: '聊天',
            isActive: false,
            onTap: _showChatPanel,
          ),
          _buildToolButton(
            icon: Icons.group_outlined,
            label: '成员',
            isActive: false,
            onTap: _showParticipantsList,
          ),
          _buildToolButton(
            icon: _layoutMode == _MeetingLayoutMode.speaker
                ? Icons.view_carousel_outlined
                : Icons.grid_view_rounded,
            label: _layoutMode == _MeetingLayoutMode.speaker ? '演讲者' : '网格',
            isActive: _layoutMode == _MeetingLayoutMode.speaker,
            onTap: () {
              setState(() {
                _layoutMode = _layoutMode == _MeetingLayoutMode.grid
                    ? _MeetingLayoutMode.speaker
                    : _MeetingLayoutMode.grid;
              });
            },
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
    final bgColor = isActive
        ? const Color(0xFFEAF2FF)
        : const Color(0xFFF3F5F9);

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
            Text(label, style: TextStyle(color: iconColor, fontSize: 11)),
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
                  child: Icon(
                    isOn ? onIcon : offIcon,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onSelectDevice,
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  color: _textSecondary,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: iconColor, fontSize: 11)),
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
              Text(
                widget.isHost ? '你是房主，可选择仅离开或直接结束会议。' : '确定要离开当前会议吗？',
                style: const TextStyle(color: _textSecondary, fontSize: 14),
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
                      onPressed: () async {
                        if (_isLeaving) return;
                        _isLeaving = true;
                        Navigator.pop(dialogContext);
                        await _controller.leaveMeeting(endMeetingIfHost: false);
                        if (!mounted) return;
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
                        '离开会议',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.isHost) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_isLeaving) return;
                      _isLeaving = true;
                      Navigator.pop(dialogContext);
                      await _controller.leaveMeeting(endMeetingIfHost: true);
                      if (!mounted) return;
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      backgroundColor: const Color(0xFFE6504F),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '结束会议（关闭房间）',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDevicePicker(String type) async {
    await _controller.manager.loadDevices(); // 实时获取最新设备
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final List<_DevicePickerItem> devices = type == 'camera'
            ? _controller.manager.cameraDevices
                  .map(
                    (device) => _DevicePickerItem(
                      deviceId: device.deviceId,
                      label: device.label.isNotEmpty
                          ? device.label
                          : device.deviceId,
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
                ..._controller.manager.microphoneDevices.map(
                  (device) => _DevicePickerItem(
                    deviceId: device.deviceId,
                    label: device.label.isNotEmpty
                        ? device.label
                        : device.deviceId,
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
                    itemCount: type == 'microphone'
                        ? devices.length + 1
                        : devices.length,
                    itemBuilder: (context, index) {
                      if (type == 'microphone' && index == 0) {
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: const Icon(Icons.hearing, color: _brandBlue),
                          title: const Text(
                            '测试系统默认麦克风',
                            style: TextStyle(color: _textPrimary),
                          ),
                          subtitle: const Text(
                            '会短暂打开再立即关闭，用于检测是否可用',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            final available = await _controller.manager
                                .probeMicrophoneAvailability();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  available ? '系统默认麦克风可用' : '系统默认麦克风不可用',
                                ),
                              ),
                            );
                          },
                        );
                      }

                      final deviceIndex = type == 'microphone'
                          ? index - 1
                          : index;
                      final d = devices[deviceIndex];
                      final currentId = type == 'camera'
                          ? _controller.manager.selectedCameraId
                          : _controller.manager.selectedMicrophoneId;

                      bool isSelected =
                          currentId != null &&
                          currentId.isNotEmpty &&
                          d.deviceId.isNotEmpty &&
                          currentId == d.deviceId;
                      if (type == 'microphone' &&
                          d.isDefault &&
                          (currentId == null || currentId == 'default')) {
                        isSelected = true;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFEFF5FF)
                              : const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFBFD7FF)
                                : const Color(0xFFE7ECF5),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? _brandBlue
                                : const Color(0xFFB6BFCC),
                          ),
                          title: Text(
                            d.label,
                            style: const TextStyle(color: _textPrimary),
                          ),
                          onTap: () {
                            if (type == 'camera') {
                              _controller.manager.switchCamera(d.deviceId);
                            } else if (type == 'microphone') {
                              _controller.manager.switchMicrophone(d.deviceId);
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
                '参会成员 (${_controller.manager.remotePeers.length + 1})',
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
                      name: '${widget.selfName} (我)',
                      audioOn: _controller.manager.isMicrophoneOn,
                      videoOn:
                          _controller.manager.isCameraOn ||
                          _controller.manager.isScreenSharing,
                      isSelf: true,
                    ),
                    ..._controller.manager.remotePeers.values.map(
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
          backgroundColor: isSelf
              ? const Color(0xFFEAF2FF)
              : const Color(0xFFEFF2F7),
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
              color: audioOn
                  ? const Color(0xFF18A058)
                  : const Color(0xFFE6504F),
            ),
            const SizedBox(width: 10),
            Icon(
              videoOn ? Icons.videocam : Icons.videocam_off,
              size: 19,
              color: videoOn
                  ? const Color(0xFF18A058)
                  : const Color(0xFFE6504F),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDockedChatPanel() {
    return Container(
      width: _chatDockWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '聊天',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '消息 ${_controller.chatMessages.length}',
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _hideChatPanel,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: _textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7ECF5)),
                ),
                child: _controller.chatMessages.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无消息，来发第一条吧',
                          style: TextStyle(color: _textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _chatScrollController,
                        itemCount: _controller.chatMessages.length,
                        itemBuilder: (context, index) {
                          final msg = _controller.chatMessages[index];
                          final isSelf = msg.isSentBySelf;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Align(
                              alignment: isSelf
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 250,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelf ? _brandBlue : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: isSelf
                                        ? null
                                        : Border.all(
                                            color: const Color(0xFFE3E9F4),
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isSelf
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg.senderName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelf
                                              ? Colors.white70
                                              : _textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        msg.content,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isSelf
                                              ? Colors.white
                                              : _textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInputController,
                    onSubmitted: (_) => _sendChatMessage(),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD8DFEA)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD8DFEA)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _brandBlue),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendChatMessage,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(64, 42),
                    backgroundColor: _brandBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '发送',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _MeetingLayoutMode { grid, speaker }

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
  final bool mirror;

  const _VideoRendererView({required this.renderer, required this.mirror});

  @override
  State<_VideoRendererView> createState() => _VideoRendererViewState();
}

class _VideoRendererViewState extends State<_VideoRendererView> {
  bool _isReady = false;

  void _bindRenderer({required bool forceSetState}) {
    final ready = widget.renderer.videoWidth > 0;
    if (forceSetState && mounted) {
      setState(() {
        _isReady = ready;
      });
    } else {
      _isReady = ready;
    }

    widget.renderer.onResize = () {
      if (mounted && !_isReady && widget.renderer.videoWidth > 0) {
        setState(() {
          _isReady = true;
        });
      }
    };
  }

  @override
  void initState() {
    super.initState();
    _bindRenderer(forceSetState: false);
  }

  @override
  void didUpdateWidget(covariant _VideoRendererView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderer != widget.renderer) {
      oldWidget.renderer.onResize = null;
      _bindRenderer(forceSetState: true);
    }
  }

  @override
  void dispose() {
    widget.renderer.onResize = null;
    super.dispose();
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
        mirror: widget.mirror,
        // objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      ),
    );
  }
}
