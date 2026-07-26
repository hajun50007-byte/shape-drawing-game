/// 난이도 1단계당 구체적인 게임플레이 수치.
/// 아래 값은 전부 실측 전 시작 가설값 — Phase 1 플레이테스트하며 조정할 것.
class DifficultyParams {
  final double fallSpeed; // px/sec
  final int spawnIntervalMs;
  final int maxSimultaneousShapes;
  final double recognitionThreshold; // 0~100, 이 점수 이상이면 통과

  const DifficultyParams({
    required this.fallSpeed,
    required this.spawnIntervalMs,
    required this.maxSimultaneousShapes,
    required this.recognitionThreshold,
  });
}

/// 난이도 레벨(1~7) -> 구체 파라미터 매핑.
/// 레벨 사이는 선형 보간(lerp)으로 매끄럽게 연결한다.
class DifficultyTable {
  static const Map<int, DifficultyParams> _anchors = {
    1: DifficultyParams(
        fallSpeed: 80,
        spawnIntervalMs: 1800,
        maxSimultaneousShapes: 2,
        recognitionThreshold: 60),
    3: DifficultyParams(
        fallSpeed: 120,
        spawnIntervalMs: 1400,
        maxSimultaneousShapes: 3,
        recognitionThreshold: 64),
    5: DifficultyParams(
        fallSpeed: 160,
        spawnIntervalMs: 1000,
        maxSimultaneousShapes: 3,
        recognitionThreshold: 68),
    7: DifficultyParams(
        fallSpeed: 200,
        spawnIntervalMs: 800,
        maxSimultaneousShapes: 4,
        recognitionThreshold: 72),
  };

  /// level은 정수/소수 모두 허용 (예: 스테이지 내부에서 시간 경과에 따라
  /// 2.3, 2.7처럼 점진 상승시킬 때 사용)
  static DifficultyParams paramsFor(double level) {
    final keys = _anchors.keys.toList()..sort();
    if (level <= keys.first) return _anchors[keys.first]!;
    if (level >= keys.last) return _anchors[keys.last]!;

    int lower = keys.first;
    int upper = keys.last;
    for (int i = 0; i < keys.length - 1; i++) {
      if (level >= keys[i] && level <= keys[i + 1]) {
        lower = keys[i];
        upper = keys[i + 1];
        break;
      }
    }
    final t = (level - lower) / (upper - lower);
    final a = _anchors[lower]!;
    final b = _anchors[upper]!;
    return DifficultyParams(
      fallSpeed: _lerp(a.fallSpeed, b.fallSpeed, t),
      spawnIntervalMs: _lerp(
              a.spawnIntervalMs.toDouble(), b.spawnIntervalMs.toDouble(), t)
          .round(),
      maxSimultaneousShapes: _lerp(a.maxSimultaneousShapes.toDouble(),
              b.maxSimultaneousShapes.toDouble(), t)
          .round(),
      recognitionThreshold:
          _lerp(a.recognitionThreshold, b.recognitionThreshold, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// 스테이지 모드와 레이드 모드가 공유하는 실행 설정.
/// duration이 null이면 레이드(무한 진행)로 취급한다.
class RunConfig {
  final String id;
  final double minDifficulty;
  final double maxDifficulty;
  final Duration? duration; // null = 레이드
  final int startLives;

  const RunConfig({
    required this.id,
    required this.minDifficulty,
    required this.maxDifficulty,
    required this.duration,
    required this.startLives,
  });

  bool get isRaid => duration == null;
}

/// Phase 1 비교 테스트용 프리셋.
/// 스테이지: 1씩 슬라이딩(1~3/2~4/3~5) — 촘촘하고 부드러운 개별 성장감
/// 레이드: 2씩 점프하는 체크포인트(1~3/3~5/5~7) — 굵직한 압박감, "1/3/5단계"로 라벨링
class RunPresets {
  static const stage1 = RunConfig(
    id: 'stage_1',
    minDifficulty: 1,
    maxDifficulty: 3,
    duration: Duration(minutes: 1, seconds: 30),
    startLives: 3,
  );

  static const stage2 = RunConfig(
    id: 'stage_2',
    minDifficulty: 2,
    maxDifficulty: 4,
    duration: Duration(minutes: 1, seconds: 30),
    startLives: 3,
  );

  static const stage3 = RunConfig(
    id: 'stage_3',
    minDifficulty: 3,
    maxDifficulty: 5,
    duration: Duration(minutes: 1, seconds: 30),
    startLives: 3,
  );

  /// 레이드 체크포인트 구간. UI 라벨은 "1단계/3단계/5단계"로 표시.
  static const raidCheckpoints = [
    RunConfig(
        id: 'raid_1',
        minDifficulty: 1,
        maxDifficulty: 3,
        duration: null,
        startLives: 3),
    RunConfig(
        id: 'raid_3',
        minDifficulty: 3,
        maxDifficulty: 5,
        duration: null,
        startLives: 3),
    RunConfig(
        id: 'raid_5',
        minDifficulty: 5,
        maxDifficulty: 7,
        duration: null,
        startLives: 3),
  ];
}
