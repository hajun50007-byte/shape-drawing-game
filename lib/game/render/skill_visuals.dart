import 'package:flutter/material.dart';

import '../model/active_skill.dart';

/// 스킬 하나의 색 묶음.
class SkillPalette {
  const SkillPalette({
    required this.accent,
    required this.bright,
    required this.dim,
  });

  /// 버튼·장착 카드에 쓰는 대표색.
  final Color accent;

  /// 배경 이펙트가 번갈아 표시하는 두 색 중 밝고 쨍한 쪽.
  final Color bright;

  /// 번갈아 표시하는 두 색 중 어둡고 짙은 쪽.
  /// [bright]와 명도·채도 차이를 크게 벌려 대비를 확실히 준다.
  final Color dim;
}

/// 스킬별 색상의 유일한 출처.
///
/// 배경 이펙트, 스킬 발동 버튼, 런 시작 전 장착 선택 화면이 전부 여기서
/// 색을 읽으므로 세 곳의 색이 어긋날 수 없다.
class SkillVisuals {
  static const Map<ActiveSkill, SkillPalette> palettes = {
    // 더블클리어 = 보라
    ActiveSkill.doubleClear: SkillPalette(
      accent: Color(0xFF9C27B0),
      bright: Color(0xFFE99BFF),
      dim: Color(0xFF4A0D63),
    ),
    // 전체 레이어 제거 = 초록(명도를 조금 높게)
    ActiveSkill.layerBreak: SkillPalette(
      accent: Color(0xFF43D67C),
      bright: Color(0xFFA6FFC8),
      dim: Color(0xFF0B5C30),
    ),
    // 타임 슬로우 = 파랑
    ActiveSkill.timeSlow: SkillPalette(
      accent: Color(0xFF2196F3),
      bright: Color(0xFF9BDcFF),
      dim: Color(0xFF0A3D6B),
    ),
  };

  static SkillPalette of(ActiveSkill skill) => palettes[skill]!;

  /// 스킬이 켜져 있을 때 버튼에 쓰는 조금 더 밝은 강조색.
  static Color activeAccentOf(ActiveSkill skill) => of(skill).bright;
}
