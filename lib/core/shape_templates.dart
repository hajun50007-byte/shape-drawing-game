import 'dart:math' as math;
import 'gesture_recognizer.dart';

/// Phase 1 프로토타입용 기본 도형 템플릿.
/// 좌표 스케일은 무관(인식기가 정규화함). 여기서는 0~100 기준 좌표 사용.
/// 새 도형을 추가할 땐 서로 헷갈리지 않을 만큼 형태가 뚜렷한 것부터 넣을 것
/// (예: 원과 타원처럼 유사한 형태를 초반에 같이 넣으면 오인식 늘어남).
class ShapeTemplates {
  static List<ShapeTemplate> get all => [circle, triangle, square, star];

  static ShapeTemplate get circle {
    final pts = <Point>[];
    for (int i = 0; i <= 60; i++) {
      final angle = 2 * math.pi * i / 60;
      pts.add(Point(50 + 40 * math.cos(angle), 50 + 40 * math.sin(angle)));
    }
    return ShapeTemplate('circle', pts);
  }

  static ShapeTemplate get triangle {
    return ShapeTemplate(
      'triangle',
      _polyline([
        const Point(50, 10),
        const Point(90, 90),
        const Point(10, 90),
        const Point(50, 10),
      ]),
    );
  }

  static ShapeTemplate get square {
    return ShapeTemplate(
      'square',
      _polyline([
        const Point(10, 10),
        const Point(90, 10),
        const Point(90, 90),
        const Point(10, 90),
        const Point(10, 10),
      ]),
    );
  }

  static ShapeTemplate get star {
    return ShapeTemplate('star', _polyline(_starVertices()));
  }

  static List<Point> _starVertices() {
    const cx = 50.0, cy = 50.0;
    const outerR = 45.0, innerR = 18.0;
    const points = 5;
    final vertices = <Point>[];
    for (int i = 0; i <= points * 2; i++) {
      final r = (i % 2 == 0) ? outerR : innerR;
      final angle = (math.pi / points) * i - math.pi / 2;
      vertices.add(Point(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    return vertices;
  }

  /// 꼭짓점 목록을 선분으로 잇는 point path로 변환 (인식기는 연속된 궤적을 기대함)
  static List<Point> _polyline(List<Point> vertices,
      {int pointsPerSegment = 20}) {
    final result = <Point>[];
    for (int i = 0; i < vertices.length - 1; i++) {
      final a = vertices[i];
      final b = vertices[i + 1];
      for (int j = 0; j < pointsPerSegment; j++) {
        final t = j / pointsPerSegment;
        result.add(Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    result.add(vertices.last);
    return result;
  }
}
