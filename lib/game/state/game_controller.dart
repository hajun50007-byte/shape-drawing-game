import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/boss_traits.dart';
import '../../core/difficulty.dart';
import '../../core/gesture_recognizer.dart' as core;
import '../../core/shape_templates.dart';
import '../model/active_skill.dart';
import '../model/clear_effect.dart';
import '../model/equipped_skills.dart';
import '../model/falling_shape.dart';
import '../render/shape_palette.dart';
import '../render/skill_frame_overlay.dart';
import '../render/stroke_pad_painter.dart';
import 'skill_rings.dart';
import 'unlock_state.dart';

enum GameStatus { playing, cleared, gameOver }

/// 게임 한 판의 모든 상태와 규칙. 위젯/렌더링에 의존하지 않으며 매 프레임
/// [update]로만 시간이 흐른다(내부에 dart:async 타이머를 두지 않는다).
class GameController extends ChangeNotifier {
  GameController({
    required this.runConfig,
    math.Random? random,
    this.equipped = EquippedSkills.defaultLoadout,
  }) : _random = random ?? math.Random() {
    final templates = ShapeTemplates.all;
    _recognizer = core.UnistrokeRecognizer(templates);
    _shapeNames = templates.map((t) => t.name).toList();
    _lives = runConfig.startLives;
    _difficultyLevel = runConfig.minDifficulty;
  }

  /// 이 런에 장착된 액티브 스킬. 장착 안 한 스킬은 게이지가 차지 않고
  /// 발동도 되지 않는다.
  final EquippedSkills equipped;

  // ---------------- 튜닝 상수 ----------------

  /// 레이드(무한 진행)에서 min~max 난이도까지 올라가는 데 걸리는 시간.
  static const Duration raidDifficultyRamp = Duration(minutes: 2);

  /// 레이어를 깼을 때의 흰색 플래시 지속 시간.
  static const Duration clearFlashDuration = Duration(milliseconds: 150);

  /// 궤적/판정 색 피드백이 남아 있는 시간.
  static const Duration strokeFeedbackDuration = Duration(milliseconds: 180);

  /// 인식 실패 점수 디버그 표시 시간.
  static const Duration missScoreDuration = Duration(milliseconds: 1200);

  static const double shapeSize = 72.0;

  /// 단일 보스의 레이어 수. 일반 다층 도형(최대 2층)과 구분되는 기준.
  static const int bossLayers = 10;

  /// 쌍둥이 보스 각각의 레이어 수.
  static const int twinBossLayers = 7;

  /// 한쪽 쌍둥이가 먼저 쓰러졌을 때, 남은 쪽의 남은 층수가 늘어나는 값.
  static const int twinBossReinforcedLayers = 10;

  /// 단일 보스 크기(낙하 구역의 짧은 변 대비 비율). 화면의 약 60%.
  static const double bossSizeFraction = 0.6;

  /// 쌍둥이 보스 크기. 단일 보스보다 작다.
  static const double twinBossSizeFraction = 0.38;

  /// 쌍둥이 보스가 내려오는 가로 위치(낙하 구역 너비 대비).
  static const List<double> twinBossXFractions = [0.25, 0.75];

  /// 보스 낙하 속도(px/sec). 난이도와 무관한 고정값이다.
  static const double bossFallSpeed = 18.0;

  /// 레이드 보스 낙하 속도. 스테이지 보스보다 조금 빠르다.
  static const double raidBossFallSpeed = 26.0;

  /// 보스 등장 연출 길이.
  static const Duration bossIntroDuration = Duration(milliseconds: 1200);

  /// 보스 스테이지라도 시작하자마자 보스가 나오지는 않는다.
  /// 이 시간까지는 일반 도형만 내려온다.
  static const Duration bossSpawnDelay = Duration(seconds: 25);

  /// 보스를 놓쳤을 때 깎이는 라이프. 일반 도형(1)보다 훨씬 아프다.
  static const int bossLifeCost = 3;

  /// 보스를 처치한 뒤 다음 보스가 나오기까지의 간격.
  static const Duration bossCooldown = Duration(seconds: 8);

  /// 레이드에서 보스가 주기적으로 다시 등장하기까지의 간격.
  static const Duration raidBossInterval = Duration(seconds: 20);

  /// 레이드에서 일반 도형이 작게 스폰될 확률.
  static const double smallShapeChance = 0.30;

  /// 작은 변형 도형의 크기 배율.
  static const double smallShapeSizeFactor = 0.65;

  // ---------------- 클리어 이펙트 튜닝 ----------------

  static const Duration burstDuration = Duration(milliseconds: 260);
  static const double burstMaxScale = 1.7;

  static const Duration particleDuration = Duration(milliseconds: 260);
  static const int particlesPerShape = 8;
  static const double particleMinSpeed = 130;
  static const double particleMaxSpeed = 260;
  static const double particleSizeFactor = 0.16;

  static const Duration scorePopupDuration = Duration(milliseconds: 700);
  static const double scorePopupRise = 46;

  /// 크러쉬형 반짝임: 도형 주변에 만들 지점 수(최소~최대).
  static const int sparkleMinClusters = 3;
  static const int sparkleMaxClusters = 4;

  /// 각 지점에 배치되는 미니 도형 수(가상 삼각형 꼭짓점).
  static const int sparklePerCluster = 3;

  /// 지점이 흩어지는 반경(도형 크기 대비).
  static const double sparkleSpreadFactor = 0.75;

  /// 가상 삼각형의 반지름(도형 크기 대비).
  static const double sparkleTriangleRadiusFactor = 0.16;

  /// 미니 도형 크기(도형 크기 대비).
  static const double sparkleMiniSizeFactor = 0.13;

  /// 켜짐/꺼짐 전환 간격. 3번 깜빡이므로 수명은 이 값의 6배.
  static const Duration sparkleBlinkInterval = Duration(milliseconds: 100);
  static const int sparkleBlinkCount = 3;

  /// 한 반짝임 안에서 지점끼리 최소로 떨어져야 하는 거리(도형 크기 대비).
  /// 지점이 서로 겹쳐 뭉치면 폭죽이 아니라 얼룩처럼 보인다.
  static const double sparkleMinClusterSpacingFactor = 0.30;

  /// 서로 다른 반짝임끼리 최소로 떨어져야 하는 거리(도형 크기 대비).
  /// 같은 자리에서 여러 도형이 터질 때 연출이 뭉치는 걸 막는다.
  static const double sparkleMinSpacingFactor = 0.85;

  /// 겹침을 피해 위치를 다시 뽑아보는 최대 횟수.
  static const int effectPlacementAttempts = 12;

  /// 여러 이펙트가 겹쳐 화면이 어지러워지지 않도록 동시 존재 개수에
  /// 상한을 둔다. 넘치면 가장 오래된 것부터 제거한다.
  static const int maxConcurrentParticles = particlesPerShape * 4;
  static const int maxConcurrentSparkles = 4;
  static const int maxConcurrentBursts = 4;

  // ---------------- 전체 레이어 제거 스킬 ----------------

  /// 도형을 하나 처치할 때마다 차는 레이어 제거 게이지 양.
  /// 더블클리어 게이지와는 완전히 독립적이다.
  static const double layerBreakGainPerClear = 0.1;

  /// 레이어 하나를 깰 때마다 차는 콤보 게이지 양.
  static const double gaugeGainPerClear = 0.12;

  /// 스킬을 발동할 수 있는 최소 게이지.
  static const double skillMinGauge = 0.3;

  /// 스킬이 켜져 있는 동안의 게이지 소모 속도(초당).
  /// 플레이테스트에서 너무 빨리 닳는다는 피드백을 받아 기존 0.5에서
  /// 절반으로 낮춘 값 — 계속 플레이하며 다시 조정할 튜닝 포인트다.
  static const double skillDrainPerSecond = 0.25;

  /// 홀드 더블클리어에서 두 번째 클리어가 발동하기까지의 딜레이.
  static const Duration doubleClearDelay = Duration(seconds: 1);

  /// 라이프 감소 시 붉은 테두리 플래시가 사라지는 속도(초당).
  static const double damageFlashDecayPerSecond = 2.5;

  // ---------------- 타임 슬로우 스킬 ----------------

  /// 도형을 하나 처치할 때마다 차는 타임 슬로우 게이지 양.
  /// 다른 두 스킬과 완전히 독립적이다.
  static const double timeSlowGainPerClear = 0.08;

  /// 발동 시 낙하 속도 감소 지속 시간.
  static const Duration timeSlowDuration = Duration(milliseconds: 3500);

  /// 발동 중 모든 낙하 속도(보스 포함)에 곱해지는 배율.
  static const double timeSlowFactor = 0.45;

  /// 즉시 발동형인 "전체 레이어 제거"의 배경 연출 표시 시간.
  /// 지속시간이 없는 스킬이라 잠깐만 보여준다.
  static const Duration layerBreakOverlayDuration = Duration(seconds: 1);

  /// 라이프가 이 수 이하로 남으면 배경을 은은하게 붉게 물들인다.
  static const int lowLifeThreshold = 1;

  // ---------------- 외부 노출 상태 ----------------

  final RunConfig runConfig;

  final List<FallingShape> shapes = [];
  final List<core.Point> strokePoints = [];

  /// 클리어 연출. 렌더링만을 위한 상태로, 게임 규칙에는 영향을 주지 않는다.
  final List<ShapeBurst> bursts = [];
  final List<ShapeParticle> particles = [];
  final List<ShapeSparkle> sparkles = [];
  final List<ScorePopup> scorePopups = [];

  GameStatus get status => _status;
  int get score => _score;
  int get lives => _lives;

  /// 내부 난이도는 소수 보간을 유지하고, 화면 표시용으로만 내림한다.
  double get difficultyLevel => _difficultyLevel;
  int get displayLevel => _difficultyLevel.floor();

  Duration get runElapsed => _runElapsed;
  Duration? get remaining =>
      runConfig.duration == null ? null : runConfig.duration! - _runElapsed;

  StrokeFeedback? get strokeFeedback => _strokeFeedback;
  double? get lastMissScore => _lastMissScore;
  double? get lastMissThreshold => _lastMissThreshold;

  /// 마지막으로 인식한 결과. 반지름 비율 페널티 곡선을 튜닝하기 위한 디버그
  /// 오버레이에서 읽는다(릴리즈 빌드에서는 표시되지 않는다).
  core.RecognitionResult? get lastRecognition => _lastRecognition;

  /// 현재 난이도의 기본 통과 기준(도형별 보정 전).
  double get currentThreshold =>
      DifficultyTable.paramsFor(_difficultyLevel).recognitionThreshold;

  /// 마지막 인식에 실제로 적용된 통과 기준(도형별 보정 반영).
  double? get lastAppliedThreshold => _lastAppliedThreshold;

  /// 0~1. 라이프가 깎인 직후 1이 되고 시간에 따라 줄어든다.
  double get damageFlash => _damageFlash;

  /// 0~1 콤보 게이지.
  double get comboGauge => _comboGauge;
  bool get isSkillReady => equipped.doubleClear && _comboGauge >= skillMinGauge;

  /// 토글로 켜진 상태인지. 게이지가 바닥나면 자동으로 꺼진다.
  bool get isSkillActive => _skillOn && _comboGauge > 0;

  /// 0~1 전체 레이어 제거 게이지. 더블클리어 게이지와 독립적이다.
  double get layerBreakGauge => _layerBreakGauge;

  /// 게이지가 가득 찼고 벗겨낼 도형이 화면에 있을 때만 발동할 수 있다.
  bool get isLayerBreakReady =>
      equipped.layerBreak &&
      _layerBreakGauge >= 1 &&
      shapes.any((s) => s.isActionable);

  /// 0~1 타임 슬로우 게이지. 다른 두 스킬과 독립적이다.
  double get timeSlowGauge => _timeSlowGauge;
  bool get isTimeSlowReady => equipped.timeSlow && _timeSlowGauge >= 1;

  /// 낙하 속도 감소가 적용 중인지.
  bool get isTimeSlowActive => _timeSlowRemaining > Duration.zero;

  /// 배경 사각형 링들의 소유권·애니메이션 상태.
  SkillRingsState get skillRings => _skillRings;

  /// 지금 배경 연출을 소유한 스킬들(켜진 순서).
  List<ActiveSkill> get overlaySkills => _skillRings.activeSkills;

  /// 라이프가 얼마 안 남아 배경을 붉게 물들여야 하는지.
  bool get isLowLife =>
      _status == GameStatus.playing && _lives > 0 && _lives <= lowLifeThreshold;

  Size get fieldSize => _fieldSize;

  // ---------------- 내부 상태 ----------------

  final math.Random _random;
  late final core.UnistrokeRecognizer _recognizer;
  late final List<String> _shapeNames;

  GameStatus _status = GameStatus.playing;
  int _score = 0;
  late int _lives;
  double _difficultyLevel = 1;

  Duration _runElapsed = Duration.zero;
  Duration _sinceLastSpawn = Duration.zero;
  Duration _feedbackRemaining = Duration.zero;
  Duration _missScoreRemaining = Duration.zero;
  int _nextShapeId = 0;

  StrokeFeedback? _strokeFeedback;
  double? _lastMissScore;
  double? _lastMissThreshold;
  core.RecognitionResult? _lastRecognition;
  double? _lastAppliedThreshold;
  double _damageFlash = 0;
  double _comboGauge = 0;
  bool _skillOn = false;
  double _layerBreakGauge = 0;
  double _timeSlowGauge = 0;
  Duration _timeSlowRemaining = Duration.zero;

  /// 즉시 발동형 레이어 제거의 연출 잔여 시간.
  Duration _layerBreakOverlayRemaining = Duration.zero;

  final SkillRingsState _skillRings = SkillRingsState(
    ringCount: SkillFrameOverlay.ringCount,
    fadeDuration: SkillFrameOverlay.fadeDuration,
    stagger: SkillFrameOverlay.stagger,
  );

  /// 쌍둥이 보스를 이미 내보냈는지. 재소환 방지와 클리어 판정에 쓴다.
  bool _twinBossesSpawned = false;

  /// 남은 쪽 보스를 이미 보강했는지.
  bool _twinBossReinforced = false;

  /// 홀드 더블클리어의 두 번째 클리어 예약.
  Duration _doubleClearRemaining = Duration.zero;
  int _doubleClearScore = 0;

  Duration _bossCooldownRemaining = Duration.zero;

  /// 지금까지 내보낸 보스 무리 수. alternating에서 순서를 정하는 데 쓴다.
  int _bossSpawnCount = 0;

  Size _fieldSize = Size.zero;

  // ---------------- 루프 ----------------

  void setFieldSize(Size size) => _fieldSize = size;

  void update(Duration dt) {
    if (_status != GameStatus.playing || _fieldSize == Size.zero) return;

    final dtSeconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    _runElapsed += dt;
    _sinceLastSpawn += dt;
    _difficultyLevel = _computeDifficultyLevel();

    final params = DifficultyTable.paramsFor(_difficultyLevel);

    _tickTransientFeedback(dt, dtSeconds);
    _tickEffects(dt);
    _tickSkill(dtSeconds);
    _tickDoubleClear(dt);
    _tickTimeSlow(dt);
    _tickSkillOverlay(dt);
    _tickBossSkills(dt);
    _tickShapes(dt, dtSeconds, params);
    _trySpawn(params);
    _trySpawnBoss(dt);

    if (_applyMissedShapes()) {
      notifyListeners();
      return;
    }

    _updateTwinBossState();
    if (_status != GameStatus.playing) {
      notifyListeners();
      return;
    }

    final duration = runConfig.duration;
    if (duration != null && _runElapsed >= duration) {
      _status = GameStatus.cleared;
    }

    notifyListeners();
  }

  void _tickTransientFeedback(Duration dt, double dtSeconds) {
    if (_feedbackRemaining > Duration.zero) {
      _feedbackRemaining -= dt;
      if (_feedbackRemaining <= Duration.zero) {
        _feedbackRemaining = Duration.zero;
        _strokeFeedback = null;
        strokePoints.clear();
      }
    }
    if (_missScoreRemaining > Duration.zero) {
      _missScoreRemaining -= dt;
      if (_missScoreRemaining <= Duration.zero) {
        _missScoreRemaining = Duration.zero;
        _lastMissScore = null;
        _lastMissThreshold = null;
      }
    }
    if (_damageFlash > 0) {
      _damageFlash =
          math.max(0, _damageFlash - damageFlashDecayPerSecond * dtSeconds);
    }
  }

  void _tickSkill(double dtSeconds) {
    if (!_skillOn) return;
    _comboGauge = math.max(0, _comboGauge - skillDrainPerSecond * dtSeconds);
    if (_comboGauge == 0) _skillOn = false;
  }

  /// 예약된 두 번째 클리어를 딜레이 후에 발동한다.
  void _tickDoubleClear(Duration dt) {
    if (_doubleClearRemaining <= Duration.zero) return;
    _doubleClearRemaining -= dt;
    if (_doubleClearRemaining > Duration.zero) return;

    _doubleClearRemaining = Duration.zero;
    final target = _mostUrgentActionable();
    if (target == null) return;

    final affected = _clearMatching(target.activeName);
    if (affected.isEmpty) return;

    final comboBonus = comboBonusFor(_doubleClearScore, affected.length);
    _score += _doubleClearScore * affected.length + comboBonus;
    _chargeSkillGauges(affected);
    _spawnClearEffects(affected, _doubleClearScore, comboBonus);
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _tickShapes(Duration dt, double dtSeconds, DifficultyParams params) {
    for (final shape in shapes) {
      if (shape.isIntroPlaying) {
        shape.introRemaining -= dt;
        if (shape.introRemaining < Duration.zero) {
          shape.introRemaining = Duration.zero;
        }
        continue;
      }
      if (shape.isFlashing) {
        shape.flashRemaining -= dt;
        if (shape.flashRemaining < Duration.zero) {
          shape.flashRemaining = Duration.zero;
        }
        continue;
      }
      if (shape.isCleared) continue;
      shape.y += _fallSpeedFor(shape, params) * dtSeconds;
    }
    shapes.removeWhere((s) => s.isFinished);
  }

  /// 도형 하나의 현재 낙하 속도. 보스는 난이도와 무관한 고정 속도(가속
  /// 스킬 중이면 그 배율만큼 더 빠름)를, 일반 도형은 난이도 표 값을
  /// 쓰고, 타임 슬로우가 켜져 있으면 종류와 무관하게 전부 느려진다.
  double _fallSpeedFor(FallingShape shape, DifficultyParams params) {
    double speed;
    if (shape.isBoss) {
      final base = runConfig.isRaidMode ? raidBossFallSpeed : bossFallSpeed;
      speed =
          shape.isHasted ? base * runConfig.bossTraits.hasteSpeedMultiplier : base;
    } else {
      speed = params.fallSpeed;
    }
    if (isTimeSlowActive) speed *= timeSlowFactor;
    return speed;
  }

  void _tickTimeSlow(Duration dt) {
    if (_timeSlowRemaining <= Duration.zero) return;
    _timeSlowRemaining -= dt;
    if (_timeSlowRemaining < Duration.zero) _timeSlowRemaining = Duration.zero;
  }

  /// 켜져 있는 스킬 집합을 링 상태에 반영하고 애니메이션을 진행시킨다.
  /// 링 소유권 규칙과 등장·퇴장 연출은 [SkillRingsState]가 담당한다.
  void _tickSkillOverlay(Duration dt) {
    if (_layerBreakOverlayRemaining > Duration.zero) {
      _layerBreakOverlayRemaining -= dt;
      if (_layerBreakOverlayRemaining < Duration.zero) {
        _layerBreakOverlayRemaining = Duration.zero;
      }
    }

    final active = <ActiveSkill>{
      // 레이어 제거는 즉시 발동형이라 정해진 시간 동안만 켜진 것으로 친다.
      if (_layerBreakOverlayRemaining > Duration.zero) ActiveSkill.layerBreak,
      if (isTimeSlowActive) ActiveSkill.timeSlow,
      if (isSkillActive) ActiveSkill.doubleClear,
    };

    _skillRings.syncActiveSkills(active);
    _skillRings.advance(dt);
  }

  /// 살아있는 보스마다 스킬 대기 -> 텔레그래프 -> 발동 사이클을 진행한다.
  /// 보스는 생성 시 부여받은 스킬 하나만, 남은 횟수만큼만 사용한다.
  void _tickBossSkills(Duration dt) {
    final traits = runConfig.bossTraits;
    for (final shape in shapes) {
      if (!shape.isBoss || !shape.isActionable) continue;

      if (shape.hasteRemaining > Duration.zero) {
        shape.hasteRemaining -= dt;
        if (shape.hasteRemaining < Duration.zero) {
          shape.hasteRemaining = Duration.zero;
        }
      }

      if (shape.isTelegraphing) {
        shape.telegraphRemaining -= dt;
        if (shape.telegraphRemaining <= Duration.zero) {
          shape.telegraphRemaining = Duration.zero;
          final skill = shape.telegraphedSkill;
          shape.telegraphedSkill = null;
          if (skill != null) {
            _executeBossSkill(shape, skill, traits);
            shape.skillUsesRemaining--;
          }
          // 연속 시전을 막기 위해 기본 간격에 시전 후 쿨다운을 더한다.
          shape.skillCooldownRemaining =
              traits.skillInterval + traits.postCastCooldown;
        }
        continue;
      }

      // 부여된 스킬이 없거나 사용 횟수를 다 썼으면 더는 아무것도 하지 않는다.
      if (!shape.canUseSkill) continue;

      if (shape.skillCooldownRemaining > Duration.zero) {
        shape.skillCooldownRemaining -= dt;
        // 이번 프레임에 마침 다 닳았으면 바로 아래에서 텔레그래프를 시작한다.
        if (shape.skillCooldownRemaining > Duration.zero) continue;
      }

      shape.telegraphedSkill = shape.assignedSkill;
      shape.telegraphRemaining = traits.rollTelegraphDuration(_random);
    }
  }

  void _executeBossSkill(
    FallingShape boss,
    BossSkillType skill,
    BossTraits traits,
  ) {
    switch (skill) {
      case BossSkillType.heal:
        // 이미 벗겨낸 진행은 그대로 두고, 남은 레이어 "바깥"(배열 끝,
        // 다음에 클리어할 지점)에 새 레이어를 덧붙여 "층수 +N"을
        // 구현한다. 새로 붙은 층부터 다시 벗겨내야 한다.
        final currentRemaining = boss.layers.sublist(0, boss.remainingLayers);
        boss.setRemainingLayers([
          ...currentRemaining,
          ..._buildLayerNames(traits.healLayerBonus),
        ]);
      case BossSkillType.haste:
        boss.hasteRemaining = traits.hasteDuration;
    }
  }

  void _trySpawn(DifficultyParams params) {
    // 스테이지 모드는 보스전 중 일반 도형 스폰을 멈추고, 보스가 정리되면
    // 재개한다. 레이드는 반대로 계속 스폰하되 2층 도형만 내보낸다.
    final bossFight = _hasLivingBoss;
    if (bossFight && !runConfig.isRaidMode) return;

    final aliveCount = shapes.where((s) => !s.isBoss && !s.isCleared).length;
    if (_sinceLastSpawn.inMilliseconds < params.spawnIntervalMs) return;
    if (aliveCount >= effectiveMaxSimultaneousShapes(params)) return;
    _sinceLastSpawn = Duration.zero;
    shapes.add(_createShape(forceMultiLayer: bossFight));
  }

  bool get _hasLivingBoss => shapes.any((s) => s.isBoss && !s.isCleared);

  /// 난이도 표의 동시 등장 상한에 런 설정의 배율을 적용한 값.
  int effectiveMaxSimultaneousShapes(DifficultyParams params) {
    return (params.maxSimultaneousShapes * runConfig.simultaneousShapesScale)
        .round();
  }

  /// 보스는 지정 난이도 이상에서, 등장 유예 시간이 지난 뒤,
  /// 화면에 하나도 없을 때만 등장한다.
  void _trySpawnBoss(Duration dt) {
    final bossFrom = runConfig.bossFromDifficulty;
    if (bossFrom == null || _difficultyLevel < bossFrom) return;
    // 시작하자마자 보스가 나오지 않도록 초반은 일반 도형만 흘려보낸다.
    if (_runElapsed < bossSpawnDelay) return;

    if (_hasLivingBoss) {
      // 레이드는 주기적으로 다시 등장하므로 더 긴 간격을 쓴다.
      _bossCooldownRemaining =
          runConfig.isRaidMode ? raidBossInterval : bossCooldown;
      return;
    }
    // 스테이지의 쌍둥이 보스는 한 번만 등장한다(둘 다 잡으면 클리어).
    if (runConfig.bossKind == BossKind.twin && _twinBossesSpawned) return;
    if (_bossCooldownRemaining > Duration.zero) {
      _bossCooldownRemaining -= dt;
      return;
    }

    if (_nextBossIsTwin) {
      _spawnTwinBosses();
      _twinBossesSpawned = true;
      _twinBossReinforced = false;
    } else {
      shapes.add(_createBoss(
        layers: _buildLayerNames(bossLayers),
        sizeFraction: bossSizeFraction,
        xFraction: 0.5,
      ));
    }
    _bossSpawnCount++;
  }

  /// 이번에 내보낼 보스가 쌍둥이인지.
  /// alternating은 단일 -> 쌍둥이 -> 단일 ... 순으로 번갈아 나온다.
  bool get _nextBossIsTwin => switch (runConfig.bossKind) {
        BossKind.twin => true,
        BossKind.single => false,
        BossKind.alternating => _bossSpawnCount.isOdd,
      };

  /// 좌우에서 동시에 내려오는 쌍둥이 보스. 두 보스는 서로 다른 도형
  /// 시퀀스를 갖는다.
  void _spawnTwinBosses() {
    final first = _buildLayerNames(twinBossLayers);
    var second = _buildLayerNames(twinBossLayers);
    for (int attempt = 0; attempt < 8; attempt++) {
      if (!_sameSequence(first, second)) break;
      second = _buildLayerNames(twinBossLayers);
    }

    for (int i = 0; i < twinBossXFractions.length; i++) {
      shapes.add(_createBoss(
        layers: i == 0 ? first : second,
        sizeFraction: twinBossSizeFraction,
        xFraction: twinBossXFractions[i],
        // 스킬은 단일 보스 형태만 쓴다.
        canUseSkills: false,
      ));
    }
  }

  static bool _sameSequence(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  FallingShape _createBoss({
    required List<String> layers,
    required double sizeFraction,
    required double xFraction,
    bool canUseSkills = true,
  }) {
    final traits = runConfig.bossTraits;
    final size = math.min(_fieldSize.width, _fieldSize.height) * sizeFraction;
    return FallingShape(
      id: _nextShapeId++,
      layers: layers,
      // 좌우 이동 없이 지정된 가로 위치에서 수직으로만 하강한다.
      x: _fieldSize.width * xFraction,
      y: -size / 2,
      size: size,
      color: ShapePalette.multiLayerColor,
      isBoss: true,
      introDuration: bossIntroDuration,
    )
      // 생성 시 스킬 하나를 무작위로 부여받고, 그 스킬만 정해진 횟수만큼 쓴다.
      // 쌍둥이 보스는 스킬을 쓰지 않는다(단일 보스 형태 전용).
      ..assignedSkill =
          canUseSkills ? traits.rollAssignedSkill(_random) : null
      ..skillUsesRemaining = canUseSkills ? traits.maxSkillUses : 0
      // 등장하자마자 쓰지 않도록 첫 판단까지 스킬 간격만큼 대기시킨다.
      ..skillCooldownRemaining = traits.skillInterval;
  }

  /// 쌍둥이 중 한쪽이 먼저 쓰러지면 남은 쪽의 남은 층수를 늘리고,
  /// 스테이지의 쌍둥이전이면 둘 다 쓰러졌을 때 클리어 처리한다.
  ///
  /// 레이드의 번갈아 등장하는 쌍둥이는 보강만 적용하고, 잡았다고 런이
  /// 끝나지는 않는다(무한 진행이므로).
  void _updateTwinBossState() {
    if (!_twinBossesSpawned) return;

    final living = shapes.where((s) => s.isBoss && !s.isCleared).toList();

    if (living.isEmpty) {
      if (runConfig.bossKind == BossKind.twin) {
        _status = GameStatus.cleared;
      } else {
        // 레이드: 다음 보스를 다시 뽑을 수 있게 상태만 되돌린다.
        _twinBossesSpawned = false;
        _twinBossReinforced = false;
      }
      return;
    }

    if (living.length == 1 && !_twinBossReinforced) {
      _twinBossReinforced = true;
      final survivor = living.first;
      // 이미 벗겨낸 층은 그대로 두고 남은 층만 다시 채운다.
      survivor.setRemainingLayers(_buildLayerNames(twinBossReinforcedLayers));
    }
  }

  FallingShape _createShape({bool forceMultiLayer = false}) {
    final margin = shapeSize;
    final width = _fieldSize.width;
    final x = width <= margin * 2
        ? width / 2
        : margin + _random.nextDouble() * (width - margin * 2);

    final isMultiLayer = forceMultiLayer ||
        (runConfig.maxLayers > 1 &&
            _random.nextDouble() < runConfig.multiLayerChance);
    final layerCount =
        isMultiLayer ? math.max(2, runConfig.maxLayers) : 1;

    // 레이드에서는 일정 확률로 평소보다 작은 도형이 섞여 나온다.
    // 인식기는 크기를 정규화하므로 판정 로직은 그대로 재사용된다.
    final isSmall =
        runConfig.isRaidMode && _random.nextDouble() < smallShapeChance;
    final size = shapeSize * (isSmall ? smallShapeSizeFactor : 1.0);

    return FallingShape(
      id: _nextShapeId++,
      layers: _buildLayerNames(layerCount),
      x: x,
      y: -size,
      size: size,
      color: ShapePalette.forShape(
        isMultiLayer: isMultiLayer,
        random: _random,
      ),
    );
  }

  /// 레이어 이름을 무작위로 뽑는다. 같은 도형끼리의 조합(예: 사각형 안에
  /// 사각형)도 그대로 허용한다 — 크기 차이로 중첩이 충분히 구분된다.
  List<String> _buildLayerNames(int count) {
    return List.generate(
      count,
      (_) => _shapeNames[_random.nextInt(_shapeNames.length)],
    );
  }

  /// 바닥으로 흘려보낸 도형을 처리한다. 게임 오버면 true.
  bool _applyMissedShapes() {
    bool isMissed(FallingShape s) =>
        s.isActionable && s.y - s.size / 2 > _fieldSize.height;

    final missed = shapes.where(isMissed).toList();
    if (missed.isEmpty) return false;

    // 보스를 놓치면 일반 도형보다 훨씬 크게 깎인다.
    final lifeCost = missed.fold<int>(
      0,
      (sum, s) => sum + (s.isBoss ? bossLifeCost : 1),
    );

    shapes.removeWhere(isMissed);
    _lives -= lifeCost;
    _onLifeLost();

    if (_lives <= 0) {
      _lives = 0;
      _status = GameStatus.gameOver;
      return true;
    }
    return false;
  }

  /// 실패 피드백: 붉은 테두리 플래시 + 성공과 구분되는 진동 패턴.
  void _onLifeLost() {
    _damageFlash = 1.0;
    // 성공은 lightImpact, 실패는 heavyImpact로 촉각을 명확히 구분한다.
    HapticFeedback.heavyImpact();
  }

  double _computeDifficultyLevel() {
    final rampMillis =
        (runConfig.duration ?? raidDifficultyRamp).inMilliseconds.toDouble();
    final t = rampMillis == 0
        ? 1.0
        : (_runElapsed.inMilliseconds / rampMillis).clamp(0.0, 1.0);
    return runConfig.minDifficulty +
        (runConfig.maxDifficulty - runConfig.minDifficulty) * t;
  }

  // ---------------- 입력 ----------------

  void startStroke(double x, double y) {
    if (_status != GameStatus.playing) return;
    _feedbackRemaining = Duration.zero;
    _strokeFeedback = null;
    strokePoints
      ..clear()
      ..add(core.Point(x, y));
    notifyListeners();
  }

  void extendStroke(double x, double y) {
    if (_status != GameStatus.playing) return;
    strokePoints.add(core.Point(x, y));
    notifyListeners();
  }

  void endStroke() {
    if (_status != GameStatus.playing || strokePoints.length < 2) {
      strokePoints.clear();
      notifyListeners();
      return;
    }

    final result = _recognizer.recognize(strokePoints);
    _lastRecognition = result;
    // 통과 기준은 인식된 도형에 따라 보정된다(예: 사각형은 -8점).
    final threshold = DifficultyTable.thresholdFor(_difficultyLevel, result.name);
    _lastAppliedThreshold = threshold;
    final passed = result.score >= threshold;

    final affected =
        passed ? _clearMatching(result.name) : const <FallingShape>[];

    // 더블클리어: 스킬이 켜져 있으면 한 번의 성공이 잠시 뒤 두 번째
    // 클리어로 이어진다. 즉시가 아니라 딜레이를 둬서 연출이 겹치지 않게 한다.
    if (affected.isNotEmpty && isSkillActive) {
      _doubleClearRemaining = doubleClearDelay;
      _doubleClearScore = result.score.round();
    }

    if (affected.isNotEmpty) {
      final perShape = result.score.round();
      final comboBonus = comboBonusFor(perShape, affected.length);
      _score += perShape * affected.length + comboBonus;
      _chargeSkillGauges(affected);
      _spawnClearEffects(affected, perShape, comboBonus);
      _strokeFeedback = StrokeFeedback.hit;
      _lastMissScore = null;
      _lastMissThreshold = null;
      _missScoreRemaining = Duration.zero;
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      _strokeFeedback = StrokeFeedback.miss;
      _lastMissScore = result.score;
      _lastMissThreshold = threshold;
      _missScoreRemaining = missScoreDuration;
    }

    _feedbackRemaining = strokeFeedbackDuration;
    notifyListeners();
  }

  /// 활성 레이어 이름이 [name]인 모든 도형의 레이어를 한 겹씩 벗기고,
  /// 영향을 받은 도형들을 반환한다.
  List<FallingShape> _clearMatching(String name) {
    final affected = <FallingShape>[];
    for (final shape in shapes) {
      if (!shape.isActionable || shape.activeName != name) continue;
      _peelLayer(shape);
      affected.add(shape);
    }
    return affected;
  }

  /// 도형 하나의 바깥 레이어를 한 겹 벗기고 플래시를 건다. 보스가 이걸로
  /// 완전히 쓰러지면 해당 훅을 실행한다.
  void _peelLayer(FallingShape shape) {
    shape.clearedLayers++;
    shape.flashRemaining = clearFlashDuration;
    if (shape.isBoss && shape.isCleared) _onBossCleared(shape);
  }

  /// 보스가 쓰러졌을 때의 훅. 지금은 5단계 보스 클리어 시 타임 슬로우
  /// 해금에만 쓰인다.
  void _onBossCleared(FallingShape boss) {
    if (runConfig.id == RunPresets.stage5.id) {
      UnlockState.instance.unlockTimeSlow();
    }
  }

  /// 동시 클리어 보너스 점수.
  ///
  /// 주의: 이전 버전에는 콤보 보너스 항목 자체가 없었고 총점이
  /// (도형당 점수 × 개수)였다. 콤보 팝업을 별도로 띄우려면 보너스가
  /// 실재해야 해서 여기서 처음 정의한다. 2개 이상 동시 클리어 시
  /// 기본 획득분과 같은 양을 보너스로 더한다.
  static int comboBonusFor(int perShapeScore, int clearedCount) {
    if (clearedCount < 2) return 0;
    return perShapeScore * clearedCount;
  }

  /// 콤보 하나에 대한 연출을 만든다.
  /// - 완전히 사라진 도형마다 파티클 또는 반짝임(둘 중 무작위)
  /// - 콤보의 마지막 도형에 흰색 버스트
  /// - 도형마다 개별 점수 팝업, 콤보면 보너스 팝업을 하나 더
  void _spawnClearEffects(
    List<FallingShape> affected,
    int perShapeScore,
    int comboBonus,
  ) {
    if (affected.isEmpty) return;

    for (final shape in affected) {
      if (shape.isCleared) _spawnDestroyEffect(shape);
      // 각 도형 위치에서 개별 점수가 떠오른다.
      scorePopups.add(ScorePopup(
        startX: shape.x,
        startY: shape.y,
        score: perShapeScore,
        riseDistance: scorePopupRise,
        duration: scorePopupDuration,
      ));
    }

    final last = affected.last;
    if (last.isCleared) {
      bursts.add(ShapeBurst(
        shapeName: last.layers.first,
        x: last.x,
        y: last.y,
        size: last.size,
        duration: burstDuration,
      ));
      _capList(bursts, maxConcurrentBursts);
    }

    if (comboBonus > 0) {
      // 콤보 보너스는 마지막 도형 위치에 한 번만 강조해서 띄운다.
      scorePopups.add(ScorePopup(
        startX: last.x,
        startY: last.y - scorePopupRise * 0.6,
        score: comboBonus,
        label: 'COMBO',
        riseDistance: scorePopupRise * 1.4,
        duration: scorePopupDuration,
      ));
    }
  }

  /// 도형이 완전히 사라질 때의 연출. 파티클과 크러쉬형 반짝임 중
  /// 하나를 무작위로 골라 재생한다.
  void _spawnDestroyEffect(FallingShape shape) {
    if (_random.nextBool()) {
      _spawnParticles(shape);
    } else {
      _spawnSparkle(shape);
    }
  }

  /// 도형 반경 주변 3~4개 지점에, 각 지점마다 미니 도형 3개를 가상
  /// 삼각형 꼭짓점 위치로 배치한다.
  ///
  /// 겹쳐 보이는 걸 줄이기 위해 두 단계로 간격을 둔다:
  /// 1. 이미 떠 있는 다른 반짝임과 너무 가까우면 중심을 밀어낸다.
  /// 2. 한 반짝임 안에서도 지점끼리 최소 간격을 두고 뽑는다.
  void _spawnSparkle(FallingShape shape) {
    final clusterCount = sparkleMinClusters +
        _random.nextInt(sparkleMaxClusters - sparkleMinClusters + 1);
    final spread = shape.size * sparkleSpreadFactor;
    final triangleRadius = shape.size * sparkleTriangleRadiusFactor;
    final minClusterGap = shape.size * sparkleMinClusterSpacingFactor;

    final center = _separatedSparkleCenter(shape);
    final centerX = center.$1;
    final centerY = center.$2;

    final clusterCenters = <(double, double)>[];
    for (int c = 0; c < clusterCount; c++) {
      (double, double)? placed;
      for (int attempt = 0; attempt < effectPlacementAttempts; attempt++) {
        final angle = _random.nextDouble() * 2 * math.pi;
        final distance = spread * (0.35 + _random.nextDouble() * 0.65);
        final candidate = (
          centerX + math.cos(angle) * distance,
          centerY + math.sin(angle) * distance,
        );
        placed = candidate;
        final tooClose = clusterCenters.any((existing) =>
            _distance(existing.$1, existing.$2, candidate.$1, candidate.$2) <
            minClusterGap);
        if (!tooClose) break;
      }
      clusterCenters.add(placed!);
    }

    final clusters = <List<SparklePoint>>[];
    for (final (cx, cy) in clusterCenters) {
      // 가상 삼각형의 세 꼭짓점.
      final rotation = _random.nextDouble() * 2 * math.pi;
      clusters.add([
        for (int v = 0; v < sparklePerCluster; v++)
          SparklePoint(
            cx + math.cos(rotation + 2 * math.pi * v / sparklePerCluster) *
                triangleRadius,
            cy + math.sin(rotation + 2 * math.pi * v / sparklePerCluster) *
                triangleRadius,
          ),
      ]);
    }

    sparkles.add(ShapeSparkle(
      shapeName: shape.layers.first,
      centerX: centerX,
      centerY: centerY,
      miniSize: shape.size * sparkleMiniSizeFactor,
      clusters: clusters,
      blinkInterval: sparkleBlinkInterval,
      blinkCount: sparkleBlinkCount,
      // 켜짐/꺼짐 한 쌍이 한 번의 깜빡임이므로 2배.
      duration: sparkleBlinkInterval * (sparkleBlinkCount * 2),
    ));
    _capList(sparkles, maxConcurrentSparkles);
  }

  /// 이미 떠 있는 반짝임들과 최소 간격을 확보한 중심 좌표를 고른다.
  ///
  /// 한 번만 밀어내면 A에서 멀어지다 B에 붙어버릴 수 있어, 더 밀어낼
  /// 대상이 없을 때까지 반복해서 정리한다(반짝임 수가 상한으로 묶여
  /// 있어 몇 번이면 수렴한다).
  (double, double) _separatedSparkleCenter(FallingShape shape) {
    final minGap = shape.size * sparkleMinSpacingFactor;
    // 딱 최소 거리에 맞추면 부동소수점 오차로 다시 "가깝다"고 판정될 수
    // 있어 아주 살짝 더 밀어낸다.
    final targetGap = minGap * 1.001;

    var x = shape.x;
    var y = shape.y;

    for (int pass = 0; pass < effectPlacementAttempts; pass++) {
      var adjusted = false;
      for (final other in sparkles) {
        final gap = _distance(x, y, other.centerX, other.centerY);
        if (gap >= minGap) continue;
        adjusted = true;

        if (gap < 1e-6) {
          // 정확히 같은 자리면 방향이 없으니 임의 방향으로 밀어낸다.
          final angle = _random.nextDouble() * 2 * math.pi;
          x += math.cos(angle) * targetGap;
          y += math.sin(angle) * targetGap;
          continue;
        }
        // 겹치는 만큼만 바깥으로 밀어낸다.
        final push = (targetGap - gap) / gap;
        x += (x - other.centerX) * push;
        y += (y - other.centerY) * push;
      }
      if (!adjusted) break;
    }
    return (x, y);
  }

  static double _distance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _spawnParticles(FallingShape shape) {
    final name = shape.layers.first;
    for (int i = 0; i < particlesPerShape; i++) {
      // 사방으로 고르게 퍼지도록 기본 각도에 약간의 흔들림을 준다.
      final angle = (2 * math.pi * i / particlesPerShape) +
          (_random.nextDouble() - 0.5) * 0.6;
      final speed = particleMinSpeed +
          _random.nextDouble() * (particleMaxSpeed - particleMinSpeed);
      particles.add(ShapeParticle(
        shapeName: name,
        startX: shape.x,
        startY: shape.y,
        size: shape.size * particleSizeFactor,
        velocityX: math.cos(angle) * speed,
        velocityY: math.sin(angle) * speed,
        duration: particleDuration,
      ));
    }
    _capList(particles, maxConcurrentParticles);
  }

  /// 이펙트 목록이 상한을 넘으면 가장 오래된 것부터 제거한다.
  void _capList<T>(List<T> list, int max) {
    while (list.length > max) {
      list.removeAt(0);
    }
  }

  void _tickEffects(Duration dt) {
    for (final b in bursts) {
      b.advance(dt);
    }
    for (final p in particles) {
      p.advance(dt);
    }
    for (final s in sparkles) {
      s.advance(dt);
    }
    for (final s in scorePopups) {
      s.advance(dt);
    }
    bursts.removeWhere((e) => e.isDone);
    particles.removeWhere((e) => e.isDone);
    sparkles.removeWhere((e) => e.isDone);
    scorePopups.removeWhere((e) => e.isDone);
  }

  /// 화면 아래(놓치기 직전)에 가장 가까운, 아직 살아있는 도형.
  FallingShape? _mostUrgentActionable() {
    FallingShape? best;
    for (final shape in shapes) {
      if (!shape.isActionable) continue;
      if (best == null || shape.y > best.y) best = shape;
    }
    return best;
  }

  /// 장착된 스킬들의 게이지를 한 번에 채운다. 더블클리어는 레이어를 벗긴
  /// 횟수(맞은 도형 수)로, 레이어 제거·타임 슬로우는 완전히 처치한
  /// 도형 수로 찬다.
  void _chargeSkillGauges(List<FallingShape> affected) {
    if (affected.isEmpty) return;
    if (equipped.doubleClear) {
      _comboGauge =
          math.min(1.0, _comboGauge + gaugeGainPerClear * affected.length);
    }
    if (equipped.layerBreak) _addLayerBreakCharge(affected);
    if (equipped.timeSlow) _addTimeSlowCharge(affected);
  }

  /// 도형을 처치한 만큼 레이어 제거 게이지를 채운다.
  /// 레이어만 벗겨진 경우는 제외하고 완전히 사라진 도형만 센다.
  void _addLayerBreakCharge(List<FallingShape> affected) {
    final destroyed = affected.where((s) => s.isCleared).length;
    if (destroyed == 0) return;
    _layerBreakGauge =
        _snapToFull(_layerBreakGauge + layerBreakGainPerClear * destroyed);
  }

  /// 도형을 처치한 만큼 타임 슬로우 게이지를 채운다.
  void _addTimeSlowCharge(List<FallingShape> affected) {
    final destroyed = affected.where((s) => s.isCleared).length;
    if (destroyed == 0) return;
    _timeSlowGauge =
        _snapToFull(_timeSlowGauge + timeSlowGainPerClear * destroyed);
  }

  /// 0.1 같은 소수를 여러 번 더하면 부동소수점 오차로 1.0에 살짝 못
  /// 미쳐 게이지가 영영 가득 차지 않는 문제를 막는다.
  double _snapToFull(double value) {
    final clamped = math.min(1.0, value);
    return clamped > 1 - 1e-9 ? 1.0 : clamped;
  }

  /// 전체 레이어 제거 스킬. 화면의 모든 도형에서 현재 바깥 레이어를
  /// 한 겹씩 벗긴다. 1층 도형은 그대로 클리어되고, 다층·보스 도형은
  /// 다음 레이어가 노출된다.
  void activateLayerBreak() {
    if (!equipped.layerBreak) return;
    if (!isLayerBreakReady) return;

    final affected = <FallingShape>[];
    for (final shape in shapes) {
      if (!shape.isActionable) continue;
      _peelLayer(shape);
      affected.add(shape);
    }
    if (affected.isEmpty) return;

    _layerBreakGauge = 0;
    _layerBreakOverlayRemaining = layerBreakOverlayDuration;

    // 점수는 현재 난이도의 통과 기준을 획득 점수로 삼는다.
    final perShape = currentThreshold.round();
    final comboBonus = comboBonusFor(perShape, affected.length);
    _score += perShape * affected.length + comboBonus;
    _spawnClearEffects(affected, perShape, comboBonus);

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    notifyListeners();
  }

  /// 스킬을 켜고 끈다. 게이지가 최소치에 못 미치면 켤 수 없다.
  void toggleSkill() {
    if (!equipped.doubleClear) return;
    if (_skillOn) {
      _skillOn = false;
    } else {
      if (!isSkillReady) return;
      _skillOn = true;
    }
    notifyListeners();
  }

  /// 타임 슬로우 스킬. 발동 시 게이지를 전부 쓰고 일정 시간 화면의 모든
  /// 낙하 속도가 느려진다.
  void activateTimeSlow() {
    if (!isTimeSlowReady) return;
    _timeSlowGauge = 0;
    _timeSlowRemaining = timeSlowDuration;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    notifyListeners();
  }

  void restart() {
    shapes.clear();
    strokePoints.clear();
    bursts.clear();
    particles.clear();
    sparkles.clear();
    scorePopups.clear();
    _status = GameStatus.playing;
    _score = 0;
    _lives = runConfig.startLives;
    _difficultyLevel = runConfig.minDifficulty;
    _runElapsed = Duration.zero;
    _sinceLastSpawn = Duration.zero;
    _feedbackRemaining = Duration.zero;
    _missScoreRemaining = Duration.zero;
    _strokeFeedback = null;
    _lastMissScore = null;
    _lastMissThreshold = null;
    _damageFlash = 0;
    _comboGauge = 0;
    _skillOn = false;
    _layerBreakGauge = 0;
    _timeSlowGauge = 0;
    _timeSlowRemaining = Duration.zero;
    _layerBreakOverlayRemaining = Duration.zero;
    _skillRings.reset();
    _twinBossesSpawned = false;
    _twinBossReinforced = false;
    _lastRecognition = null;
    _lastAppliedThreshold = null;
    _doubleClearRemaining = Duration.zero;
    _doubleClearScore = 0;
    _bossCooldownRemaining = Duration.zero;
    notifyListeners();
  }
}
