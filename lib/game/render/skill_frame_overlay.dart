import 'package:flutter/material.dart';

import '../model/active_skill.dart';
import '../model/skill_ring.dart';
import '../state/skill_rings.dart';
import 'skill_visuals.dart';

/// 액티브 스킬이 켜져 있는 동안 배경에 깔리는 사각형 연출.
///
/// 각 링은 "겹친 사각형"이 아니라 이웃 링 사이의 **띠(band)** 로 그려진다.
/// 화면 전체 사각형을 10겹 겹쳐 알파 블렌딩하면 픽셀마다 10번씩 덧칠돼
/// 모바일에서 fill rate를 크게 잡아먹는데, 띠로 그리면 한 픽셀이 한 번만
/// 칠해진다. 줄무늬로 보여야 하는 요구와도 맞는다.
///
/// 링 간격은 안쪽으로 갈수록 좁아져(ease-out) 색 조정 없이 입체감을 낸다.
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

  /// 줄무늬 두 그룹의 색이 서로 교대하는 주기.
  static const Duration colorInterval = Duration(milliseconds: 500);

  /// 배경 연출이라 도형·궤적을 가리지 않도록 전체 불투명도를 낮게 둔다.
  static const double maxOpacity = 0.42;

  /// 등장 애니메이션이 외곽부터 중앙까지 한 바퀴 도는 데 걸리는 시간.
  static Duration get entranceCycle =>
      stagger * (ringCount - 1) + fadeDuration;

  @override
  Widget build(BuildContext context) {
    final state = rings;
    if (state == null || !state.hasVisibleRings) {
      return const SizedBox.expand();
    }
    // 배경 이펙트만 따로 리페인트되도록 격리한다. 이게 없으면 낙하 도형·
    // 드로잉 패드·HUD까지 같은 레이어에서 매 프레임 함께 다시 그려진다.
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SkillRingPainter(state, state.revision),
        ),
      ),
    );
  }
}

class _SkillRingPainter extends CustomPainter {
  _SkillRingPainter(this.state, this.revision);

  final SkillRingsState state;

  /// 링 상태가 바뀔 때마다 올라가는 값. 이게 같으면 다시 그릴 필요가 없다.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;
    final active = state.activeSkills;
    final dualMode = active.length >= 2;

    Rect rectFor(int index) {
      final scale = ringScale(
        index: index,
        ringCount: SkillFrameOverlay.ringCount,
        innermostScale: SkillFrameOverlay.innermostScale,
        easeExponent: SkillFrameOverlay.easeExponent,
      );
      return Rect.fromCenter(
        center: center,
        width: size.width * scale,
        height: size.height * scale,
      );
    }

    for (final ring in state.rings) {
      final outer = rectFor(ring.index);
      // 마지막 링은 안쪽에 이웃이 없으니 꽉 찬 사각형으로 그린다.
      final isInnermost = ring.index == SkillFrameOverlay.ringCount - 1;

      for (final anim in ring.visibleAnimations) {
        paint.color = _colorFor(anim, ring.index, active, dualMode);
        if (isInnermost) {
          canvas.drawRect(outer, paint);
        } else {
          // 이웃 링과의 사이만 칠해 오버드로우를 없앤다.
          canvas.drawPath(
            Path()
              ..fillType = PathFillType.evenOdd
              ..addRect(outer)
              ..addRect(rectFor(ring.index + 1)),
            paint,
          );
        }
      }
    }
  }

  /// 색 결정 규칙.
  ///
  /// - 스킬 하나: 홀/짝 링 두 그룹이 서로 다른 채도를 갖고, 주기마다
  ///   그룹끼리 색을 맞바꾼다(줄무늬가 깜빡이는 형태, 순차 파도 아님).
  /// - 스킬 둘: 홀/짝이 이미 스킬 구분에 쓰이므로 교대하지 않고,
  ///   스킬별로 고정된 채도로 구분한다.
  Color _colorFor(
    RingAnimation anim,
    int ringIndex,
    List<ActiveSkill> active,
    bool dualMode,
  ) {
    final double saturation;
    if (dualMode) {
      final isNewer = anim.skill == active.last;
      final newerHigh = SkillVisuals.newerSkillTakesHighSaturation;
      final high = isNewer == newerHigh;
      saturation = high
          ? SkillVisuals.dualHighSaturation
          : SkillVisuals.dualLowSaturation;
    } else {
      // 그룹 단위로 동시에 전환한다(링별 지연 없음).
      final step = state.clock.inMicroseconds ~/
          SkillFrameOverlay.colorInterval.inMicroseconds;
      final swapped = step.isOdd;
      final highGroup = ringIndex.isEven != swapped;
      saturation = highGroup
          ? SkillVisuals.stripeHighSaturation
          : SkillVisuals.stripeLowSaturation;
    }

    return SkillVisuals.effectColor(anim.skill, saturation).withValues(
      alpha: (anim.alpha * SkillFrameOverlay.maxOpacity).clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRepaint(covariant _SkillRingPainter oldDelegate) =>
      oldDelegate.revision != revision;
}
