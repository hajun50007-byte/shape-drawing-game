/// 런(스테이지/레이드) 시작 전 장착한 액티브 스킬 구성.
/// 장착하지 않은 스킬은 그 런 동안 게이지가 차지 않고 버튼도 뜨지 않는다.
class EquippedSkills {
  const EquippedSkills({
    required this.doubleClear,
    required this.layerBreak,
    required this.timeSlow,
  });

  final bool doubleClear;
  final bool layerBreak;
  final bool timeSlow;

  /// 총 장착 개수. 로드아웃 화면에서 "정확히 2개"를 강제하는 데 쓴다.
  int get equippedCount =>
      (doubleClear ? 1 : 0) + (layerBreak ? 1 : 0) + (timeSlow ? 1 : 0);

  /// 타임 슬로우가 아직 해금되지 않았을 때의 기본 장착(둘뿐이라 선택의
  /// 여지가 없다).
  static const defaultLoadout =
      EquippedSkills(doubleClear: true, layerBreak: true, timeSlow: false);
}
