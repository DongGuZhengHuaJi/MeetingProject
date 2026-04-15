import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'app_env.dart';

class Meeting {
  final String roomId;
  final DateTime startTime;
  final String meetingType;
  final String status;
  final DateTime? endedAt;
  final String? endReason;

  Meeting({
    required this.roomId,
    required this.startTime,
    required this.meetingType,
    required this.status,
    this.endedAt,
    this.endReason,
  });

  bool get isClosed => status.toLowerCase() == 'closed';
}

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() {
    if (statusCode == null) {
      return 'ApiException: $message';
    }
    return 'ApiException($statusCode): $message';
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final int? accessExpiresIn;
  final int? refreshExpiresIn;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accessExpiresIn,
    this.refreshExpiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: (json['access_token'] ?? json['token'] ?? '').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
      accessExpiresIn: _toInt(json['access_expires_in']),
      refreshExpiresIn: _toInt(json['refresh_expires_in']),
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class HttpMgr {
  final String baseUrl;
  final Duration timeout;
  final HttpClient _client;

  String? _accessToken;
  String? _refreshToken;
  String? _selfName;
  Timer? _tokenRefreshTimer;

  static final HttpMgr _instance = HttpMgr._internal(
    kApiBaseUrl,
    timeout: const Duration(seconds: 12),
  );
  factory HttpMgr.instance() => _instance;
  HttpMgr._internal(
    this.baseUrl, {
    this.timeout = const Duration(seconds: 8),
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get selfName => _selfName;
  bool get hasLogin =>
      (_accessToken?.isNotEmpty ?? false) &&
      (_refreshToken?.isNotEmpty ?? false);

  void setTokens({required String accessToken, required String refreshToken}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
    _selfName = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  Future<Map<String, dynamic>> registerUser({
    required String userId,
    required String password,
  }) {
    return _postAction('register_user', {'from': userId, 'pwd': password});
  }

  Future<String> login({
    required String userId,
    required String password,
  }) async {
    final rsp = await _postAction('login', {'from': userId, 'pwd': password});

    final tokens = AuthTokens.fromJson(rsp);
    if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
      throw const ApiException('Server did not return valid tokens');
    }

    setTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );

    _scheduleTokenAutoRefresh(
      userId: userId,
      accessExpiresIn: tokens.accessExpiresIn,
    );

    _selfName = rsp['self_name']?.toString().trim();
    if (_selfName == null || _selfName!.isEmpty) {
      _selfName = userId;
    }

    return _selfName!;
  }

  Future<String> updateSelfName({
    required String userId,
    required String newName,
  }) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) {
      throw const ApiException('昵称不能为空');
    }

    final rsp = await postWithAccessToken(
      action: 'update_user_name',
      userId: userId,
      payload: {'self_name': normalized},
    );

    final latest = rsp['self_name']?.toString().trim();
    _selfName = (latest == null || latest.isEmpty) ? normalized : latest;
    return _selfName!;
  }

  Future<List<Meeting>> getUserMeetings({required String userId}) async {
    final rsp = await _postWithRetry(
      action: 'get_user_meetings',
      body: {'from': userId, 'access_token': _accessToken},
      maxAttempts: 2,
    );

    if (rsp['error'] != null) {
      throw ApiException(
        rsp['error'].toString(),
        statusCode: rsp['status_code'] as int?,
      );
    }

    final List<dynamic> meetings = rsp['meetings'] ?? [];
    return meetings
        .map(
          (r) => Meeting(
            roomId: r['room'] as String,
            startTime: _parseServerDateTime(r['time']),
            meetingType: (r['meeting_type'] ?? 'reserved').toString(),
            status: r['status'] as String,
            endedAt: _parseNullableServerDateTime(r['ended_at']),
            endReason: _parseNullableString(r['end_reason']),
          ),
        )
        .toList();
  }

  Future<List<Meeting>> getUserReservedMeetings({required String userId}) {
    return getUserMeetings(userId: userId);
  }

  Future<void> startQuickMeeting({
    required String userId,
    required String roomId,
  }) async {
    await postWithAccessToken(
      action: 'quick_meeting_start',
      userId: userId,
      payload: {'from': userId, 'room': roomId},
    );
  }

  Future<void> startScreenShare({
    required String userId,
    required String roomId,
  }) async {
    await postWithAccessToken(
      action: 'start_screen_share',
      userId: userId,
      payload: {'from': userId, 'room': roomId},
    );
  }


  static DateTime _parseServerDateTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      throw const ApiException('Invalid datetime value from server');
    }

    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.parse(normalized);
  }

  static DateTime? _parseNullableServerDateTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    return DateTime.parse(normalized);
  }

  static String? _parseNullableString(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return raw;
  }

  Future<void> reserveMeeting({
    required String userId,
    required String roomId,
    required DateTime startTime,
  }) async {
    await postWithAccessToken(
      action: 'reserve',
      userId: userId,
      payload: {
        'from': userId,
        'room': roomId,
        'time': startTime.toIso8601String(),
      },
    );
  }

  void _scheduleTokenAutoRefresh({
    required String userId,
    required int? accessExpiresIn,
  }) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;

    if (_accessToken == null ||
        _refreshToken == null ||
        accessExpiresIn == null ||
        accessExpiresIn <= 0) {
      return;
    }

    final int refreshBeforeSeconds = accessExpiresIn > 180
        ? 120
        : (accessExpiresIn ~/ 3).clamp(5, 60);
    final int delaySeconds = accessExpiresIn - refreshBeforeSeconds;
    if (delaySeconds <= 0) {
      return;
    }

    _tokenRefreshTimer = Timer(Duration(seconds: delaySeconds), () async {
      try {
        final refreshed = await refreshAccessToken(userId: userId);
        _scheduleTokenAutoRefresh(
          userId: userId,
          accessExpiresIn: refreshed.accessExpiresIn,
        );
      } catch (_) {
        clearTokens();
      }
    });
  }

  Future<AuthTokens> refreshAccessToken({required String userId}) async {
    final token = _refreshToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('Missing refresh token');
    }

    final rsp = await _postAction('refresh_token', {
      'from': userId,
      'refresh_token': token,
    });

    final tokens = AuthTokens.fromJson(rsp);
    if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
      throw const ApiException('Server did not return valid refreshed tokens');
    }

    setTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );

    _scheduleTokenAutoRefresh(
      userId: userId,
      accessExpiresIn: tokens.accessExpiresIn,
    );

    return tokens;
  }

  Future<Map<String, dynamic>> logout({required String userId}) async {
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      throw const ApiException('Missing login tokens');
    }

    final rsp = await _postAction('logout', {
      'from': userId,
      'access_token': access,
      'refresh_token': refresh,
    });

    clearTokens();
    return rsp;
  }

  Future<Map<String, dynamic>> postWithAccessToken({
    required String action,
    required String userId,
    Map<String, dynamic>? payload,
  }) {
    final access = _accessToken;
    if (access == null || access.isEmpty) {
      throw const ApiException('Missing access token');
    }

    return _postAction(action, {
      'from': userId,
      'access_token': access,
      ...?payload,
    });
  }

  Future<Map<String, dynamic>> _postAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(baseUrl);

    late HttpClientResponse rsp;
    String text = '';
    try {
      final req = await _client.postUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.write(jsonEncode({'action': action, ...body}));

      rsp = await req.close().timeout(timeout);
      text = await rsp.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException catch (_) {
      throw ApiException('Request timeout on action=$action');
    } on SocketException catch (e) {
      throw ApiException('Network error on action=$action: ${e.message}');
    }

    Map<String, dynamic> jsonBody;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Response is not a JSON object');
      }
      jsonBody = decoded;
    } catch (_) {
      throw ApiException(
        'Invalid JSON response: $text',
        statusCode: rsp.statusCode,
      );
    }

    if (rsp.statusCode < 200 || rsp.statusCode >= 300) {
      throw ApiException(
        jsonBody['error']?.toString() ?? 'Request failed',
        statusCode: rsp.statusCode,
      );
    }

    if (jsonBody.containsKey('error')) {
      throw ApiException(
        jsonBody['error']?.toString() ?? 'Unknown server error',
        statusCode: rsp.statusCode,
      );
    }

    return jsonBody;
  }

  Future<Map<String, dynamic>> _postWithRetry({
    required String action,
    required Map<String, dynamic> body,
    int maxAttempts = 2,
  }) async {
    ApiException? lastError;
    for (int i = 1; i <= maxAttempts; i++) {
      try {
        return await _postAction(action, body);
      } on ApiException catch (e) {
        lastError = e;
        final isTimeout = e.message.contains('timeout');
        if (!isTimeout || i == maxAttempts) {
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    throw lastError ?? const ApiException('Unknown request failure');
  }

  void dispose() {
    _tokenRefreshTimer?.cancel();
    _client.close(force: true);
  }
}
