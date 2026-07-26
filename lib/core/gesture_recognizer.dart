import 'dart:math' as math;

/// $1 Unistroke Recognizer 구현 (Wobbrock, Wilson, Li 2007 기반 간소화 버전)
/// 손가락으로 그린 궤적(포인트 목록)을 등록된 도형 템플릿과 비교해
/// 가장 유사한 도형과 0~100 유사도 점수를 반환한다.
///
/// 주의: 실제 통과 기준(threshold)은 difficulty.dart의 값을 사용하며,
/// 이 클래스는 순수 계산만 담당한다. Flutter 위젯/제스처 코드와 분리되어 있어
/// 별도 단위 테스트가 가능하다.

class Point {
  final double x;
  final double y;
  const Point(this.x, this.y);
}

class ShapeTemplate {
  final String name;
  final List<Point> points;
  const ShapeTemplate(this.name, this.points);
}

class RecognitionResult {
  final String name;
  final double score; // 0~100, 높을수록 유사
  const RecognitionResult(this.name, this.score);
}

class UnistrokeRecognizer {
  static const int _numResamplePoints = 64;
  static const double _squareSize = 250.0;
  static final double _halfDiagonal =
      0.5 * math.sqrt(_squareSize * _squareSize * 2);

  final List<ShapeTemplate> _normalizedTemplates;

  UnistrokeRecognizer(List<ShapeTemplate> rawTemplates)
      : _normalizedTemplates = rawTemplates
            .map((t) => ShapeTemplate(t.name, _normalize(t.points)))
            .toList();

  /// 손가락 궤적(raw)을 등록된 템플릿과 비교
  RecognitionResult recognize(List<Point> rawPoints) {
    if (rawPoints.length < 2) {
      return const RecognitionResult('unknown', 0);
    }
    final candidate = _normalize(rawPoints);

    String bestName = 'unknown';
    double bestDistance = double.infinity;

    for (final t in _normalizedTemplates) {
      final d = _pathDistance(candidate, t.points);
      if (d < bestDistance) {
        bestDistance = d;
        bestName = t.name;
      }
    }

    final score =
        math.max(0.0, (1 - bestDistance / _halfDiagonal) * 100).toDouble();
    return RecognitionResult(bestName, score);
  }

  // ---------------- 내부 정규화 파이프라인 ----------------

  static List<Point> _normalize(List<Point> points) {
    var pts = _resample(points, _numResamplePoints);
    final angle = _indicativeAngle(pts);
    pts = _rotateBy(pts, -angle);
    pts = _scaleToSquare(pts, _squareSize);
    pts = _translateToOrigin(pts);
    return pts;
  }

  static List<Point> _resample(List<Point> points, int n) {
    final src = List<Point>.from(points);
    final pathLen = _pathLength(src);
    if (pathLen == 0) {
      return List.filled(n, src.first);
    }
    final interval = pathLen / (n - 1);
    double d = 0;
    final newPoints = <Point>[src.first];

    int i = 1;
    while (i < src.length && newPoints.length < n) {
      final prev = src[i - 1];
      final cur = src[i];
      final segDist = _distance(prev, cur);
      if (segDist == 0) {
        i++;
        continue;
      }
      if (d + segDist >= interval) {
        final t = (interval - d) / segDist;
        final newPoint = Point(
          prev.x + t * (cur.x - prev.x),
          prev.y + t * (cur.y - prev.y),
        );
        newPoints.add(newPoint);
        src.insert(i, newPoint);
        d = 0;
      } else {
        d += segDist;
      }
      i++;
    }
    while (newPoints.length < n) {
      newPoints.add(src.last);
    }
    return newPoints;
  }

  static double _pathLength(List<Point> points) {
    double len = 0;
    for (int i = 1; i < points.length; i++) {
      len += _distance(points[i - 1], points[i]);
    }
    return len;
  }

  static double _distance(Point a, Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _indicativeAngle(List<Point> points) {
    final c = _centroid(points);
    // Flutter 좌표계는 y가 아래로 증가하므로, 실제 기기 테스트하며
    // 부호가 반대로 느껴지면 이 함수의 부호를 뒤집어 조정할 것.
    return math.atan2(c.y - points.first.y, points.first.x - c.x);
  }

  static Point _centroid(List<Point> points) {
    double sx = 0, sy = 0;
    for (final p in points) {
      sx += p.x;
      sy += p.y;
    }
    return Point(sx / points.length, sy / points.length);
  }

  static List<Point> _rotateBy(List<Point> points, double angle) {
    final c = _centroid(points);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return points.map((p) {
      final dx = p.x - c.x;
      final dy = p.y - c.y;
      return Point(
        dx * cosA - dy * sinA + c.x,
        dx * sinA + dy * cosA + c.y,
      );
    }).toList();
  }

  static List<Point> _scaleToSquare(List<Point> points, double size) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final w = maxX - minX;
    final h = maxY - minY;
    return points.map((p) {
      return Point(
        w == 0 ? p.x : (p.x - minX) * (size / w),
        h == 0 ? p.y : (p.y - minY) * (size / h),
      );
    }).toList();
  }

  static List<Point> _translateToOrigin(List<Point> points) {
    final c = _centroid(points);
    return points.map((p) => Point(p.x - c.x, p.y - c.y)).toList();
  }

  static double _pathDistance(List<Point> a, List<Point> b) {
    double d = 0;
    final n = math.min(a.length, b.length);
    for (int i = 0; i < n; i++) {
      d += _distance(a[i], b[i]);
    }
    return d / n;
  }
}
