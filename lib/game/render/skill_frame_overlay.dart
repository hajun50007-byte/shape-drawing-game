import 'package:flutter/material.dart';

import '../model/skill_ring.dart';
import '../state/skill_rings.dart';
import 'skill_visuals.dart';

/// 액티브 스킬이 켜져 있는 동안 배경에 깔리는 사각형 연출.
///
/// 화면 가장자리부터 중앙까지 꽉 채운 사각형을 겹쳐 그리며, 안쪽(작은)
/// 사각형이 바깥쪽 위에 올라가 가운데가 제일 앞에 보인다. 인접한 사각형
/// 사이의 간격은 안쪽으로 갈수록 좁아져(ease-out) 색 조정 없이 간격만으로
/// 살짝 튀어나온 입체감을 낸다.
class SkillFrameOverlay extends StatelessWidget {
  const SkillFrameOverlay({super.key, required this.rings});

  final SkillRingsState? rings;

  // ---------------- 튜닝 상수 ----------------

  /// 겹쳐 그릴 사각형 수.
  static const int ringCount = 10;

  /// 가장 안쪽 사각형의 크기(화면 대비). "화면의 약 60%의 10% 정도".
  static const double innermostScale = 0.6 * 0.10;

  /// 간격 곡선. 1이면 등간격이고, 클수록 바깥 간격이 넓고 안쪽이 촘촘해진다.
  static const double easeExponent = 2.4;

  /// 사각형 하나가 나타나거나 사라지는 데 걸리는 시간.
  static const Duration fadeDuration = Duration(milliseconds: 300);

  /// 등장·퇴장이 외곽 -> 중앙으로 번지는 간격.
  static const Duration stagger = Duration(milliseconds: 100);

  /// 두 색을 번갈아 표시하는 주기.
  static const Duration colorInterval = Duration(milliseconds: 300);

  /// 색 전환이 외곽 -> 중앙으로 번지는 간격.
  /// 한 주기 안에 파도가 전체를 훑고 지나가도록 잡았다.
  static const Duration colorStagger =
      Duration(milliseconds: 300 ~/ ringCount);

  /// 배경 연출이라 도형·궤적을 가리지 않도록 전체 불투명도를 낮게 둔다.
  static const double maxOpacity = 0.42;

  @override
  Widget build(BuildContext context) {
    final state = rings;
    if (state == null || !state.hasVisibleRings) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SkillRingPainter(state),
      ),
    );
  }
}

class _SkillRingPainter extends CustomPainter {
  _SkillRingPainter(this.state);

  final SkillRingsState state;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    // index 0(가장 바깥)부터 그리면 안쪽 사각형이 나중에 그려져 위에 온다.
    for (final ring in state.rings) {
      final scale = ringScale(
        index: ring.index,
        ringCount: SkillFrameOverlay.ringCount,
        innermostScale: SkillFrameOverlay.innermostScale,
        easeExponent: SkillFrameOverlay.easeExponent,
      );
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * scale,
        height: size.height * scale,
      );

      for (final anim in ring.visibleAnimations) {
        paint.color = _colorFor(anim, ring.index);
        canvas.drawRect(rect, paint);
      }
    }
  }

  /// 링마다 위상을 어긋나게 줘서 색 전환이 외곽부터 차례로 번지게 한다.
  Color _colorFor(RingAnimation anim, int ringIndex) {
    final palette = SkillVisuals.of(anim.skill);
    final phaseTime = state.clock - SkillFrameOverlay.colorStagger * ringIndex;
    final step = phaseTime.isNegative
        ? 0
        : phaseTime.inMicroseconds ~/
            SkillFrameOverlay.colorInterval.inMicroseconds;
    final base = step.isEven ? palette.bright : palette.dim;
    return base.withValues(
      alpha: (anim.alpha * SkillFrameOverlay.maxOpacity).clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRepaint(covariant _SkillRingPainter oldDelegate) => true;
}
