import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/game/render/shape_geometry.dart';

void main() {
  group('layerScale', () {
    test('index 0(가장 안쪽)이 가장 작고 마지막이 전체 크기', () {
      expect(layerScale(0, 2), 0.5);
      expect(layerScale(1, 2), 1.0);
      expect(layerScale(0, 4), 0.25);
      expect(layerScale(3, 4), 1.0);
    });
  });

  group('삼각형 안쪽 레이어 위치 보정', () {
    test('삼각형이 감싸면 안쪽 레이어가 위로 올라간다', () {
      // 화면 좌표는 y가 아래로 증가하므로 "위쪽"은 음수.
      final offset = innerLayerOffsetY('triangle', 100);
      expect(offset, lessThan(0));
      expect(offset, closeTo(-100 * triangleInnerOffsetFactor, 1e-9));
    });

    test('원/사각형이 감쌀 때는 보정하지 않는다', () {
      expect(innerLayerOffsetY('circle', 100), 0);
      expect(innerLayerOffsetY('square', 100), 0);
    });

    test('보정량은 감싸는 레이어 크기에 비례한다', () {
      final small = innerLayerOffsetY('triangle', 50);
      final large = innerLayerOffsetY('triangle', 200);
      expect(large.abs(), greaterThan(small.abs()));
      expect(large, closeTo(small * 4, 1e-9));
    });
  });
}
