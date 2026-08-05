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

  /// 등장이 외곽부터 중앙까지 한 바퀴 도는 데 걸리는 시간.
  /// 스킬을 아주 짧게 켰다 꺼도 이 한 사이클은 반드시 완주시킨다.
  Duration get entranceCycle =>
      stagger * (ringCount - 1) + fadeDuration;

  /// 켜진 순서대로의 스킬 목록(마지막이 가장 최근).
  final List<ActiveSkill> _activeOrder = [];

  /// 스킬별 등장 시작 시각(시계 기준). 최소 1사이클 보장에 쓴다.
  final Map<ActiveSkill, Duration> _entranceStartedAt = {};

  /// 등장 1사이클을 채우느라 미뤄둔 퇴장들.
  final List<_PendingExit> _pendingExits = [];

  /// 색 위상 계산용으로 계속 흐르는 시계. 토글과 무관하게 단조 증가하므로
  /// 스킬을 껐다 켜도 색 전환이 끊기지 않는다.
  Duration _clock = Duration.zero;
  Duration get clock => _clock;

  /// 상태가 바뀔 때마다 올라간다. 페인터의 shouldRepaint 비교용.
  int _revision = 0;
  int get revision => _revision;

  List<ActiveSkill> get activeSkills => List.unmodifiable(_activeOrder);

  bool get hasVisibleRings => rings.any((r) => !r.isIdle);

  void advance(Duration dt) {
    if (dt == Duration.zero) return;
    _clock += dt;
    // 보이는 링이 없으면 그릴 것도 없으니 리비전을 올리지 않는다
    // (스킬이 꺼져 있는 동안 불필요한 리페인트를 막는다).
    if (hasVisibleRings) _revision++;

    // 링을 먼저 진행시킨 뒤에 예약된 퇴장을 처리한다. 순서가 반대면
    // 퇴장을 만들 때 등장 진행도가 한 프레임 뒤처진 값으로 읽혀,
    // 큰 dt에서 등장이 덜 끝난 것으로 오판된다.
    for (final ring in rings) {
      ring.advance(dt);
    }
    _tickPendingExits(dt);
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
    // 아직 시작도 안 한 퇴장 예약이 있으면 취소한다(다시 켠 것이므로).
    // 이미 재생 중인 퇴장 애니메이션은 건드리지 않고 끝까지 재생된다.
    final hadPendingExit = _pendingExits.any((p) => p.skill == skill);
    _pendingExits.removeWhere((p) => p.skill == skill);

    final hadOthers = _activeOrder.isNotEmpty;
    _activeOrder.add(skill);
    // 예약 취소로 되살아난 경우엔 원래 등장 시작 시각을 유지해야
    // 1사이클 보장이 무한정 연장되지 않는다.
    if (!hadPendingExit) _entranceStartedAt[skill] = _clock;
    _revision++;

    // 예약만 취소하면 되는 경우(링 주인이 그대로)라면 재배치할 필요가 없다.
    if (hadPendingExit && rings.any((r) => r.owner == skill)) return;

    if (!hadOthers) {
      _assign(skill, _allIndices());
      return;
    }
    // 나중에 켜진 스킬이 홀수 번째 링(1-based)을 가져간다.
    _assign(skill, _oddRingIndices());
  }

  void _deactivate(ActiveSkill skill) {
    _activeOrder.remove(skill);
    _revision++;

    // 등장이 외곽->중앙 한 바퀴를 돌기 전에 꺼졌다면, 남은 시간만큼
    // 퇴장을 미뤄 한 사이클을 반드시 완주시킨다. 미루는 동안에는 링이
    // 주인을 그대로 들고 있어 등장 애니메이션이 계속 재생된다.
    final startedAt = _entranceStartedAt.remove(skill);
    final elapsed = startedAt == null ? entranceCycle : _clock - startedAt;
    final holdFor =
        elapsed >= entranceCycle ? Duration.zero : entranceCycle - elapsed;

    if (holdFor > Duration.zero) {
      _pendingExits.add(_PendingExit(skill: skill, remaining: holdFor));
      return;
    }
    _performExit(skill);
  }

  /// 실제로 링을 비우고, 남은 스킬이 있으면 그 자리로 확장시킨다.
  void _performExit(ActiveSkill skill) {
    final released = <int>[];
    for (final ring in rings) {
      if (ring.owner != skill) continue;
      released.add(ring.index);
    }
    if (released.isEmpty) return;

    _release(released);

    // 남은 스킬이 있으면 비워진 링으로 다시 확장한다(등장 규칙 재사용).
    final remaining = _activeOrder.isEmpty ? null : _activeOrder.last;
    if (remaining != null) _assign(remaining, released);
    _revision++;
  }

  void _tickPendingExits(Duration dt) {
    if (_pendingExits.isEmpty) return;
    final due = <ActiveSkill>[];
    for (final pending in _pendingExits) {
      pending.remaining -= dt;
      if (pending.remaining <= Duration.zero) due.add(pending.skill);
    }
    if (due.isEmpty) return;
    _pendingExits.removeWhere((p) => p.remaining <= Duration.zero);
    for (final skill in due) {
      _performExit(skill);
    }
  }

  /// [indices] 링을 [skill]이 차지하게 한다. 기존 주인은 퇴장시킨다.
  /// 지연은 외곽부터 순서대로 붙어 바깥에서 안쪽으로 번진다.
  void _assign(
    ActiveSkill skill,
    List<int> indices, {
    Duration extraDelay = Duration.zero,
  }) {
    for (int order = 0; order < indices.length; order++) {
      final ring = rings[indices[order]];
      final delay = extraDelay + stagger * order;
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

  void _release(
    List<int> indices, {
    Duration extraDelay = Duration.zero,
  }) {
    for (int order = 0; order < indices.length; order++) {
      rings[indices[order]].release(
        startDelay: extraDelay + stagger * order,
        fadeDuration: fadeDuration,
      );
    }
  }

  List<int> _allIndices() => [for (int i = 0; i < ringCount; i++) i];

  /// 1-based 홀수 번째 = 0-based 짝수 인덱스.
  List<int> _oddRingIndices() =>
      [for (int i = 0; i < ringCount; i += 2) i];

  void reset() {
    _activeOrder.clear();
    _entranceStartedAt.clear();
    _pendingExits.clear();
    _clock = Duration.zero;
    _revision++;
    for (final ring in rings) {
      ring.occupant = null;
      ring.exiting.clear();
    }
  }
}

/// 등장 1사이클을 채우느라 대기 중인 퇴장 예약.
class _PendingExit {
  _PendingExit({required this.skill, required this.remaining});

  final ActiveSkill skill;
  Duration remaining;
}
