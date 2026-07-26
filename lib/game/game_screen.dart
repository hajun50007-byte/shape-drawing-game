import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/difficulty.dart';
import '../core/gesture_recognizer.dart' as core;
import '../core/shape_templates.dart';
import 'falling_shape.dart';
import 'shape_painter.dart';

enum _GameStatus { playing, cleared, gameOver }

/// 레이드(무한 진행) 모드에서 min~max 난이도까지 올라가는 데 걸리는 시간.
/// duration이 없는 RunConfig(RunPresets.raidCheckpoints)에 적용된다.
const Duration _raidDifficultyRampDuration = Duration(minutes: 2);

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.runConfig});

  final RunConfig runConfig;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final core.UnistrokeRecognizer _recognizer;
  late final List<String> _shapeNames;

  final List<FallingShape> _shapes = [];
  final List<core.Point> _strokePoints = [];
  final math.Random _random = math.Random();

  Duration _lastElapsed = Duration.zero;
  Duration _runElapsed = Duration.zero;
  Duration _sinceLastSpawn = Duration.zero;
  int _nextShapeId = 0;

  int _score = 0;
  late int _lives;
  double _difficultyLevel = 1;
  StrokeFeedback? _strokeFeedback;
  _GameStatus _status = _GameStatus.playing;
  Timer? _feedbackClearTimer;

  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    final templates = ShapeTemplates.all;
    _recognizer = core.UnistrokeRecognizer(templates);
    _shapeNames = templates.map((t) => t.name).toList();
    _lives = widget.runConfig.startLives;
    _difficultyLevel = widget.runConfig.minDifficulty;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _feedbackClearTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (_status != _GameStatus.playing || _canvasSize == Size.zero) return;

    setState(() {
      _runElapsed += dt;
      _sinceLastSpawn += dt;
      _difficultyLevel = _computeDifficultyLevel();

      final params = DifficultyTable.paramsFor(_difficultyLevel);

      if (_sinceLastSpawn.inMilliseconds >= params.spawnIntervalMs &&
          _shapes.length < params.maxSimultaneousShapes) {
        _sinceLastSpawn = Duration.zero;
        _spawnShape();
      }

      final dtSeconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
      for (final shape in _shapes) {
        shape.y += params.fallSpeed * dtSeconds;
      }

      final missedCount =
          _shapes.where((s) => s.y - s.size / 2 > _canvasSize.height).length;
      if (missedCount > 0) {
        _shapes.removeWhere((s) => s.y - s.size / 2 > _canvasSize.height);
        _lives -= missedCount;
        if (_lives <= 0) {
          _lives = 0;
          _status = _GameStatus.gameOver;
          return;
        }
      }

      final duration = widget.runConfig.duration;
      if (duration != null && _runElapsed >= duration) {
        _status = _GameStatus.cleared;
      }
    });
  }

  double _computeDifficultyLevel() {
    final config = widget.runConfig;
    final rampMillis = (config.duration ?? _raidDifficultyRampDuration)
        .inMilliseconds
        .toDouble();
    final t = rampMillis == 0
        ? 1.0
        : (_runElapsed.inMilliseconds / rampMillis).clamp(0.0, 1.0);
    return config.minDifficulty +
        (config.maxDifficulty - config.minDifficulty) * t;
  }

  void _spawnShape() {
    const size = 72.0;
    final margin = size;
    final width = _canvasSize.width;
    final x = width <= margin * 2
        ? width / 2
        : margin + _random.nextDouble() * (width - margin * 2);
    _shapes.add(FallingShape(
      id: _nextShapeId++,
      name: _shapeNames[_random.nextInt(_shapeNames.length)],
      x: x,
      y: -size,
      size: size,
    ));
  }

  void _onPanStart(DragStartDetails details) {
    if (_status != _GameStatus.playing) return;
    _feedbackClearTimer?.cancel();
    setState(() {
      _strokeFeedback = null;
      _strokePoints
        ..clear()
        ..add(core.Point(details.localPosition.dx, details.localPosition.dy));
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_status != _GameStatus.playing) return;
    setState(() {
      _strokePoints
          .add(core.Point(details.localPosition.dx, details.localPosition.dy));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_status != _GameStatus.playing || _strokePoints.length < 2) {
      setState(_strokePoints.clear);
      return;
    }

    final result = _recognizer.recognize(_strokePoints);
    final params = DifficultyTable.paramsFor(_difficultyLevel);

    FallingShape? target;
    if (result.score >= params.recognitionThreshold) {
      target = _closestShapeToStroke(result.name);
    }

    setState(() {
      if (target != null) {
        _shapes.remove(target);
        _score += result.score.round();
        _strokeFeedback = StrokeFeedback.hit;
      } else {
        _strokeFeedback = StrokeFeedback.miss;
      }
    });

    _feedbackClearTimer?.cancel();
    _feedbackClearTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _strokePoints.clear();
        _strokeFeedback = null;
      });
    });
  }

  FallingShape? _closestShapeToStroke(String name) {
    final candidates = _shapes.where((s) => s.name == name).toList();
    if (candidates.isEmpty) return null;

    final cx =
        _strokePoints.map((p) => p.x).reduce((a, b) => a + b) / _strokePoints.length;
    final cy =
        _strokePoints.map((p) => p.y).reduce((a, b) => a + b) / _strokePoints.length;

    candidates.sort((a, b) {
      final da = _squaredDistance(a.x, a.y, cx, cy);
      final db = _squaredDistance(b.x, b.y, cx, cy);
      return da.compareTo(db);
    });
    return candidates.first;
  }

  double _squaredDistance(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }

  void _restart() {
    _feedbackClearTimer?.cancel();
    setState(() {
      _shapes.clear();
      _strokePoints.clear();
      _score = 0;
      _lives = widget.runConfig.startLives;
      _difficultyLevel = widget.runConfig.minDifficulty;
      _runElapsed = Duration.zero;
      _sinceLastSpawn = Duration.zero;
      _strokeFeedback = null;
      _status = _GameStatus.playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: GameCanvasPainter(
                        shapes: _shapes,
                        strokePoints: _strokePoints,
                        strokeFeedback: _strokeFeedback,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: _Hud(
                    score: _score,
                    lives: _lives,
                    difficultyLevel: _difficultyLevel,
                    remaining: widget.runConfig.duration == null
                        ? null
                        : widget.runConfig.duration! - _runElapsed,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (_status != _GameStatus.playing)
                  _GameEndOverlay(
                    cleared: _status == _GameStatus.cleared,
                    score: _score,
                    onRetry: _restart,
                    onHome: () => Navigator.of(context).pop(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.score,
    required this.lives,
    required this.difficultyLevel,
    required this.remaining,
  });

  final int score;
  final int lives;
  final double difficultyLevel;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    const style =
        TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('❤️ x$lives', style: style),
        Text('Lv ${difficultyLevel.toStringAsFixed(1)}', style: style),
        Text('점수 $score', style: style),
        if (remaining != null) Text(_formatDuration(remaining!), style: style),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final minutes = clamped.inMinutes;
    final seconds = clamped.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _GameEndOverlay extends StatelessWidget {
  const _GameEndOverlay({
    required this.cleared,
    required this.score,
    required this.onRetry,
    required this.onHome,
  });

  final bool cleared;
  final int score;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cleared ? '스테이지 클리어!' : '게임 오버',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('점수 $score',
                style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(onPressed: onRetry, child: const Text('다시 하기')),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: onHome, child: const Text('홈으로')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
