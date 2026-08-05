import 'package:flutter/material.dart';

import '../model/active_skill.dart';

/// 스킬별 색상·배경 이펙트 색 계산의 유일한 출처.
///
/// 배경 이펙트에 들어가는 색은 전부 [effectColor]를 거쳐 만들어진다.
/// 하드코딩된 이펙트 색상값은 두지 않는다 — 스킬 고유 색상(Hue)만 아래
/// [accents]에 두고, 명도는 [effectLightness]로 고정한 채 **채도만** 바꿔
/// 대비를 만든다.
class SkillVisuals {
  /// 스킬 고유색. 버튼·장착 카드에 그대로 쓰이고, 배경 이펙트는 여기서
  /// 색상(Hue)만 가져간다.
  static const Map<ActiveSkill, Color> accents = {
    ActiveSkill.doubleClear: Color(0xFF9C27B0), // 보라
    ActiveSkill.layerBreak: Color(0xFF43D67C), // 초록(명도 약간 높게)
    ActiveSkill.timeSlow: Color(0xFF2196F3), // 파랑
  };

  // ---------------- 배경 이펙트 색 상수 ----------------

  /// 배경 이펙트 두 색이 공유하는 명도. 명도는 고정하고 채도만 다르게 해서
  /// 대비를 만든다.
  static const double effectLightness = 0.55;

  /// 스킬 하나만 켜졌을 때 줄무늬 두 그룹이 쓰는 채도.
  static const double stripeHighSaturation = 1.0;
  static const double stripeLowSaturation = 0.40;

  /// 스킬 두 개가 동시에 켜졌을 때 각 스킬을 구분하는 채도.
  static const double dualHighSaturation = 1.0;
  static const double dualLowSaturation = 0.65;

  /// 두 스킬이 동시에 켜졌을 때, 나중에 켜진 스킬(홀수 링)이 높은 채도를
  /// 갖는지. false면 기존 스킬 쪽이 쨍해진다.
  static const bool newerSkillTakesHighSaturation = true;

  static Color accentOf(ActiveSkill skill) => accents[skill]!;

  /// 스킬이 켜져 있을 때 버튼에 쓰는 조금 더 밝은 강조색.
  static Color activeAccentOf(ActiveSkill skill) {
    final hsl = HSLColor.fromColor(accentOf(skill));
    return hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
  }

  /// 배경 이펙트용 색. 스킬의 색상(Hue)은 유지하고, 명도는
  /// [effectLightness]로 고정한 뒤 [saturation]만 바꿔서 만든다.
  ///
  /// 배경 이펙트의 모든 색은 반드시 이 함수를 거친다.
  static Color effectColor(ActiveSkill skill, double saturation) {
    final hsl = HSLColor.fromColor(accentOf(skill));
    return hsl
        .withSaturation(saturation.clamp(0.0, 1.0))
        .withLightness(effectLightness)
        .toColor();
  }
}
