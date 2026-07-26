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

  /// 레이어 하나를 깰 때마다 차는 콤보 게이지 양.
  static const double gaugeGainPerClear = 0.12;

  /// 스킬을 발동할 수 있는 최소 게이지.
  static const double skillMinGauge = 0.3;

  /// 스킬을 홀드하지 않고 단발로 쓸 때의 명목 소모 속도(초당).
  static const double skillBaseDrainPerSecond = 0.25;

  /// 홀드 중 실제 소모 속도. 명목 소모의 2배라 "지금 쓸까 아낄까"가
  /// 실제 판단이 된다. (Phase 2 기획 7-C절)
  static const double skillHoldDrainPerSecond = skillBaseDrainPerSecond * 2;

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
  double _damageFlash = 0;
  double _comboGauge = 0;
  bool _skillHeld = false;

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
    _tickShapes(dt, dtSeconds, params);
    _trySpawn(params);

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

  void _tickShapes(Duration dt, double dtSeconds, DifficultyParams params) {
    for (final shape in shapes) {
      if (shape.isFlashing) {
        shape.flashRemaining -= dt;
        if (shape.flashRemaining < Duration.zero) {
          shape.flashRemaining = Duration.zero;
        }
        continue;
      }
      if (shape.isCleared) continue;
      shape.y += params.fallSpeed * dtSeconds;
    }
    shapes.removeWhere((s) => s.isFinished);
  }

  void _trySpawn(DifficultyParams params) {
    final aliveCount = shapes.where((s) => !s.isCleared).length;
    if (_sinceLastSpawn.inMilliseconds < params.spawnIntervalMs) return;
    if (aliveCount >= params.maxSimultaneousShapes) return;
    _sinceLastSpawn = Duration.zero;
    shapes.add(_createShape());
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
    final params = DifficultyTable.paramsFor(_difficultyLevel);
    final passed = result.score >= params.recognitionThreshold;

    var clearedCount = passed ? _clearMatching(result.name) : 0;

    // 홀드 더블클리어: 스킬을 누르고 있으면 한 번의 성공으로 두 그룹을 지운다.
    // 방금 지운 도형은 플래시 중이라 제외되므로 다음 그룹이 대상이 된다.
    if (clearedCount > 0 && isSkillActive) {
      final next = _mostUrgentActionable();
      if (next != null) {
        clearedCount += _clearMatching(next.activeName);
      }
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
      _lastMissThreshold = params.recognitionThreshold;
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
    notifyListeners();
  }
}
