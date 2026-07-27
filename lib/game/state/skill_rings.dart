import '../model/active_skill.dart';
import '../model/skill_ring.dart';

/// 배경 사각형 링들의 소유권과 등장·퇴장 애니메이션을 관리한다.
///
/// 소유 규칙:
/// - 스킬이 하나만 켜져 있으면 그 스킬이 전체 링을 갖는다.
/// - 이미 하나가 재생 중인데 두 번째가 켜지면, 나중에 켜진 쪽이 홀수 번째
///   링(1,3,5... = index 0,2,4)을 가져가고 기존 스킬은 짝수 번째만 유지한다.
/// - 하나가 꺼지면 그 스킬의 링은 퇴장하고, 남은 스킬이 비워진 링에 대해
///   등장 애니메이션을 다시 트리거해 전체 링으로 재확장한다.
class SkillRingsState {
  SkillRingsState({
    required this.ringCount,
    required this.fadeDuration,
    required this.stagger,
  }) : rings = List.generate(ringCount, SkillRing.new, growable: false);

  final int ringCount;

  /// 링 하나가 나타나거나 사라지는 데 걸리는 시간.
  final Duration fadeDuration;

  /// 외곽 -> 중앙 순서를 만드는 링 간 지연.
  final Duration stagger;

  final List<SkillRing> rings;

  /// 켜진 순서대로의 스킬 목록(마지막이 가장 최근).
  final List<ActiveSkill> _activeOrder = [];

  /// 색 위상 계산용으로 계속 흐르는 시계. 토글과 무관하게 단조 증가하므로
  /// 스킬을 껐다 켜도 색 전환 파도가 끊기지 않는다.
  Duration _clock = Duration.zero;
  Duration get clock => _clock;

  List<ActiveSkill> get activeSkills => List.unmodifiable(_activeOrder);

  bool get hasVisibleRings => rings.any((r) => !r.isIdle);

  void advance(Duration dt) {
    _clock += dt;
    for (final ring in rings) {
      ring.advance(dt);
    }
  }

  /// 활성 스킬 집합이 바뀌었을 때 호출한다.
  void syncActiveSkills(Set<ActiveSkill> active) {
    for (final skill in active) {
      if (!_activeOrder.contains(skill)) _activate(skill);
    }
    for (final skill in List<ActiveSkill>.from(_activeOrder)) {
      if (!active.contains(skill)) _deactivate(skill);
    }
  }

  void _activate(ActiveSkill skill) {
    final hadOthers = _activeOrder.isNotEmpty;
    _activeOrder.add(skill);

    if (!hadOthers) {
      _assign(skill, _allIndices());
      return;
    }
    // 나중에 켜진 스킬이 홀수 번째 링(1-based)을 가져간다.
    _assign(skill, _oddRingIndices());
  }

  void _deactivate(ActiveSkill skill) {
    _activeOrder.remove(skill);

    final released = <int>[];
    for (final ring in rings) {
      if (ring.owner != skill) continue;
      released.add(ring.index);
    }
    _release(released);

    // 남은 스킬이 있으면 비워진 링으로 다시 확장한다(등장 규칙 재사용).
    final remaining = _activeOrder.isEmpty ? null : _activeOrder.last;
    if (remaining != null && released.isNotEmpty) {
      _assign(remaining, released);
    }
  }

  /// [indices] 링을 [skill]이 차지하게 한다. 기존 주인은 퇴장시킨다.
  /// 지연은 외곽부터 순서대로 붙어 바깥에서 안쪽으로 번진다.
  void _assign(ActiveSkill skill, List<int> indices) {
    for (int order = 0; order < indices.length; order++) {
      final ring = rings[indices[order]];
      final delay = stagger * order;
      if (ring.owner != null && ring.owner != skill) {
        ring.release(startDelay: delay, fadeDuration: fadeDuration);
      }
      ring.occupy(
        skill: skill,
        startDelay: delay,
        fadeDuration: fadeDuration,
      );
    }
  }

  void _release(List<int> indices) {
    for (int order = 0; order < indices.length; order++) {
      rings[indices[order]]
          .release(startDelay: stagger * order, fadeDuration: fadeDuration);
    }
  }

  List<int> _allIndices() => [for (int i = 0; i < ringCount; i++) i];

  /// 1-based 홀수 번째 = 0-based 짝수 인덱스.
  List<int> _oddRingIndices() =>
      [for (int i = 0; i < ringCount; i += 2) i];

  void reset() {
    _activeOrder.clear();
    _clock = Duration.zero;
    for (final ring in rings) {
      ring.occupant = null;
      ring.exiting.clear();
    }
  }
}
