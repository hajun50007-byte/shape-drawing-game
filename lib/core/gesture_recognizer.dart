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

/// 템플릿 하나에 대한 채점 내역. 디버그 오버레이에서 페널티 곡선을
/// 튜닝할 때 쓰인다.
class TemplateEvaluation {
  final String name;

  /// 이 템플릿의 대각선-십자 반지름 비율.
  final double templateRatio;

  /// 후보와 이 템플릿의 비율 차이.
  final double ratioDiff;

  /// ratioDiff로부터 계산된 0~1 배율.
  final double penalty;

  /// 궤적 거리만으로 계산한 0~100 점수.
  final double baseScore;

  /// baseScore * penalty.
  final double finalScore;

  const TemplateEvaluation({
    required this.name,
    required this.templateRatio,
    required this.ratioDiff,
    required this.penalty,
    required this.baseScore,
    required this.finalScore,
  });
}

class RecognitionResult {
  final String name;
  final double score; // 0~100, 높을수록 유사

  /// 후보 궤적의 대각선-십자 반지름 비율.
  final double candidateRatio;

  /// 템플릿별 채점 내역(디버그용).
  final List<TemplateEvaluation> evaluations;

  const RecognitionResult(
    this.name,
    this.score, {
    this.candidateRatio = 0,
    this.evaluations = const [],
  });
}

class UnistrokeRecognizer {
  static const int _numResamplePoints = 64;
  static const double _squareSize = 250.0;
  static final double _halfDiagonal =
      0.5 * math.sqrt(_squareSize * _squareSize * 2);

  /// 대각선/십자 방향 반지름을 잴 때 각 방향에서 허용하는 각도 반경(도).
  static const double _radiusSampleHalfWindow = 15.0;

  /// 대각선 방향(모서리가 있는 쪽).
  static const List<double> _cornerDirections = [45, 135, 225, 315];

  /// 십자 방향(변의 중앙이 있는 쪽).
  static const List<double> _edgeDirections = [0, 90, 180, 270];

  /// 대각선-십자 반지름 비율 차이가 이 값 이하면 감점 없음.
  ///
  /// 이 지표는 "모서리가 변 중앙보다 얼마나 더 멀리 튀어나와 있나"를 재기
  /// 때문에 원(≈1.0)과 사각형(≈1.41)을 뚜렷하게 갈라준다.
  /// 하드 컷이 아니라 소프트 페널티라, 애매하게 그린 도형도 점수만 깎이고
  /// 후보로는 남는다. 두 상수는 디버그 오버레이를 보며 튜닝하는 값이다.
  static const double ratioPenaltyStart = 0.15;

  /// 이 차이 이상이면 페널티가 0(사실상 후보에서 탈락).
  static const double ratioPenaltyEnd = 0.45;

  /// 반지름 비율 차이에 따른 0~1 배율. start 이하면 1, end 이상이면 0,
  /// 그 사이는 선형으로 감소한다.
  static double ratioPenalty(double ratioDiff) {
    if (ratioDiff <= ratioPenaltyStart) return 1.0;
    if (ratioDiff >= ratioPenaltyEnd) return 0.0;
    return 1.0 -
        (ratioDiff - ratioPenaltyStart) / (ratioPenaltyEnd - ratioPenaltyStart);
  }

  final List<ShapeTemplate> _normalizedTemplates;

  // 각 정규화 템플릿의 점 순서를 뒤집은 버전. 사용자가 도형을 시계/반시계
  // 어느 방향으로 그리든 인식되도록, recognize()에서 정방향/역방향 둘 다와
  // 비교해 더 가까운 쪽을 사용한다. _normalizedTemplates와 인덱스가 대응한다.
  late final List<List<Point>> _reversedTemplatePoints;

  /// 각 템플릿의 대각선-십자 반지름 비율. 정규화된 좌표 기준으로 미리
  /// 계산해둔다.
  late final List<double> _templateRatios;

  UnistrokeRecognizer(List<ShapeTemplate> rawTemplates)
      : _normalizedTemplates = rawTemplates
            .map((t) => ShapeTemplate(t.name, _normalize(t.points)))
            .toList() {
    _reversedTemplatePoints =
        _normalizedTemplates.map((t) => t.points.reversed.toList()).toList();
    _templateRatios =
        _normalizedTemplates.map((t) => _cornerEdgeRatioOf(t.points)).toList();
  }

  /// 손가락 궤적(raw)을 등록된 템플릿과 비교
  RecognitionResult recognize(List<Point> rawPoints) {
    if (rawPoints.length < 2) {
      return const RecognitionResult('unknown', 0);
    }
    final candidate = _normalize(rawPoints);
    final candidateRatio = _cornerEdgeRatioOf(candidate);

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
      final templateRatio = _templateRatios[i];
      final ratioDiff = (candidateRatio - templateRatio).abs();
      final penalty = ratioPenalty(ratioDiff);
      final finalScore = baseScore * penalty;

      evaluations.add(TemplateEvaluation(
        name: t.name,
        templateRatio: templateRatio,
        ratioDiff: ratioDiff,
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
        candidateRatio: candidateRatio,
        evaluations: evaluations,
      );
    }

    return RecognitionResult(
      bestName,
      bestScore,
      candidateRatio: candidateRatio,
      evaluations: evaluations,
    );
  }

  /// 대각선-십자 반지름 비율.
  ///
  /// 정규화 마지막 단계에서 중심이 원점으로 옮겨져 있으므로, 중심에서 각
  /// 점까지의 각도와 거리를 그대로 쓸 수 있다. 대각선 네 방향(45/135/225/
  /// 315도)에서 가장 먼 점까지의 거리 평균을 십자 네 방향(0/90/180/270도)의
  /// 평균으로 나눈다.
  ///
  /// 모서리가 뾰족할수록 커진다: 원≈1.0, 사각형≈1.41.
  static double _cornerEdgeRatioOf(List<Point> points) {
    final cornerRadius = _averageMaxRadius(points, _cornerDirections);
    final edgeRadius = _averageMaxRadius(points, _edgeDirections);
    if (edgeRadius <= 0) return 0;
    return cornerRadius / edgeRadius;
  }

  /// 주어진 방향들 각각에 대해 ±[_radiusSampleHalfWindow] 안에 들어오는
  /// 점 중 가장 먼 거리를 구하고, 그 값들의 평균을 낸다.
  /// 어떤 점도 없는 방향은 평균에서 제외한다.
  static double _averageMaxRadius(
    List<Point> points,
    List<double> directions,
  ) {
    double sum = 0;
    int counted = 0;

    for (final direction in directions) {
      double maxRadius = 0;
      bool found = false;
      for (final p in points) {
        if (_angularDistance(_angleDegrees(p), direction) >
            _radiusSampleHalfWindow) {
          continue;
        }
        final radius = math.sqrt(p.x * p.x + p.y * p.y);
        if (!found || radius > maxRadius) {
          maxRadius = radius;
          found = true;
        }
      }
      if (found) {
        sum += maxRadius;
        counted++;
      }
    }

    return counted == 0 ? 0 : sum / counted;
  }

  /// 원점 기준 각도(0~360도).
  static double _angleDegrees(Point p) {
    final degrees = math.atan2(p.y, p.x) * 180 / math.pi;
    return (degrees + 360) % 360;
  }

  /// 두 각도 사이의 최단 거리(0~180도).
  static double _angularDistance(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
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
