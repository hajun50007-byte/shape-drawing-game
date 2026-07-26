import 'dart:ui' show Color;

/// 스테이지 구간별 테마. 대사·캐릭터는 없고 이름과 배경 톤만 다르게 해서
/// 진행감을 준다. (Phase 2 기획 9절)
class StageTheme {
  final String name;

  /// 낙하 구역 배경색. 도형이 선명하게 보이도록 항상 어두운 톤을 쓴다.
  final Color background;

  /// 드로잉 패드 배경색. 낙하 구역과 구분되게 살짝 밝은 톤.
  final Color padBackground;

  const StageTheme({
    required this.name,
    required this.background,
    required this.padBackground,
  });

  /// 1~5단계 구간.
  static const factoryEntrance = StageTheme(
    name: '공장 초입',
    background: Color(0xFF10131A),
    padBackground: Color(0xFF181C26),
  );

  /// 6~10단계 구간.
  static const accelerationLine = StageTheme(
    name: '가속 라인',
    background: Color(0xFF161020),
    padBackground: Color(0xFF221A2E),
  );

  /// 난이도 레벨로 구간 테마를 고른다. 스테이지 데이터에 theme을 직접
  /// 지정하지 않은 RunConfig의 기본값으로 쓰인다.
  static StageTheme forDifficulty(double level) {
    return level <= 5 ? factoryEntrance : accelerationLine;
  }
}
