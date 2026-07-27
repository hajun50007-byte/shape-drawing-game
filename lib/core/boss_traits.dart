import 'dart:math' as math;

/// 보스가 사용하는 스킬 종류.
enum BossSkillType {
  /// 현재 층수에 레이어를 추가해 체력을 회복한다.
  heal,

  /// 정해진 시간 동안 낙하 속도를 올린다.
  haste,
}

/// 보스별 스킬 사용 성향을 담는 설정 객체.
///
/// 보스는 생성 시 [skillWeights]에 따라 **한 가지 스킬만** 부여받고, 그
/// 판이 끝날 때까지 그 스킬만 사용한다(둘을 번갈아 쓰지 않는다).
///
/// 가중치·횟수·간격만 다르게 준 새 인스턴스를 추가하는 것으로 새 보스를
/// 재사용 가능하게 설계했다 — 새 보스 종류를 추가할 때 이 클래스를 다시
/// 만들 필요 없이 `BossTraits(skillWeights: {...})`만 새로 정의하면 된다.
class BossTraits {
  const BossTraits({
    required this.skillWeights,
    this.skillInterval = const Duration(seconds: 2),
    this.postCastCooldown = const Duration(seconds: 3),
    this.telegraphMin = const Duration(milliseconds: 1000),
    this.telegraphMax = const Duration(milliseconds: 1500),
    this.hasteDuration = const Duration(seconds: 3),
    this.hasteSpeedMultiplier = 4.0,
    this.healLayerBonus = 3,
    this.maxSkillUses = 2,
  });

  /// 보스 생성 시 어떤 스킬을 부여할지 정하는 상대 가중치. 값이 클수록
  /// 자주 뽑힌다. 0 이하인 스킬은 아예 후보에서 제외된다.
  final Map<BossSkillType, double> skillWeights;

  /// 스킬을 쓸 수 있게 되기까지의 기본 대기 시간.
  final Duration skillInterval;

  /// 스킬을 한 번 쓰고 난 뒤 추가로 붙는 대기 시간. 연속 시전을 막는다.
  /// 즉 시전 후 다음 시전까지는 [skillInterval] + 이 값만큼 걸린다.
  final Duration postCastCooldown;

  /// 텔레그래프(경고) 지속 시간 범위. 발동마다 이 사이에서 무작위로 고른다.
  final Duration telegraphMin;
  final Duration telegraphMax;

  /// 가속 스킬의 지속 시간.
  final Duration hasteDuration;

  /// 가속 스킬 동안 낙하 속도에 곱해지는 배율.
  final double hasteSpeedMultiplier;

  /// 회복 스킬로 추가되는 레이어 수.
  final int healLayerBonus;

  /// 보스 한 개체가 스킬을 쓸 수 있는 총 횟수.
  final int maxSkillUses;

  /// [telegraphMin]~[telegraphMax] 사이에서 무작위 텔레그래프 시간을 뽑는다.
  Duration rollTelegraphDuration(math.Random random) {
    final range = telegraphMax - telegraphMin;
    if (range <= Duration.zero) return telegraphMin;
    return telegraphMin + range * random.nextDouble();
  }

  /// 가중치에 따라 이 보스가 평생 쓸 스킬 하나를 고른다.
  /// 후보가 없으면 null(스킬을 쓰지 않는 보스).
  BossSkillType? rollAssignedSkill(math.Random random) {
    final candidates =
        skillWeights.entries.where((e) => e.value > 0).toList(growable: false);
    if (candidates.isEmpty) return null;

    final total = candidates.fold<double>(0, (sum, e) => sum + e.value);
    var roll = random.nextDouble() * total;
    for (final entry in candidates) {
      roll -= entry.value;
      if (roll <= 0) return entry.key;
    }
    return candidates.last.key;
  }

  /// 기본 단일 보스(5단계 등)에 쓰는 성향. 회복/가속이 반반으로 뽑힌다.
  static const standard = BossTraits(
    skillWeights: {BossSkillType.heal: 1.0, BossSkillType.haste: 1.0},
  );

  /// 쌍둥이 보스(10단계)에 쓰는 성향. 각자 층수가 얕고 한쪽이 쓰러지면
  /// 남은 쪽이 보강되는 기믹이 이미 있어 회복이 걸릴 확률을 낮춘다.
  static const twin = BossTraits(
    skillWeights: {BossSkillType.heal: 0.6, BossSkillType.haste: 1.4},
  );
}
