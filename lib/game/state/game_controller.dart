import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/difficulty.dart';
import '../../core/gesture_recognizer.dart' as core;
import '../../core/shape_templates.dart';
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

  /// 보스 도형의 레이어 수. 일반 다층 도형(최대 2층)과 구분되는 기준.
  static const int bossLayers = 10;

  /// 보스 크기(낙하 구역의 짧은 변 대비 비율). 화면의 약 60%를 차지한다.
  static const double bossSizeFraction = 0.6;

  /// 보스 낙하 속도 배율. 일반 도형보다 훨씬 느리게 내려온다.
  static const double bossFallSpeedFactor = 0.12;

  /// 보스 등장 연출 길이.
  static const Duration bossIntroDuration = Duration(milliseconds: 1200);

  /// 보스를 처치한 뒤 다음 보스가 나오기까지의 간격.
  static const Duration bossCooldown = Duration(seconds: 8);

  /// 레이어 하나를 깰 때마다 차는 콤보 게이지 양.
  static const double gaugeGainPerClear = 0.12;

  /// 스킬을 발동할 수 있는 최소 게이지.
  static const double skillMinGauge = 0.3;

  /// 홀드 중 게이지 소모 속도(초당).
  /// 플레이테스트에서 너무 빨리 닳는다는 피드백을 받아 기존 0.5에서
  /// 절반으로 낮춘 값 — 계속 플레이하며 다시 조정할 튜닝 포인트다.
  static const double skillHoldDrainPerSecond = 0.25;

  /// 홀드 더블클리어에서 두 번째 클리어가 발동하기까지의 딜레이.
  static const Duration doubleClearDelay = Duration(seconds: 1);

  /// 라이프 감소 시 붉은 테두리 플래시가 사라지는 속도(초당).
  static const double damageFlashDecayPerSecond = 2.5;

  // ---------------- 외부 노출 상태 ----------------

  final RunConfig runConfig;

  final List<FallingShape> shapes = [];
  final List<core.Point> strokePoints = [];

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
  bool get isSkillActive => _skillHeld && _comboGauge > 0;

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
  bool _skillHeld = false;

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
    _tickSkill(dtSeconds);
    _tickDoubleClear(dt);
    _tickShapes(dt, dtSeconds, params);
    _trySpawn(params);
    _trySpawnBoss(dt);

    if (_applyMissedShapes()) {
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
    if (!_skillHeld) return;
    _comboGauge =
        math.max(0, _comboGauge - skillHoldDrainPerSecond * dtSeconds);
    if (_comboGauge == 0) _skillHeld = false;
  }

  /// 예약된 두 번째 클리어를 딜레이 후에 발동한다.
  void _tickDoubleClear(Duration dt) {
    if (_doubleClearRemaining <= Duration.zero) return;
    _doubleClearRemaining -= dt;
    if (_doubleClearRemaining > Duration.zero) return;

    _doubleClearRemaining = Duration.zero;
    final target = _mostUrgentActionable();
    if (target == null) return;

    final cleared = _clearMatching(target.activeName);
    if (cleared == 0) return;
    _score += _doubleClearScore * cleared;
    _comboGauge = math.min(1.0, _comboGauge + gaugeGainPerClear * cleared);
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
      final speed = shape.isBoss
          ? params.fallSpeed * bossFallSpeedFactor
          : params.fallSpeed;
      shape.y += speed * dtSeconds;
    }
    shapes.removeWhere((s) => s.isFinished);
  }

  void _trySpawn(DifficultyParams params) {
    // 보스는 별도 규칙으로 관리하므로 일반 도형 정원에서 제외한다.
    final aliveCount =
        shapes.where((s) => !s.isBoss && !s.isCleared).length;
    if (_sinceLastSpawn.inMilliseconds < params.spawnIntervalMs) return;
    if (aliveCount >= params.maxSimultaneousShapes) return;
    _sinceLastSpawn = Duration.zero;
    shapes.add(_createShape());
  }

  /// 보스는 지정 난이도 이상에서, 화면에 하나도 없을 때만 등장한다.
  void _trySpawnBoss(Duration dt) {
    final bossFrom = runConfig.bossFromDifficulty;
    if (bossFrom == null || _difficultyLevel < bossFrom) return;

    if (shapes.any((s) => s.isBoss)) {
      _bossCooldownRemaining = bossCooldown;
      return;
    }
    if (_bossCooldownRemaining > Duration.zero) {
      _bossCooldownRemaining -= dt;
      return;
    }
    shapes.add(_createBoss());
  }

  FallingShape _createBoss() {
    final size =
        math.min(_fieldSize.width, _fieldSize.height) * bossSizeFraction;
    return FallingShape(
      id: _nextShapeId++,
      layers: _buildLayerNames(bossLayers),
      // 화면 정중앙에서 내려온다.
      x: _fieldSize.width / 2,
      y: -size / 2,
      size: size,
      color: ShapePalette.multiLayerColor,
      isBoss: true,
      introDuration: bossIntroDuration,
    );
  }

  FallingShape _createShape() {
    final margin = shapeSize;
    final width = _fieldSize.width;
    final x = width <= margin * 2
        ? width / 2
        : margin + _random.nextDouble() * (width - margin * 2);

    final isMultiLayer = runConfig.maxLayers > 1 &&
        _random.nextDouble() < runConfig.multiLayerChance;
    final layerCount = isMultiLayer ? runConfig.maxLayers : 1;

    return FallingShape(
      id: _nextShapeId++,
      layers: _buildLayerNames(layerCount),
      x: x,
      y: -shapeSize,
      size: shapeSize,
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

    final clearedCount = passed ? _clearMatching(result.name) : 0;

    // 홀드 더블클리어: 스킬을 누르고 있으면 한 번의 성공이 잠시 뒤 두 번째
    // 클리어로 이어진다. 즉시가 아니라 딜레이를 둬서 연출이 겹치지 않게 한다.
    if (clearedCount > 0 && isSkillActive) {
      _doubleClearRemaining = doubleClearDelay;
      _doubleClearScore = result.score.round();
    }

    if (clearedCount > 0) {
      _score += result.score.round() * clearedCount;
      _comboGauge =
          math.min(1.0, _comboGauge + gaugeGainPerClear * clearedCount);
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

  /// 활성 레이어 이름이 [name]인 모든 도형의 레이어를 한 겹씩 벗긴다.
  int _clearMatching(String name) {
    var count = 0;
    for (final shape in shapes) {
      if (!shape.isActionable || shape.activeName != name) continue;
      shape.clearedLayers++;
      shape.flashRemaining = clearFlashDuration;
      count++;
    }
    return count;
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

  void setSkillHeld(bool held) {
    if (held && !isSkillReady) return;
    if (_skillHeld == held) return;
    _skillHeld = held;
    notifyListeners();
  }

  void restart() {
    shapes.clear();
    strokePoints.clear();
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
    _skillHeld = false;
    _lastRecognition = null;
    _lastAppliedThreshold = null;
    _doubleClearRemaining = Duration.zero;
    _doubleClearScore = 0;
    _bossCooldownRemaining = Duration.zero;
    notifyListeners();
  }
}
