import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 도형 색상 규칙. (Phase 2 기획 3절 / 9절)
/// - 일반 도형: 채도 낮은 빨/초/파 계열 중 랜덤 (장식용, 신호 아님)
/// - 다층 도형: 채도 높은 보라 고정 (특수 도형임을 한눈에 구분)
/// - 배경과 명도·채도가 모두 비슷하면 보색으로 반전해 항상 구분되게 한다.
class ShapePalette {
  /// 일반 도형용 채도 낮은 빨/초/파.
  static const normalColors = <Color>[
    Color(0xFFA85C5C), // 빨강 계열
    Color(0xFF5CA86B), // 초록 계열
    Color(0xFF5C7BA8), // 파랑 계열
  ];

  /// 다층 도형 전용 채도 높은 보라.
  static const multiLayerColor = Color(0xFF9B2FE0);

  /// 배경과 "너무 비슷하다"고 볼 명도 차이 임계값.
  static const double _minLightnessDiff = 0.18;

  /// 배경과 "너무 비슷하다"고 볼 채도 차이 임계값.
  static const double _minSaturationDiff = 0.25;

  static Color randomNormal(math.Random random) =>
      normalColors[random.nextInt(normalColors.length)];

  /// 도형 하나의 기본 색을 고른다. 다층 도형은 보라 고정.
  static Color forShape({
    required bool isMultiLayer,
    required math.Random random,
  }) {
    return isMultiLayer ? multiLayerColor : randomNormal(random);
  }

  /// 배경색과 명도·채도가 모두 가까우면 보색으로 반전하고 배경 반대쪽으로
  /// 명도를 밀어 대비를 확보한다. 충분히 구분되면 원래 색을 그대로 쓴다.
  static Color ensureContrast(Color color, Color background) {
    final c = HSLColor.fromColor(color);
    final bg = HSLColor.fromColor(background);

    final lightnessDiff = (c.lightness - bg.lightness).abs();
    final saturationDiff = (c.saturation - bg.saturation).abs();

    final tooSimilar = lightnessDiff < _minLightnessDiff &&
        saturationDiff < _minSaturationDiff;
    if (!tooSimilar) return color;

    // 보색으로 뒤집고, 배경이 어두우면 밝은 쪽 / 밝으면 어두운 쪽으로 민다.
    final flipped = c.withHue((c.hue + 180) % 360);
    final pushedLightness = bg.lightness < 0.5
        ? math.min(1.0, bg.lightness + 0.45)
        : math.max(0.0, bg.lightness - 0.45);
    return flipped.withLightness(pushedLightness).toColor();
  }

  /// 다층 도형에서 레이어별 색. 안쪽으로 갈수록 밝게 해서 중첩이 보이게 한다.
  static Color layerShade(Color base, int layerIndex, int layerCount) {
    if (layerCount <= 1) return base;
    final hsl = HSLColor.fromColor(base);
    // index 0(가장 안쪽)이 가장 밝다.
    final t = layerIndex / (layerCount - 1);
    final lightness = (hsl.lightness + 0.22 * (1 - t)).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
}
