import 'dart:async';

import 'package:flutter/foundation.dart';

import 'webrtc_mgr.dart';

class Msg {
  final String senderName;
  final String content;
  final bool isSentBySelf;

  Msg(this.senderName, this.content, this.isSentBySelf);
}

enum MeetingPageUiEventType { showMessage, exitPage }

class MeetingPageUiEvent {
  final MeetingPageUiEventType type;
  final String message;

  const MeetingPageUiEvent({required this.type, required this.message});
}

class MeetingController extends ChangeNotifier {
  final String selfId;
  final String roomId;
  final bool isHost;
  final String signalingUrl;
  final bool alreadyJoined;
  final WebRTCManager manager;

  MeetingController({
    required this.selfId,
    required this.roomId,
    required this.isHost,
    required this.signalingUrl,
    required this.alreadyJoined,
    WebRTCManager? manager,
  }) : manager = manager ?? WebRTCManager();

  final StreamController<MeetingPageUiEvent> _uiEventController =
      StreamController<MeetingPageUiEvent>.broadcast();

  StreamSubscription<MeetingUiEvent>? _managerEventSub;

  Stream<MeetingPageUiEvent> get uiEvents => _uiEventController.stream;

  List<Msg> messages = [];
  List<Msg> get chatMessages => List.unmodifiable(messages);

  void addChatMessage({
    required String senderName,
    required String content,
    required bool isSentBySelf,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    messages.add(Msg(senderName, trimmed, isSentBySelf));
    notifyListeners();
  }

  Future<void> initialize() async {
    manager.addListener(_relayManagerState);
    _managerEventSub = manager.uiEvents.listen(_handleManagerEvent);

    if (alreadyJoined) {
      return;
    }
  }

  Future<void> startMeeting({required bool joinWithMic}) async {
    if (alreadyJoined) {
      return;
    }

    try {
      await manager.initializeSignaling(
        selfId: selfId,
        signalingUrl: signalingUrl,
      );

      await manager.prepareDevicesForJoin(
        requestMicPermission: joinWithMic,
        requestCameraPermission: false,
      );

      await manager.joinRoom(roomId: roomId, isHost: isHost);

      if (joinWithMic) {
        await manager.toggleMicrophone();
        if (!manager.isMicrophoneOn) {
          _emitUiEvent(
            const MeetingPageUiEvent(
              type: MeetingPageUiEventType.showMessage,
              message: '麦克风权限未授予或设备不可用，已静音入会',
            ),
          );
        }
      }
    } catch (e) {
      _emitUiEvent(
        MeetingPageUiEvent(
          type: MeetingPageUiEventType.showMessage,
          message: '初始化失败: $e',
        ),
      );
      rethrow;
    }
  }

  Future<void> leaveMeeting({required bool endMeetingIfHost}) {
    return manager.leaveRoom(endMeetingIfHost: endMeetingIfHost);
  }

  void _relayManagerState() {
    notifyListeners();
  }

  void _handleManagerEvent(MeetingUiEvent event) {
    switch (event.type) {
      case MeetingUiEventType.roomClosed:
        _emitUiEvent(
          MeetingPageUiEvent(
            type: MeetingPageUiEventType.showMessage,
            message: event.message,
          ),
        );
        _emitUiEvent(
          const MeetingPageUiEvent(
            type: MeetingPageUiEventType.exitPage,
            message: '',
          ),
        );
        break;
      case MeetingUiEventType.joinFailed:
      case MeetingUiEventType.signalingError:
        _emitUiEvent(
          MeetingPageUiEvent(
            type: MeetingPageUiEventType.showMessage,
            message: event.message,
          ),
        );
        break;
      case MeetingUiEventType.joinSucceeded:
      case MeetingUiEventType.reservationNotice:
        break;
    }
  }

  void _emitUiEvent(MeetingPageUiEvent event) {
    if (!_uiEventController.isClosed) {
      _uiEventController.add(event);
    }
  }

  @override
  void dispose() {
    _managerEventSub?.cancel();
    manager.removeListener(_relayManagerState);
    _uiEventController.close();
    super.dispose();
  }
}
