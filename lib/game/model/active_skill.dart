/// 플레이어가 쓰는 액티브 스킬 종류.
///
/// 배경 이펙트·시전 버튼·장착 선택 화면이 모두 이 값을 기준으로 색을
/// 가져오므로(ShapeVisuals), 세 곳의 스킬 색이 항상 같이 움직인다.
enum ActiveSkill { doubleClear, layerBreak, timeSlow }
