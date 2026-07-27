import 'dart:math' as math;
import 'dart:ui';

import '../../core/gesture_recognizer.dart' as core;
import '../../core/shape_templates.dart';

/// 템플릿 좌표(0~100 기준)를 이름으로 찾아 쓰기 위한 캐시.
/// ShapeTemplates의 게터는 호출마다 좌표를 새로 계산하므로 한 번만 읽는다.
final Map<String, List<core.Point>> _templatePoints = {
  for (final t in ShapeTemplates.all) t.name: t.points,
};

/// 템플릿별 무게중심(면적 기준). 도형을 "보이는 가운데"에 맞춰 그리는 기준점.
///
/// 삼각형은 아래로 갈수록 넓어져서 바운딩박스 중심과 실제 무게중심이
/// 다르다. 바운딩박스 중심을 기준으로 그리면 다층 도형의 안쪽 레이어가
/// 위로 치우쳐 보인다. 무게중심을 기준으로 삼으면 안쪽 레이어가 그냥
/// 시각적 중앙에서 자라나므로 따로 보정할 필요가 없다.
final Map<String, Offset> _templateCentroids = {
  for (final entry in _templatePoints.entries)
    entry.key: _areaCentroid(entry.value),
};

/// 신발끈 공식으로 구한 면적 무게중심. 면적이 0에 가까우면 좌표 평균으로
/// 물러선다.
Offset _areaCentroid(List<core.Point> points) {
  double doubleArea = 0;
  double cx = 0;
  double cy = 0;

  for (int i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final cross = a.x * b.y - b.x * a.y;
    doubleArea += cross;
    cx += (a.x + b.x) * cross;
    cy += (a.y + b.y) * cross;
  }

  if (doubleArea.abs() < 1e-9) {
    final avgX = points.map((p) => p.x).reduce((a, b) => a + b) / points.length;
    final avgY = points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
    return Offset(avgX, avgY);
  }

  final area = doubleArea / 2;
  return Offset(cx / (6 * area), cy / (6 * area));
}

/// 다층 도형에서 안쪽 레이어일수록 작아지는 비율.
/// index 0(가장 안쪽)이 가장 작고, 마지막 레이어가 전체 크기가 된다.
double layerScale(int layerIndex, int layerCount) {
  return (layerIndex + 1) / layerCount;
}

/// 이름에 해당하는 도형의 무게중심(템플릿 좌표계).
Offset templateCentroid(String name) =>
    _templateCentroids[name] ?? const Offset(50, 50);

/// 이름에 해당하는 도형을 (cx, cy)를 **무게중심**으로 삼아 그린 닫힌 Path.
///
/// 모든 레이어가 같은 (cx, cy)를 쓰므로, 다층 도형의 안쪽 레이어는 바깥
/// 도형의 시각적 중앙에서 그대로 작아진 모습이 된다.
Path buildShapePath(String name, double cx, double cy, double size) {
  final points = _templatePoints[name];
  final path = Path();
  if (points == null || points.isEmpty) return path;

  final centroid = templateCentroid(name);
  // 템플릿 좌표는 0~100 범위이므로, 무게중심 기준 상대 좌표를 size에 맞춘다.
  final unit = size / 2 / 50;

  for (int i = 0; i < points.length; i++) {
    final px = cx + (points[i].x - centroid.dx) * unit;
    final py = cy + (points[i].y - centroid.dy) * unit;
    if (i == 0) {
      path.moveTo(px, py);
    } else {
      path.lineTo(px, py);
    }
  }
  // 채우기 방식이므로 항상 닫아준다.
  path.close();
  return path;
}

/// 도형이 무게중심 기준으로 위/아래로 뻗는 최대 거리(size 대비 비율).
/// 놓침 판정처럼 "완전히 화면 밖으로 나갔는지"를 볼 때 쓴다.
double shapeBottomExtentFactor(String name) {
  final points = _templatePoints[name];
  if (points == null || points.isEmpty) return 0.5;
  final centroid = templateCentroid(name);
  final maxY = points.map((p) => p.y).reduce(math.max);
  return (maxY - centroid.dy) / 100;
}
