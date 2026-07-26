import 'stage_theme.dart';

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

  /// 일반 다층 도형의 레이어 수. 1이면 다층 도형이 없는 스테이지이고,
  /// 다층 도형이 있는 스테이지는 최대 2층까지만 쓴다. 10층짜리 보스는
  /// 이 값과 무관하게 [bossFromDifficulty]로 제어한다.
  final int maxLayers;

  /// 도형이 스폰될 때 다층 도형으로 나올 확률(0~1).
  final double multiLayerChance;

  /// 이 난이도 이상이 되면 보스가 등장한다. null이면 보스 없음.
  /// 스테이지·레이드 모두 같은 규칙으로 동작한다.
  final double? bossFromDifficulty;

  /// 구간 테마. null이면 minDifficulty로부터 자동 선택한다.
  final StageTheme? theme;

  const RunConfig({
    required this.id,
    required this.minDifficulty,
    required this.maxDifficulty,
    required this.duration,
    required this.startLives,
    this.maxLayers = 1,
    this.multiLayerChance = 0,
    this.bossFromDifficulty,
    this.theme,
  });

  bool get isRaid => duration == null;

  StageTheme get resolvedTheme =>
      theme ?? StageTheme.forDifficulty(minDifficulty);
}

/// Phase 1 비교 테스트용 프리셋.
/// 스테이지: 1씩 슬라이딩(1~3/2~4/3~5) — 촘촘하고 부드러운 개별 성장감
/// 레이드: 2씩 점프하는 체크포인트(1~3/3~5/5~7) — 굵직한 압박감, "1/3/5단계"로 라벨링
class RunPresets {
  /// 스테이지 공통 진행 시간. (Phase 2에서 1분 30초 -> 1분으로 단축)
  static const stageDuration = Duration(minutes: 1);

  /// 공통 시작 라이프. (Phase 2에서 3 -> 5로 변경)
  static const startLives = 5;

  static const stage1 = RunConfig(
    id: 'stage_1',
    minDifficulty: 1,
    maxDifficulty: 3,
    duration: stageDuration,
    startLives: startLives,
  );

  static const stage2 = RunConfig(
    id: 'stage_2',
    minDifficulty: 2,
    maxDifficulty: 4,
    duration: stageDuration,
    startLives: startLives,
  );

  static const stage3 = RunConfig(
    id: 'stage_3',
    minDifficulty: 3,
    maxDifficulty: 5,
    duration: stageDuration,
    startLives: startLives,
  );

  /// 다층 도형이 등장하는 4단계.
  static const stage4 = RunConfig(
    id: 'stage_4',
    minDifficulty: 4,
    maxDifficulty: 6,
    duration: stageDuration,
    startLives: startLives,
    maxLayers: 2,
    multiLayerChance: 0.35,
  );

  /// 보스가 처음 등장하는 5단계.
  static const stage5 = RunConfig(
    id: 'stage_5',
    minDifficulty: 5,
    maxDifficulty: 7,
    duration: stageDuration,
    startLives: startLives,
    maxLayers: 2,
    multiLayerChance: 0.35,
    bossFromDifficulty: bossDifficulty,
  );

  /// 다층 도형만 나오는 특별 스테이지(2층, 보스 없음).
  static const specialStage = RunConfig(
    id: 'stage_special',
    minDifficulty: 3,
    maxDifficulty: 5,
    duration: stageDuration,
    startLives: startLives,
    maxLayers: 2,
    multiLayerChance: 0.6,
  );

  /// 보스가 처음 등장하는 난이도. 스테이지·레이드 공통.
  static const double bossDifficulty = 5;

  /// 레이드 체크포인트 구간. UI 라벨은 "1단계/3단계/5단계"로 표시.
  /// 보스 규칙은 스테이지와 동일하게 난이도 5부터 적용된다.
  static const raidCheckpoints = [
    RunConfig(
        id: 'raid_1',
        minDifficulty: 1,
        maxDifficulty: 3,
        duration: null,
        startLives: startLives,
        bossFromDifficulty: bossDifficulty),
    RunConfig(
        id: 'raid_3',
        minDifficulty: 3,
        maxDifficulty: 5,
        duration: null,
        startLives: startLives,
        maxLayers: 2,
        multiLayerChance: 0.3,
        bossFromDifficulty: bossDifficulty),
    RunConfig(
        id: 'raid_5',
        minDifficulty: 5,
        maxDifficulty: 7,
        duration: null,
        startLives: startLives,
        maxLayers: 2,
        multiLayerChance: 0.35,
        bossFromDifficulty: bossDifficulty),
  ];
}
