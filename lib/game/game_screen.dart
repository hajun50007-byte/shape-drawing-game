import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/difficulty.dart';
import 'model/equipped_skills.dart';
import 'render/falling_field_painter.dart';
import 'render/skill_frame_overlay.dart';
import 'state/game_controller.dart';
import 'state/unlock_state.dart';
import 'widgets/drawing_pad.dart';
import 'widgets/game_hud.dart';
import 'widgets/game_overlays.dart';
import 'widgets/skill_button.dart';

/// 화면 하단 드로잉 패드가 차지하는 비율. 상단은 낙하 도형 전용 표시 영역.
const double _padHeightFraction = 0.33;

/// 게임 화면. 상태와 규칙은 전부 [GameController]에 있고, 이 위젯은
/// 틱 구동과 레이아웃 조립만 담당한다.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.runConfig,
    this.equipped = EquippedSkills.defaultLoadout,
  });

  final RunConfig runConfig;

  /// 로드아웃 화면에서 고른 액티브 스킬 구성.
  final EquippedSkills equipped;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _controller;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  /// 이번 판의 클리어를 이미 기록했는지.
  bool _clearRecorded = false;

  @override
  void initState() {
    super.initState();
    _controller = GameController(
      runConfig: widget.runConfig,
      equipped: widget.equipped,
    );
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
    _recordClearIfNeeded();
  }

  /// 스테이지를 클리어하면 다음 단계가 열리도록 진행도를 기록한다.
  /// 한 판에 한 번만 기록하며, 다시 하기로 재시작하면 다시 기록할 수 있다.
  void _recordClearIfNeeded() {
    final stage = widget.runConfig.stageNumber;
    if (stage == null) return;

    if (_controller.status != GameStatus.cleared) {
      // 재시작하면 다음 클리어를 다시 기록할 수 있게 초기화한다.
      _clearRecorded = false;
      return;
    }
    if (_clearRecorded) return;
    _clearRecorded = true;
    UnlockState.instance.markStageCleared(stage);
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
                  // 배경 연출: 낙하 구역이 투명해 도형 뒤로 비쳐 보이고,
                  // 불투명한 드로잉 패드에는 가려진다.
                  Positioned.fill(
                    child: SkillFrameOverlay(
                      kind: _controller.skillOverlay,
                      elapsed: _controller.skillOverlayElapsed,
                    ),
                  ),
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
                                bursts: _controller.bursts,
                                particles: _controller.particles,
                                sparkles: _controller.sparkles,
                                scorePopups: _controller.scorePopups,
                                burstMaxScale: GameController.burstMaxScale,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.equipped.timeSlow) ...[
                          SkillButton(
                            label: '슬로우',
                            gauge: _controller.timeSlowGauge,
                            isReady: _controller.isTimeSlowReady,
                            isActive: _controller.isTimeSlowActive,
                            onPressed: _controller.activateTimeSlow,
                            accent: Colors.blue,
                            activeAccent: Colors.lightBlueAccent,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.equipped.layerBreak) ...[
                          SkillButton(
                            label: '레이어',
                            gauge: _controller.layerBreakGauge,
                            isReady: _controller.isLayerBreakReady,
                            onPressed: _controller.activateLayerBreak,
                            accent: Colors.cyan,
                            activeAccent: Colors.cyanAccent,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.equipped.doubleClear)
                          SkillButton(
                            label: '2배',
                            activeLabel: '2배 ON',
                            gauge: _controller.comboGauge,
                            isReady: _controller.isSkillReady,
                            isActive: _controller.isSkillActive,
                            onPressed: _controller.toggleSkill,
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: padHeight + 8,
                    child: DebugRecognitionPanel(
                      recognition: _controller.lastRecognition,
                      threshold: _controller.lastAppliedThreshold ??
                          _controller.currentThreshold,
                      baseThreshold: _controller.currentThreshold,
                    ),
                  ),
                  Positioned.fill(
                    child: LowLifeTintOverlay(active: _controller.isLowLife),
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
