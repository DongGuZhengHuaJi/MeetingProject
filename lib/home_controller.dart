import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_env.dart';
import 'http_mgr.dart';
import 'webrtc_mgr.dart';

enum HomeUiEventType { showMessage, joinAndNavigate }

class HomeUiEvent {
  final HomeUiEventType type;
  final String message;
  final String? roomId;
  final bool? isHost;

  const HomeUiEvent({
    required this.type,
    required this.message,
    this.roomId,
    this.isHost,
  });
}

class HomeController extends ChangeNotifier {
  final String selfId;
  final HttpMgr httpMgr;
  final WebRTCManager manager;

  HomeController({
    required this.selfId,
    required this.httpMgr,
    WebRTCManager? manager,
  }) : manager = manager ?? WebRTCManager();

  final List<ReservedMeeting> _reservedMeetings = [];
  final StreamController<HomeUiEvent> _uiEventController =
      StreamController<HomeUiEvent>.broadcast();

  StreamSubscription<MeetingUiEvent>? _managerEventSub;
  bool _isQuickMeetingStarting = false;

  Stream<HomeUiEvent> get uiEvents => _uiEventController.stream;
  bool get isQuickMeetingStarting => _isQuickMeetingStarting;

  List<ReservedMeeting> get scheduledReservedMeetings {
    final result = _reservedMeetings
        .where((m) => m.meetingType == 'reserved' && !m.isClosed)
        .toList();
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  List<ReservedMeeting> get historyMeetings {
    final result = _reservedMeetings
        .where((m) => m.meetingType == 'reserved' && m.isClosed)
        .toList();
    result.sort((a, b) {
      final aEnd = a.endedAt ?? a.startTime;
      final bEnd = b.endedAt ?? b.startTime;
      return bEnd.compareTo(aEnd);
    });
    return result;
  }

  Future<void> initialize() async {
    _managerEventSub = manager.uiEvents.listen(_handleManagerEvent);
    await fetchReservedMeetings();
  }

  Future<void> fetchReservedMeetings() async {
    try {
      final meetings = await httpMgr.getUserReservedMeetings(userId: selfId);
      _reservedMeetings
        ..clear()
        ..addAll(meetings);
      notifyListeners();
    } on ApiException catch (e) {
      _emitUiEvent(
        HomeUiEvent(
          type: HomeUiEventType.showMessage,
          message: '获取会议列表失败：${e.message}',
        ),
      );
    } catch (e) {
      _emitUiEvent(
        HomeUiEvent(type: HomeUiEventType.showMessage, message: '获取会议列表失败：$e'),
      );
    }
  }

  Future<void> reserveMeeting({
    required String roomId,
    required DateTime startTime,
  }) async {
    try {
      await httpMgr.reserveMeeting(
        userId: selfId,
        roomId: roomId,
        startTime: startTime,
      );
      _upsertReservedMeeting(
        roomId: roomId,
        startTime: startTime,
        status: 'scheduled',
      );
      _emitUiEvent(
        HomeUiEvent(
          type: HomeUiEventType.showMessage,
          message: '会议预约成功：$roomId',
        ),
      );
    } on ApiException catch (e) {
      _emitUiEvent(
        HomeUiEvent(
          type: HomeUiEventType.showMessage,
          message: '预约失败：${e.message}',
        ),
      );
      rethrow;
    } catch (e) {
      _emitUiEvent(
        HomeUiEvent(type: HomeUiEventType.showMessage, message: '预约失败：$e'),
      );
      rethrow;
    }
  }

  Future<void> quickMeeting() async {
    if (_isQuickMeetingStarting) {
      return;
    }

    _isQuickMeetingStarting = true;
    notifyListeners();

    final randomRoom =
        (100000 + (DateTime.now().millisecondsSinceEpoch % 899999)).toString();
    try {
      await httpMgr.startQuickMeeting(userId: selfId, roomId: randomRoom);
    } catch (e) {
      _emitUiEvent(
        HomeUiEvent(type: HomeUiEventType.showMessage, message: '快速会议记录失败：$e'),
      );
      return;
    } finally {
      _isQuickMeetingStarting = false;
      notifyListeners();
    }

    _emitUiEvent(
      HomeUiEvent(
        type: HomeUiEventType.joinAndNavigate,
        message: '开始快速会议',
        roomId: randomRoom,
        isHost: true,
      ),
    );
  }

  Future<JoinRoomResult> joinMeeting({
    required String roomId,
    required bool isHost,
  }) async {
    if (!manager.meetingState.isSignalingConnected ||
        manager.selfId != selfId) {
      await manager.initializeSignaling(
        selfId: selfId,
        signalingUrl: kSignalingUrl,
      );
    }

    if (manager.isInRoom) {
      final currentRoom = manager.meetingState.currentRoomId;
      if (currentRoom != roomId) {
        await manager.leaveRoom();
      }
    }

    return manager.joinRoom(roomId: roomId, isHost: isHost);
  }

  void _upsertReservedMeeting({
    required String roomId,
    required DateTime startTime,
    required String status,
  }) {
    final idx = _reservedMeetings.indexWhere((m) => m.roomId == roomId);
    if (idx >= 0) {
      _reservedMeetings[idx] = ReservedMeeting(
        roomId: roomId,
        startTime: startTime,
        meetingType: 'reserved',
        status: status,
      );
    } else {
      _reservedMeetings.add(
        ReservedMeeting(
          roomId: roomId,
          startTime: startTime,
          meetingType: 'reserved',
          status: status,
        ),
      );
    }

    _reservedMeetings.sort((a, b) => a.startTime.compareTo(b.startTime));
    notifyListeners();
  }

  void _handleManagerEvent(MeetingUiEvent event) {
    switch (event.type) {
      case MeetingUiEventType.roomClosed:
      case MeetingUiEventType.reservationNotice:
        unawaited(fetchReservedMeetings());
        break;
      case MeetingUiEventType.signalingError:
        _emitUiEvent(
          HomeUiEvent(
            type: HomeUiEventType.showMessage,
            message: event.message,
          ),
        );
        break;
      case MeetingUiEventType.joinSucceeded:
      case MeetingUiEventType.joinFailed:
        break;
    }
  }

  void _emitUiEvent(HomeUiEvent event) {
    if (!_uiEventController.isClosed) {
      _uiEventController.add(event);
    }
  }

  @override
  void dispose() {
    _managerEventSub?.cancel();
    _uiEventController.close();
    super.dispose();
  }
}
