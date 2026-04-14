import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:window_manager/window_manager.dart';

import 'app_env.dart';
import 'home_controller.dart';
import 'http_mgr.dart';
import 'meeting_page.dart';

final logger = Logger();

//tofix: 1. 预约会议的本地状态更新（已开始/已结束）
//tofix: 2. 主持人退出
class HomePage extends StatefulWidget {
  final String selfId;
  final HttpMgr httpMgr;

  const HomePage({super.key, required this.selfId, required this.httpMgr});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _controller;
  Timer? _meetingStatusTimer;
  StreamSubscription<HomeUiEvent>? _controllerEventSub;

  List<Meeting> get _scheduledMeetings {
    return _controller.scheduledMeetings;
  }

  List<Meeting> get _historyMeetings {
    return _controller.historyMeetings;
  }

  @override
  void initState() {
    super.initState();
    _controller = HomeController(
      selfId: widget.selfId,
      httpMgr: widget.httpMgr,
    );
    _controller.addListener(_onControllerUpdate);
    _controllerEventSub = _controller.uiEvents.listen(_handleControllerEvent);
    unawaited(_controller.initialize());
    _meetingStatusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controllerEventSub?.cancel();
    _meetingStatusTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleControllerEvent(HomeUiEvent event) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }

    switch (event.type) {
      case HomeUiEventType.showMessage:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(event.message)));
        break;
      case HomeUiEventType.joinAndNavigate:
        final roomId = event.roomId;
        final isHost = event.isHost ?? true;
        final openScreenShare = event.openScreenShare;
        if (roomId != null && roomId.isNotEmpty) {
          unawaited(
            _joinAndNavigate(
              roomId: roomId,
              isHost: isHost,
              openScreenShare: openScreenShare,
            ),
          );
        }
    }
  }

  Future<void> _joinAndNavigate({
    required String roomId,
    required bool isHost,
    bool openScreenShare = false,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final joinResult = await _controller.joinMeeting(
        roomId: roomId,
        isHost: isHost,
        meetingType: openScreenShare
            ? 'screen_share'
            : (isHost ? 'quick' : null),
      );

      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MeetingPage(
            selfId: widget.selfId,
            roomId: roomId,
            isHost: joinResult.isHost,
            signalingUrl: kSignalingUrl,
            alreadyJoined: true,
            openScreenShare: openScreenShare,
          ),
        ),
      );

      if (!mounted) return;
      await _controller.fetchMeetings();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          Container(
            width: 70,
            color: const Color(0xFFF2F3F5),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0xFF0052D9),
                  child: Text(
                    '头像',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 25),
                _sideIcon(Icons.videocam, '会议', isSelected: true),
                const Spacer(),
                _sideIcon(Icons.mail_outline, ''),
                _sideIcon(Icons.settings_outlined, ''),
                _sideIcon(Icons.person_outline, ''),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: _buildLeftContent(context)),
                        Expanded(flex: 6, child: _buildRightContent()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              child: Container(),
            ),
          ),
          _winBtn(Icons.remove, () => windowManager.minimize()),
          _winBtn(Icons.crop_square, () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          }),
          _winBtn(Icons.close, () => windowManager.close(), isClose: true),
        ],
      ),
    );
  }

  Widget _buildLeftContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 30,
          crossAxisSpacing: 30,
          childAspectRatio: 1.1,
          children: [
            _mainCard(
              context,
              Icons.video_call,
              '快速会议',
              const Color(0xFF0052D9),
              onTap: _controller.isQuickMeetingStarting
                  ? null
                  : () async {
                      await _controller.startQuickMeeting();
                    },
            ),
            _mainCard(
              context,
              Icons.group_add,
              '加入会议',
              const Color(0xFF0052D9),
              onTap: () {
                _showJoinDialog(context);
              },
            ),
            _mainCard(
              context,
              Icons.calendar_today,
              '预定会议',
              const Color(0xFF0052D9),
              onTap: () {
                _showReserveDialog(context);
              },
            ),
            _mainCard(
              context,
              Icons.screen_share,
              '共享屏幕',
              const Color(0xFF0052D9),
              onTap: _controller.isScreenShareStarting
                  ? null
                  : () async {
                      await _controller.startScreenShare();
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRightContent() {
    final date = DateFormat('M月d日').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(left: 60, top: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            date,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D2129),
            ),
          ),
          const SizedBox(height: 5),
          const Text('已登录', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),
          const Text(
            '预约会议',
            style: TextStyle(
              color: Color(0xFF1D2129),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildMeetingSection(
            meetings: _scheduledMeetings,
            emptyText: '暂无预约会议',
          ),
          const SizedBox(height: 16),
          const Text(
            '历史会议',
            style: TextStyle(
              color: Color(0xFF1D2129),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _historyMeetings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.coffee_outlined,
                          size: 80,
                          color: Colors.grey.withOpacity(0.2),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '暂无历史会议',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _historyMeetings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final meeting = _historyMeetings[index];
                      return _buildMeetingCard(meeting);
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sideIcon(IconData icon, String label, {bool isSelected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(
            icon,
            color: isSelected ? const Color(0xFF0052D9) : Colors.black54,
            size: 28,
          ),
          if (label.isNotEmpty)
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF0052D9) : Colors.black54,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _mainCard(
    BuildContext context,
    IconData icon,
    String title,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1D2129),
            ),
          ),
        ],
      ),
    );
  }

  Widget _winBtn(IconData icon, VoidCallback onTap, {bool isClose = false}) {
    return InkWell(
      onTap: onTap,
      hoverColor: isClose ? Colors.red : Colors.black12,
      child: SizedBox(
        width: 45,
        height: 40,
        child: Icon(icon, size: 16, color: Colors.black54),
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final TextEditingController roomCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final roomId = roomCtrl.text.trim();
            final canJoin = roomId.isNotEmpty;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '加入会议',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: roomCtrl,
                        autofocus: true,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          hintText: '请输入房间号',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (!canJoin)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '提示：请输入有效的会议号',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: !canJoin
                                ? null
                                : () async {
                                    Navigator.pop(dialogContext);
                                    await _joinAndNavigate(
                                      roomId: roomId,
                                      isHost: false,
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[200],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '确认加入',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                              foregroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '取消',
                              style: TextStyle(fontSize: 13),
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
  }

  void _showReserveDialog(BuildContext context) {
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    final roomId = (100000 + (DateTime.now().millisecondsSinceEpoch % 899999))
        .toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final finalDateTime = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              selectedTime.hour,
              selectedTime.minute,
            );
            final isValid = finalDateTime.isAfter(DateTime.now());

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '预定会议',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text(
                          '会议号：',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        Text(
                          roomId,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildPickerItem(
                      label: '会议日期',
                      value:
                          '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                        );
                        if (date != null) {
                          setDialogState(() => selectedDate = date);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPickerItem(
                      label: '开始时间',
                      value: selectedTime.format(context),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (time != null) {
                          setDialogState(() => selectedTime = time);
                        }
                      },
                    ),
                    if (!isValid)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '提示：预约时间不能早于当前时间',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: !isValid
                                ? null
                                : () async {
                                    logger.i('确认会议：$roomId at $finalDateTime');
                                    try {
                                      await _controller.reserveMeeting(
                                        roomId: roomId,
                                        startTime: finalDateTime,
                                      );

                                      if (!mounted) return;
                                      Navigator.pop(dialogContext);
                                    } catch (e) {
                                      logger.e('Error reserving meeting: $e');
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[200],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '确认预定',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                              foregroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '取消预约',
                              style: TextStyle(fontSize: 13),
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
  }

  Widget _buildPickerItem({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingSection({
    required List<Meeting> meetings,
    required String emptyText,
  }) {
    if (meetings.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text(
          emptyText,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.separated(
        itemCount: meetings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildMeetingCard(meetings[index]),
      ),
    );
  }

  Widget _buildMeetingCard(Meeting meeting) {
    final startText = DateFormat('yyyy-MM-dd HH:mm').format(meeting.startTime);
    final endText = meeting.endedAt == null
        ? null
        : DateFormat('yyyy-MM-dd HH:mm').format(meeting.endedAt!);
    final now = DateTime.now();
    final bool started = !meeting.isClosed && !meeting.startTime.isAfter(now);
    final statusText = meeting.isClosed ? '已关闭' : (started ? '已开始' : '未开始');
    final statusColor = meeting.isClosed
        ? const Color(0xFF8C8C8C)
        : (started ? const Color(0xFF18A058) : const Color(0xFF1677FF));
    return InkWell(
      onTap: () {
        if (statusText != '已开始') return;
        _showTipDialog('加入会议', '您确定要加入房间 ${meeting.roomId} 的会议吗？', () async {
          await _joinAndNavigate(roomId: meeting.roomId, isHost: false);
        }, null);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: Color(0xFF0052D9)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '房间号 ${meeting.roomId}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D2129),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '开始: $startText',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  if (endText != null)
                    Text(
                      '结束: $endText${meeting.endReason == null ? '' : '（${meeting.endReason}）'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTipDialog(
    String title,
    String content,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1D2129),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          content,
          style: const TextStyle(
            color: Color(0xFF4E5969),
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (onConfirm != null) {
                onConfirm();
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF0052D9),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('确定'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (onCancel != null) {
                onCancel();
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF7FAFF),
              foregroundColor: const Color(0xFF0052D9),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFB7D0F8)),
              ),
            ),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
