import 'package:flutter/material.dart';

import '../state/game_controller.dart';

/// 액티브 스킬이 켜져 있는 동안 배경에 깔리는 사각형 프레임 연출.
///
/// 화면 가장자리부터 중앙까지 여러 겹의 사각형 테두리를 두고, 각 프레임이
/// 스킬 고유의 밝은 두 색을 번갈아 표시한다. 색 전환은 외곽 프레임부터
/// 중앙 프레임 순서로 파도처럼 번지고, 등장할 때도 외곽부터 차례로
/// 페이드인한다.
class SkillFrameOverlay extends StatelessWidget {
  const SkillFrameOverlay({
    super.key,
    required this.kind,
    required this.elapsed,
  });

  final SkillOverlayKind? kind;
  final Duration elapsed;

  // ---------------- 튜닝 상수 ----------------

  /// 겹쳐 그릴 프레임 수.
  static const int frameCount = 10;

  /// 가장 안쪽 프레임의 크기(화면 대비).
  /// "화면의 약 60%의 2% 정도" -> 0.6 * 0.02.
  static const double innermostScale = 0.6 * 0.02;

  /// 프레임 하나가 페이드인하는 데 걸리는 시간.
  static const Duration fadeInDuration = Duration(milliseconds: 300);

  /// 등장이 외곽 -> 중앙으로 번지는 간격.
  static const Duration appearStagger = Duration(milliseconds: 100);

  /// 두 색을 번갈아 표시하는 주기.
  static const Duration colorInterval = Duration(milliseconds: 300);

  /// 색 전환이 외곽 -> 중앙으로 번지는 간격.
  /// 한 주기 안에 파도가 전체를 훑고 지나가도록 잡았다.
  static const Duration colorStagger =
      Duration(milliseconds: 300 ~/ frameCount);

  /// 프레임 테두리 두께.
  static const double strokeWidth = 2.5;

  /// 배경 연출이라 도형·궤적을 가리지 않도록 전체 불투명도를 낮게 둔다.
  static const double maxOpacity = 0.5;

  /// 스킬별 밝고 쨍한 두 색.
  static const Map<SkillOverlayKind, (Color, Color)> palette = {
    SkillOverlayKind.timeSlow: (Color(0xFF29B6F6), Color(0xFF00E5FF)),
    SkillOverlayKind.doubleClear: (Color(0xFFFFD54F), Color(0xFFFFF176)),
    SkillOverlayKind.layerBreak: (Color(0xFFAB47BC), Color(0xFFE040FB)),
  };

  @override
  Widget build(BuildContext context) {
    if (kind == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SkillFramePainter(kind: kind!, elapsed: elapsed),
      ),
    );
  }
}

class _SkillFramePainter extends CustomPainter {
  _SkillFramePainter({required this.kind, required this.elapsed});

  final SkillOverlayKind kind;
  final Duration elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = SkillFrameOverlay.palette[kind]!;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = SkillFrameOverlay.strokeWidth;

    for (int i = 0; i < SkillFrameOverlay.frameCount; i++) {
      // 등장: 외곽(i=0)부터 차례로 나타난다.
      final appearAt = SkillFrameOverlay.appearStagger * i;
      if (elapsed < appearAt) continue;

      final sinceAppear = elapsed - appearAt;
      final fade = (sinceAppear.inMicroseconds /
              SkillFrameOverlay.fadeInDuration.inMicroseconds)
          .clamp(0.0, 1.0);

      // 색 전환: 외곽부터 차례로 번지도록 프레임마다 위상을 어긋나게 준다.
      final phaseShift = SkillFrameOverlay.colorStagger * i;
      final phaseTime = elapsed - phaseShift;
      final step = phaseTime.isNegative
          ? 0
          : phaseTime.inMicroseconds ~/
              SkillFrameOverlay.colorInterval.inMicroseconds;
      final color = step.isEven ? colors.$1 : colors.$2;

      final t = SkillFrameOverlay.frameCount == 1
          ? 0.0
          : i / (SkillFrameOverlay.frameCount - 1);
      final scale = 1.0 + (SkillFrameOverlay.innermostScale - 1.0) * t;

      final rect = Rect.fromCenter(
        center: center,
        width: size.width * scale,
        height: size.height * scale,
      );

      paint.color =
          color.withValues(alpha: fade * SkillFrameOverlay.maxOpacity);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SkillFramePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.elapsed != elapsed;
}
