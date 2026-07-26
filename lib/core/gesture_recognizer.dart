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

/// 템플릿 하나에 대한 채점 내역. 디버그 오버레이에서 extent 페널티 곡선을
/// 튜닝할 때 쓰인다.
class TemplateEvaluation {
  final String name;

  /// 후보와 이 템플릿의 extent 차이.
  final double extentDiff;

  /// extentDiff로부터 계산된 0~1 배율.
  final double penalty;

  /// 궤적 거리만으로 계산한 0~100 점수.
  final double baseScore;

  /// baseScore * penalty.
  final double finalScore;

  const TemplateEvaluation({
    required this.name,
    required this.extentDiff,
    required this.penalty,
    required this.baseScore,
    required this.finalScore,
  });
}

class RecognitionResult {
  final String name;
  final double score; // 0~100, 높을수록 유사

  /// 후보 궤적의 extent(면적 ÷ 바운딩박스 면적).
  final double candidateExtent;

  /// 템플릿별 채점 내역(디버그용).
  final List<TemplateEvaluation> evaluations;

  const RecognitionResult(
    this.name,
    this.score, {
    this.candidateExtent = 0,
    this.evaluations = const [],
  });
}

class UnistrokeRecognizer {
  static const int _numResamplePoints = 64;
  static const double _squareSize = 250.0;
  static final double _halfDiagonal =
      0.5 * math.sqrt(_squareSize * _squareSize * 2);

  /// extent(면적 ÷ 바운딩박스 면적) 차이가 이 값 이하면 감점 없음.
  /// 원≈0.785 / 사각형≈1.0 / 삼각형≈0.5.
  ///
  /// 하드 컷이 아니라 소프트 페널티라, 애매하게 그린 도형도 점수만 깎이고
  /// 후보로는 남는다. 두 상수는 디버그 오버레이를 보며 튜닝하는 값이다.
  ///
  /// 현재 범위는 의도적으로 느슨하다: 원-사각형 차이(≈0.21)가 start 안에
  /// 들어와 서로 감점하지 않으므로, 둘의 구분은 순환정렬 기본 점수에 맡기고
  /// extent는 삼각형처럼 명백히 다른 도형만 걸러낸다.
  static const double extentPenaltyStart = 0.22;

  /// 이 차이 이상이면 페널티가 0(사실상 후보에서 탈락).
  static const double extentPenaltyEnd = 0.55;

  /// extent 차이에 따른 0~1 배율. start 이하면 1, end 이상이면 0,
  /// 그 사이는 선형으로 감소한다.
  static double extentPenalty(double extentDiff) {
    if (extentDiff <= extentPenaltyStart) return 1.0;
    if (extentDiff >= extentPenaltyEnd) return 0.0;
    return 1.0 -
        (extentDiff - extentPenaltyStart) /
            (extentPenaltyEnd - extentPenaltyStart);
  }

  final List<ShapeTemplate> _normalizedTemplates;

  // 각 정규화 템플릿의 점 순서를 뒤집은 버전. 사용자가 도형을 시계/반시계
  // 어느 방향으로 그리든 인식되도록, recognize()에서 정방향/역방향 둘 다와
  // 비교해 더 가까운 쪽을 사용한다. _normalizedTemplates와 인덱스가 대응한다.
  late final List<List<Point>> _reversedTemplatePoints;

  /// 각 템플릿의 extent. 정규화된 좌표 기준으로 미리 계산해둔다.
  late final List<double> _templateExtents;

  UnistrokeRecognizer(List<ShapeTemplate> rawTemplates)
      : _normalizedTemplates = rawTemplates
            .map((t) => ShapeTemplate(t.name, _normalize(t.points)))
            .toList() {
    _reversedTemplatePoints =
        _normalizedTemplates.map((t) => t.points.reversed.toList()).toList();
    _templateExtents =
        _normalizedTemplates.map((t) => _extentOf(t.points)).toList();
  }

  /// 손가락 궤적(raw)을 등록된 템플릿과 비교
  RecognitionResult recognize(List<Point> rawPoints) {
    if (rawPoints.length < 2) {
      return const RecognitionResult('unknown', 0);
    }
    final candidate = _normalize(rawPoints);
    final candidateExtent = _extentOf(candidate);

    final evaluations = <TemplateEvaluation>[];
    String bestName = 'unknown';
    double bestScore = 0;

    for (int i = 0; i < _normalizedTemplates.length; i++) {
      final t = _normalizedTemplates[i];
      final forwardDistance = _bestCyclicDistance(candidate, t.points);
      final reversedDistance =
          _bestCyclicDistance(candidate, _reversedTemplatePoints[i]);
      final distance = math.min(forwardDistance, reversedDistance);

      final baseScore =
          math.max(0.0, (1 - distance / _halfDiagonal) * 100).toDouble();
      final extentDiff = (candidateExtent - _templateExtents[i]).abs();
      final penalty = extentPenalty(extentDiff);
      final finalScore = baseScore * penalty;

      evaluations.add(TemplateEvaluation(
        name: t.name,
        extentDiff: extentDiff,
        penalty: penalty,
        baseScore: baseScore,
        finalScore: finalScore,
      ));

      if (finalScore > bestScore) {
        bestScore = finalScore;
        bestName = t.name;
      }
    }

    // 페널티까지 먹고도 0점이면 어떤 도형도 아니라고 본다.
    if (bestScore <= 0) {
      return RecognitionResult(
        'unknown',
        0,
        candidateExtent: candidateExtent,
        evaluations: evaluations,
      );
    }

    return RecognitionResult(
      bestName,
      bestScore,
      candidateExtent: candidateExtent,
      evaluations: evaluations,
    );
  }

  /// 신발끈 공식으로 구한 도형 면적 ÷ 바운딩박스 면적.
  /// 마지막 점과 첫 점을 잇는 닫힌 다각형으로 취급한다.
  static double _extentOf(List<Point> points) {
    double doubleArea = 0;
    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      doubleArea += a.x * b.y - b.x * a.y;
    }
    final area = doubleArea.abs() / 2;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final boundingArea = (maxX - minX) * (maxY - minY);
    if (boundingArea == 0) return 0;
    return area / boundingArea;
  }

  // ---------------- 내부 정규화 파이프라인 ----------------

  static List<Point> _normalize(List<Point> points) {
    // 회전 보정(indicative angle) 없이 리샘플 -> 스케일 -> 원점 이동만 적용한다.
    // 시작점/방향에 따른 정렬 문제는 recognize()의 순환 정렬(cyclic shift)
    // 최적화와 정방향/역방향 비교가 대신 흡수한다.
    var pts = _resample(points, _numResamplePoints);
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

  static Point _centroid(List<Point> points) {
    double sx = 0, sy = 0;
    for (final p in points) {
      sx += p.x;
      sy += p.y;
    }
    return Point(sx / points.length, sy / points.length);
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

  /// a를 0~n-1칸 순환 이동(cyclic shift)시켜가며 b와의 평균 거리를 계산하고
  /// 그중 최솟값을 반환한다. 시작점이 서로 다른 두 궤적이라도 정렬만
  /// 맞으면 낮은 거리로 평가된다.
  static double _bestCyclicDistance(List<Point> a, List<Point> b) {
    final n = math.min(a.length, b.length);
    double best = double.infinity;
    for (int shift = 0; shift < n; shift++) {
      double d = 0;
      for (int i = 0; i < n; i++) {
        d += _distance(a[(i + shift) % n], b[i]);
      }
      d /= n;
      if (d < best) best = d;
    }
    return best;
  }
}
