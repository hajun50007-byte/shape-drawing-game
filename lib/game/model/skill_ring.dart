import 'dart:math' as math;

import 'active_skill.dart';

/// 링 하나에서 재생되는 애니메이션 하나(등장 또는 퇴장).
///
/// 등장과 퇴장이 각각 독립된 인스턴스라, 스킬을 빠르게 껐다 켜도 앞서
/// 재생 중이던 퇴장이 잘리거나 되감기지 않고 끝까지 재생된다.
class RingAnimation {
  RingAnimation({
    required this.skill,
    required this.startDelay,
    required this.fadeDuration,
    required this.exiting,
    this.startProgress = 0,
  });

  final ActiveSkill skill;

  /// 외곽 -> 중앙 순서를 만들기 위한 시작 지연.
  final Duration startDelay;

  /// 페이드에 걸리는 시간.
  final Duration fadeDuration;

  /// true면 사라지는 중(1 -> 0), false면 나타나는 중(0 -> 1).
  final bool exiting;

  /// 이미 진행된 것으로 치고 시작할 페이드 진행도.
  /// 반쯤 나타난 링이 사라질 때 그 지점에서 이어지도록 쓴다.
  final double startProgress;

  Duration elapsed = Duration.zero;

  void advance(Duration dt) => elapsed += dt;

  /// 지연을 기다린 뒤 진행되는 페이드 진행도 0~1.
  double get _progress {
    if (fadeDuration <= Duration.zero) return 1;
    final active = elapsed - startDelay;
    final advanced = active <= Duration.zero
        ? 0.0
        : active.inMicroseconds / fadeDuration.inMicroseconds;
    return (startProgress + advanced).clamp(0.0, 1.0);
  }

  /// 지금 프레임에서의 불투명도.
  double get alpha => exiting ? 1 - _progress : _progress;

  /// 퇴장이 끝나 목록에서 지워도 되는 상태인지.
  /// 등장은 끝나도 그대로 남아 링을 계속 채운다.
  bool get isFinished => exiting && _progress >= 1;
}

/// 화면 가장자리부터 중앙까지 깔리는 사각형 링 하나.
/// index 0이 가장 바깥이고, 커질수록 안쪽이다.
class SkillRing {
  SkillRing(this.index);

  final int index;

  /// 지금 이 링을 차지한 스킬의 등장 애니메이션(끝나면 그대로 유지된다).
  RingAnimation? occupant;

  /// 재생이 끝날 때까지 남겨두는 퇴장 애니메이션들.
  /// 빠른 토글로 여러 개가 겹칠 수 있어 목록으로 둔다.
  final List<RingAnimation> exiting = [];

  ActiveSkill? get owner => occupant?.skill;

  void advance(Duration dt) {
    occupant?.advance(dt);
    for (final anim in exiting) {
      anim.advance(dt);
    }
    exiting.removeWhere((a) => a.isFinished);
  }

  /// 현재 주인을 퇴장시킨다. 진행 중이던 등장은 그 시점의 불투명도에서
  /// 이어서 사라지도록 남은 만큼만 페이드아웃한다.
  void release({required Duration startDelay, required Duration fadeDuration}) {
    final current = occupant;
    if (current == null) return;
    occupant = null;

    exiting.add(RingAnimation(
      skill: current.skill,
      startDelay: startDelay,
      fadeDuration: fadeDuration,
      exiting: true,
      // 반쯤 나타난 상태였다면 그만큼 이미 사라진 것으로 쳐서 튀지 않게 한다.
      startProgress: (1 - current.alpha).clamp(0.0, 1.0),
    ));
  }

  /// 새 스킬을 이 링에 등장시킨다.
  /// 같은 스킬이 이미 나타나는 중이었다면 그 지점에서 이어 붙여
  /// 다시 0부터 깜빡이지 않게 한다.
  void occupy({
    required ActiveSkill skill,
    required Duration startDelay,
    required Duration fadeDuration,
  }) {
    final previous = occupant;
    final carried = (previous != null && previous.skill == skill)
        ? previous.alpha.clamp(0.0, 1.0)
        : 0.0;

    occupant = RingAnimation(
      skill: skill,
      startDelay: carried > 0 ? Duration.zero : startDelay,
      fadeDuration: fadeDuration,
      exiting: false,
      startProgress: carried,
    );
  }

  /// 그려야 할 애니메이션들(퇴장 먼저, 등장이 그 위에).
  Iterable<RingAnimation> get visibleAnimations sync* {
    for (final anim in exiting) {
      if (anim.alpha > 0) yield anim;
    }
    final current = occupant;
    if (current != null && current.alpha > 0) yield current;
  }

  bool get isIdle => occupant == null && exiting.isEmpty;
}

/// 링 크기 계산. 바깥에서 안쪽으로 갈수록 인접 링 사이 간격이 좁아지도록
/// ease-out 곡선을 적용한다(색 조정 없이 간격만으로 입체감을 낸다).
double ringScale({
  required int index,
  required int ringCount,
  required double innermostScale,
  required double easeExponent,
}) {
  if (ringCount <= 1) return innermostScale;
  final t = index / (ringCount - 1);
  // ease-out: 처음엔 빠르게 줄어들고(바깥 간격 넓음) 뒤로 갈수록 완만해진다
  // (안쪽 간격 좁음).
  final eased = 1 - math.pow(1 - t, easeExponent).toDouble();
  return 1.0 + (innermostScale - 1.0) * eased;
}
