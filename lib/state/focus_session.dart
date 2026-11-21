import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const focusSessionStorageKey = 'growup.focus-session.v1';

/// Clock-based countdown so backgrounding the app never stalls the session.
class FocusSession {
  FocusSession({int minutes = 2})
    : duration = Duration(minutes: minutes),
      remaining = Duration(minutes: minutes);

  Duration duration;
  Duration remaining;
  DateTime? deadline;
  bool started = false;

  bool get running => deadline != null;
  Duration remainingAt(DateTime now) {
    final value = deadline?.difference(now) ?? remaining;
    if (value.isNegative) return Duration.zero;
    return value > duration ? duration : value;
  }

  void selectMinutes(int minutes) {
    if (started) return;
    duration = Duration(minutes: minutes);
    remaining = duration;
  }

  void start(DateTime now) {
    if (running || remaining == Duration.zero) return;
    started = true;
    deadline = now.add(remaining);
  }

  void pause(DateTime now) {
    remaining = remainingAt(now);
    deadline = null;
  }

  void reset() {
    deadline = null;
    remaining = duration;
    started = false;
  }

  Map<String, Object?> toJson() => {
    'durationMs': duration.inMilliseconds,
    'remainingMs': remaining.inMilliseconds,
    'deadline': deadline?.toUtc().toIso8601String(),
    'started': started,
  };

  static FocusSession fromJson(Map<String, dynamic> json) {
    final duration = json['durationMs'];
    final remaining = json['remainingMs'];
    final started = json['started'];
    final rawDeadline = json['deadline'];
    final deadline = rawDeadline is String
        ? DateTime.tryParse(rawDeadline)
        : null;
    if (duration is! int ||
        ![2, 5, 10, 25].map((m) => m * 60000).contains(duration) ||
        remaining is! int ||
        remaining < 0 ||
        remaining > duration ||
        started is! bool ||
        (rawDeadline != null && deadline == null) ||
        (!started && deadline != null)) {
      throw const FormatException('집중 시간 자료를 읽을 수 없어요.');
    }
    return FocusSession(minutes: duration ~/ 60000)
      ..remaining = Duration(milliseconds: remaining)
      ..started = started
      ..deadline = deadline;
  }
}

class FocusSessionRepository {
  FocusSessionRepository(this.preferences);
  final SharedPreferencesAsync preferences;

  Future<FocusSession?> read(String goalId) async {
    final raw = await preferences.getString(focusSessionStorageKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['goalId'] != goalId) return null;
    return FocusSession.fromJson(json);
  }

  Future<void> write(String goalId, FocusSession session) =>
      preferences.setString(
        focusSessionStorageKey,
        jsonEncode({'goalId': goalId, ...session.toJson()}),
      );

  Future<void> clear() => preferences.remove(focusSessionStorageKey);

  Future<void> clearForGoal(String goalId) async {
    final raw = await preferences.getString(focusSessionStorageKey);
    if (raw == null) return;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      await clear();
      return;
    }
    if (json is! Map || json['goalId'] is! String || json['goalId'] == goalId) {
      await clear();
    }
  }
}
