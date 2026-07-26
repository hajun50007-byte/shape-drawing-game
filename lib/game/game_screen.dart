import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/difficulty.dart';
import 'render/falling_field_painter.dart';
import 'state/game_controller.dart';
import 'widgets/drawing_pad.dart';
import 'widgets/game_hud.dart';
import 'widgets/game_overlays.dart';
import 'widgets/skill_button.dart';

/// 화면 하단 드로잉 패드가 차지하는 비율. 상단은 낙하 도형 전용 표시 영역.
const double _padHeightFraction = 0.33;

/// 게임 화면. 상태와 규칙은 전부 [GameController]에 있고, 이 위젯은
/// 틱 구동과 레이아웃 조립만 담당한다.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.runConfig});

  final RunConfig runConfig;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _controller;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = GameController(runConfig: widget.runConfig);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    _controller.update(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.runConfig.resolvedTheme;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padHeight = constraints.maxHeight * _padHeightFraction;
            final fieldHeight = constraints.maxHeight - padHeight;
            _controller.setFieldSize(Size(width, fieldHeight));

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        // 상단: 낙하 도형 표시 전용. GestureDetector가 없으므로
                        // 이 영역의 터치는 드로잉으로 처리되지 않는다.
                        ClipRect(
                          child: SizedBox(
                            width: width,
                            height: fieldHeight,
                            child: CustomPaint(
                              painter: FallingFieldPainter(
                                shapes: _controller.shapes,
                                background: theme.background,
                              ),
                            ),
                          ),
                        ),
                        DrawingPad(
                          width: width,
                          height: padHeight,
                          background: theme.padBackground,
                          strokePoints: _controller.strokePoints,
                          feedback: _controller.strokeFeedback,
                          onStart: (p) => _controller.startStroke(p.dx, p.dy),
                          onUpdate: (p) => _controller.extendStroke(p.dx, p.dy),
                          onEnd: _controller.endStroke,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: GameHud(
                      score: _controller.score,
                      lives: _controller.lives,
                      displayLevel: _controller.displayLevel,
                      themeName: theme.name,
                      remaining: _controller.remaining,
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
                  Positioned(
                    right: 16,
                    bottom: padHeight + 16,
                    child: SkillButton(
                      gauge: _controller.comboGauge,
                      isReady: _controller.isSkillReady,
                      isActive: _controller.isSkillActive,
                      onHoldChanged: _controller.setSkillHeld,
                    ),
                  ),
                  if (_controller.lastMissScore != null)
                    Positioned(
                      top: fieldHeight - 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: DebugScoreBadge(
                          score: _controller.lastMissScore!,
                          threshold: _controller.lastMissThreshold ?? 0,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: DamageFlashOverlay(
                      intensity: _controller.damageFlash,
                    ),
                  ),
                  if (_controller.status != GameStatus.playing)
                    Positioned.fill(
                      child: GameEndOverlay(
                        cleared: _controller.status == GameStatus.cleared,
                        score: _controller.score,
                        onRetry: _controller.restart,
                        onHome: () => Navigator.of(context).pop(),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
