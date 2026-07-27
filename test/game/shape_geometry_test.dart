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

  group('도형 무게중심', () {
    test('원과 사각형은 무게중심이 바운딩박스 중심과 같다', () {
      expect(templateCentroid('circle').dx, closeTo(50, 0.5));
      expect(templateCentroid('circle').dy, closeTo(50, 0.5));
      expect(templateCentroid('square').dx, closeTo(50, 0.5));
      expect(templateCentroid('square').dy, closeTo(50, 0.5));
    });

    test('삼각형은 무게중심이 바운딩박스 중심보다 아래에 있다', () {
      final centroid = templateCentroid('triangle');
      expect(centroid.dx, closeTo(50, 0.5));
      // 꼭짓점 (50,10) (90,90) (10,90)의 무게중심 y = 63.33.
      expect(centroid.dy, closeTo(63.33, 1.0));
      expect(centroid.dy, greaterThan(50),
          reason: '삼각형은 아래로 갈수록 넓어 무게중심이 아래쪽이다');
    });
  });

  group('다층 도형 중심 정렬', () {
    /// path의 세로 중앙(바운딩박스 기준).
    double verticalCenterOf(String name, double cy, double size) {
      final bounds = buildShapePath(name, 100, cy, size).getBounds();
      return bounds.center.dy;
    }

    test('삼각형은 지정한 좌표를 무게중심으로 삼아 그려진다', () {
      // 무게중심 기준이므로 바운딩박스 중앙은 지정 좌표보다 위에 온다.
      final boxCenter = verticalCenterOf('triangle', 200, 100);
      expect(boxCenter, lessThan(200));
    });

    test('안쪽 삼각형이 바깥 삼각형 안에 완전히 들어간다', () {
      final outerPath = buildShapePath('triangle', 100, 200, 100);
      final outer = outerPath.getBounds();
      final inner = buildShapePath('triangle', 100, 200, 50).getBounds();

      expect(inner.left, greaterThan(outer.left));
      expect(inner.right, lessThan(outer.right));
      expect(inner.top, greaterThan(outer.top));
      expect(inner.bottom, lessThan(outer.bottom));

      // 닮은 삼각형을 무게중심 기준으로 줄인 것이므로 여백은 같지 않고
      // 무게중심에서 각 변까지의 거리에 비례한다(꼭짓점 쪽이 더 멀다).
      final topGap = inner.top - outer.top;
      final bottomGap = outer.bottom - inner.bottom;
      expect(topGap, greaterThan(bottomGap));
      expect(topGap / bottomGap, closeTo(2.0, 0.1));
    });

    test('삼각형 안에 든 원이 삼각형 밖으로 삐져나오지 않는다', () {
      // 무게중심 기준이 아니면(예: 바운딩박스 중심) 원이 좁은 꼭짓점
      // 쪽으로 밀려 위로 삐져나온다. 그게 이번에 고친 문제다.
      final trianglePath = buildShapePath('triangle', 100, 200, 100);
      final circle = buildShapePath('circle', 100, 200, 40).getBounds();

      // 원의 위·아래·좌·우 끝점이 모두 삼각형 안에 있어야 한다.
      expect(trianglePath.contains(Offset(100, circle.top + 0.5)), isTrue,
          reason: '원의 위쪽 끝이 삼각형 밖으로 나갔다');
      expect(trianglePath.contains(Offset(100, circle.bottom - 0.5)), isTrue);
      expect(trianglePath.contains(Offset(circle.left + 0.5, 200)), isTrue);
      expect(trianglePath.contains(Offset(circle.right - 0.5, 200)), isTrue);
    });
  });
}
