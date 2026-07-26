import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/difficulty.dart';
import '../../core/gesture_recognizer.dart' as core;
import '../../core/shape_templates.dart';
import '../model/clear_effect.dart';
import '../model/falling_shape.dart';
import '../render/shape_palette.dart';
import '../render/stroke_pad_painter.dart';

enum GameStatus { playing, cleared, gameOver }

/// 게임 한 판의 모든 상태와 규칙. 위젯/렌더링에 의존하지 않으며 매 프레임
/// [update]로만 시간이 흐른다(내부에 dart:async 타이머를 두지 않는다).
class GameController extends ChangeNotifier {
  GameController({required this.runConfig, math.Random? random})
      : _random = random ?? math.Random() {
    final templates = ShapeTemplates.all;
    _recognizer = core.UnistrokeRecognizer(templates);
    _shapeNames = templates.map((t) => t.name).toList();
    _lives = runConfig.startLives;
    _difficultyLevel = runConfig.minDifficulty;
  }

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

  // ---------------- 외부 노출 상태 ----------------

  final RunConfig runConfig;

  final List<FallingShape> shapes = [];
  final List<core.Point> strokePoints = [];

  /// 클리어 연출. 렌더링만을 위한 상태로, 게임 규칙에는 영향을 주지 않는다.
  final List<ShapeBurst> bursts = [];
  final List<ShapeParticle> particles = [];
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
  bool get isSkillReady => _comboGauge >= skillMinGauge;

  /// 토글로 켜진 상태인지. 게이지가 바닥나면 자동으로 꺼진다.
  bool get isSkillActive => _skillOn && _comboGauge > 0;

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

  /// 쌍둥이 보스를 이미 내보냈는지. 재소환 방지와 클리어 판정에 쓴다.
  bool _twinBossesSpawned = false;

  /// 남은 쪽 보스를 이미 보강했는지.
  bool _twinBossReinforced = false;

  /// 홀드 더블클리어의 두 번째 클리어 예약.
  Duration _doubleClearRemaining = Duration.zero;
  int _doubleClearScore = 0;

  Duration _bossCooldownRemaining = Duration.zero;

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

    final gained = _doubleClearScore * affected.length;
    _score += gained;
    _comboGauge =
        math.min(1.0, _comboGauge + gaugeGainPerClear * affected.length);
    _spawnClearEffects(affected, gained);
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
      // 보스는 난이도와 무관한 고정 속도로 내려온다.
      final speed = shape.isBoss
          ? (runConfig.isRaidMode ? raidBossFallSpeed : bossFallSpeed)
          : params.fallSpeed;
      shape.y += speed * dtSeconds;
    }
    shapes.removeWhere((s) => s.isFinished);
  }

  void _trySpawn(DifficultyParams params) {
    // 스테이지 모드는 보스전 중 일반 도형 스폰을 멈추고, 보스가 정리되면
    // 재개한다. 레이드는 반대로 계속 스폰하되 2층 도형만 내보낸다.
    final bossFight = _hasLivingBoss;
    if (bossFight && !runConfig.isRaidMode) return;

    final aliveCount = shapes.where((s) => !s.isBoss && !s.isCleared).length;
    if (_sinceLastSpawn.inMilliseconds < params.spawnIntervalMs) return;
    if (aliveCount >= params.maxSimultaneousShapes) return;
    _sinceLastSpawn = Duration.zero;
    shapes.add(_createShape(forceMultiLayer: bossFight));
  }

  bool get _hasLivingBoss => shapes.any((s) => s.isBoss && !s.isCleared);

  /// 보스는 지정 난이도 이상에서, 화면에 하나도 없을 때만 등장한다.
  void _trySpawnBoss(Duration dt) {
    final bossFrom = runConfig.bossFromDifficulty;
    if (bossFrom == null || _difficultyLevel < bossFrom) return;

    if (_hasLivingBoss) {
      // 레이드는 주기적으로 다시 등장하므로 더 긴 간격을 쓴다.
      _bossCooldownRemaining =
          runConfig.isRaidMode ? raidBossInterval : bossCooldown;
      return;
    }
    // 쌍둥이 보스는 한 번만 등장한다(둘 다 잡으면 스테이지 클리어).
    if (runConfig.bossKind == BossKind.twin && _twinBossesSpawned) return;
    if (_bossCooldownRemaining > Duration.zero) {
      _bossCooldownRemaining -= dt;
      return;
    }

    if (runConfig.bossKind == BossKind.twin) {
      _spawnTwinBosses();
      _twinBossesSpawned = true;
    } else {
      shapes.add(_createBoss(
        layers: _buildLayerNames(bossLayers),
        sizeFraction: bossSizeFraction,
        xFraction: 0.5,
      ));
    }
  }

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
  }) {
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
    );
  }

  /// 쌍둥이 중 한쪽이 먼저 쓰러지면 남은 쪽의 남은 층수를 늘리고,
  /// 둘 다 쓰러지면 스테이지를 클리어한다.
  void _updateTwinBossState() {
    if (runConfig.bossKind != BossKind.twin || !_twinBossesSpawned) return;

    final living = shapes.where((s) => s.isBoss && !s.isCleared).toList();

    if (living.isEmpty) {
      _status = GameStatus.cleared;
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

  /// 인접한 레이어가 같은 도형이면 중첩이 안 보이므로 연속 중복만 피한다.
  List<String> _buildLayerNames(int count) {
    final names = <String>[];
    for (int i = 0; i < count; i++) {
      String pick;
      do {
        pick = _shapeNames[_random.nextInt(_shapeNames.length)];
      } while (names.isNotEmpty && names.last == pick && _shapeNames.length > 1);
      names.add(pick);
    }
    return names;
  }

  /// 바닥으로 흘려보낸 도형을 처리한다. 게임 오버면 true.
  bool _applyMissedShapes() {
    bool isMissed(FallingShape s) =>
        s.isActionable && s.y - s.size / 2 > _fieldSize.height;

    final missedCount = shapes.where(isMissed).length;
    if (missedCount == 0) return false;

    shapes.removeWhere(isMissed);
    _lives -= missedCount;
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
      final gained = result.score.round() * affected.length;
      _score += gained;
      _comboGauge =
          math.min(1.0, _comboGauge + gaugeGainPerClear * affected.length);
      _spawnClearEffects(affected, gained);
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
      shape.clearedLayers++;
      shape.flashRemaining = clearFlashDuration;
      affected.add(shape);
    }
    return affected;
  }

  /// 콤보 하나에 대한 연출을 만든다.
  /// - 완전히 사라진 도형마다 파티클
  /// - 콤보의 마지막 도형에 흰색 버스트
  /// - 마지막 도형 위치에 합산 점수 팝업
  void _spawnClearEffects(List<FallingShape> affected, int gainedScore) {
    if (affected.isEmpty) return;

    for (final shape in affected) {
      if (shape.isCleared) _spawnParticles(shape);
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
    }

    scorePopups.add(ScorePopup(
      startX: last.x,
      startY: last.y,
      score: gainedScore,
      riseDistance: scorePopupRise,
      duration: scorePopupDuration,
    ));
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
  }

  void _tickEffects(Duration dt) {
    for (final b in bursts) {
      b.advance(dt);
    }
    for (final p in particles) {
      p.advance(dt);
    }
    for (final s in scorePopups) {
      s.advance(dt);
    }
    bursts.removeWhere((e) => e.isDone);
    particles.removeWhere((e) => e.isDone);
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

  /// 스킬을 켜고 끈다. 게이지가 최소치에 못 미치면 켤 수 없다.
  void toggleSkill() {
    if (_skillOn) {
      _skillOn = false;
    } else {
      if (!isSkillReady) return;
      _skillOn = true;
    }
    notifyListeners();
  }

  void restart() {
    shapes.clear();
    strokePoints.clear();
    bursts.clear();
    particles.clear();
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
