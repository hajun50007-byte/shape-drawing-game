import 'package:flutter/foundation.dart';

/// 앱이 실행되어 있는 동안만 유지되는 해금 상태.
///
/// 의도적으로 디스크에 저장하지 않는다 — 이 프로젝트에는 아직 로컬 저장소가
/// 없어서(최고기록 저장도 Phase 3 예정) "해금"은 세션 한정으로 구현했다.
/// 앱을 껐다 켜면 다시 잠긴다. 재시작 후에도 유지되려면 저장소 계층이
/// 먼저 필요하다.
class UnlockState extends ChangeNotifier {
  UnlockState._();

  static final UnlockState instance = UnlockState._();

  bool _timeSlowUnlocked = false;
  bool get timeSlowUnlocked => _timeSlowUnlocked;

  /// 5단계 보스를 처음 클리어했을 때 호출된다.
  void unlockTimeSlow() {
    if (_timeSlowUnlocked) return;
    _timeSlowUnlocked = true;
    notifyListeners();
  }

  /// 테스트 전용: 싱글턴 상태를 초기 상태로 되돌린다.
  @visibleForTesting
  void resetForTest() {
    _timeSlowUnlocked = false;
  }
}
