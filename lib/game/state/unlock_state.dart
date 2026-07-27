import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 해금·진행도 상태. shared_preferences에 저장되어 앱을 껐다 켜도 유지된다.
///
/// - 스테이지는 1단계부터 순서대로만 열린다(N단계를 깨야 N+1이 열림).
/// - 타임 슬로우 스킬은 5단계 보스를 잡으면 열린다.
class UnlockState extends ChangeNotifier {
  UnlockState._();

  static final UnlockState instance = UnlockState._();

  static const String _keyHighestClearedStage = 'highest_cleared_stage';
  static const String _keyTimeSlowUnlocked = 'time_slow_unlocked';

  /// 저장소를 읽지 못했을 때도 게임은 돌아가야 하므로, 로드 실패는
  /// 기본값(아무것도 해금 안 됨)으로 조용히 넘어간다.
  SharedPreferences? _prefs;

  int _highestClearedStage = 0;
  bool _timeSlowUnlocked = false;

  /// 지금까지 클리어한 가장 높은 단계. 0이면 아직 아무것도 못 깬 상태.
  int get highestClearedStage => _highestClearedStage;

  bool get timeSlowUnlocked => _timeSlowUnlocked;

  /// 앱 시작 시 한 번 호출한다.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _highestClearedStage = prefs.getInt(_keyHighestClearedStage) ?? 0;
      _timeSlowUnlocked = prefs.getBool(_keyTimeSlowUnlocked) ?? false;
      notifyListeners();
    } catch (_) {
      // 저장소를 못 쓰는 환경(예: 플랫폼 채널 없음)에서는 기본값으로 진행.
    }
  }

  /// [stage]단계를 지금 플레이할 수 있는지. 1단계는 항상 열려 있고,
  /// 그 뒤로는 직전 단계를 깨야 열린다.
  bool isStageUnlocked(int stage) => stage <= _highestClearedStage + 1;

  /// [stage]단계를 클리어했다고 기록한다. 이미 더 높은 단계를 깼다면
  /// 되돌리지 않는다(낮은 단계 재플레이로 진행도가 깎이지 않게).
  Future<void> markStageCleared(int stage) async {
    if (stage <= _highestClearedStage) return;
    _highestClearedStage = stage;
    notifyListeners();
    await _persistInt(_keyHighestClearedStage, stage);
  }

  /// 5단계 보스를 처음 클리어했을 때 호출된다.
  void unlockTimeSlow() {
    if (_timeSlowUnlocked) return;
    _timeSlowUnlocked = true;
    notifyListeners();
    // 저장 실패해도 이번 세션 동안은 해금 상태가 유지된다.
    unawaited(_persistBool(_keyTimeSlowUnlocked, true));
  }

  Future<void> _persistInt(String key, int value) async {
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setInt(key, value);
    } catch (_) {
      // 저장 실패는 무시 — 진행은 메모리 상태로 계속된다.
    }
  }

  Future<void> _persistBool(String key, bool value) async {
    try {
      await (_prefs ??= await SharedPreferences.getInstance())
          .setBool(key, value);
    } catch (_) {
      // 저장 실패는 무시 — 진행은 메모리 상태로 계속된다.
    }
  }

  /// 테스트 전용: 싱글턴 상태를 초기 상태로 되돌린다.
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _highestClearedStage = 0;
    _timeSlowUnlocked = false;
  }

  /// 테스트 전용: 저장소를 거치지 않고 진행도를 직접 세팅한다.
  @visibleForTesting
  void setHighestClearedStageForTest(int stage) {
    _highestClearedStage = stage;
    notifyListeners();
  }
}
