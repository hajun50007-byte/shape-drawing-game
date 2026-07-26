import 'dart:ui';

import '../../core/gesture_recognizer.dart' as core;
import '../../core/shape_templates.dart';

/// 템플릿 좌표(0~100 기준)를 이름으로 찾아 쓰기 위한 캐시.
/// ShapeTemplates의 게터는 호출마다 좌표를 새로 계산하므로 한 번만 읽는다.
final Map<String, List<core.Point>> _templatePoints = {
  for (final t in ShapeTemplates.all) t.name: t.points,
};

/// 다층 도형에서 안쪽 레이어일수록 작아지는 비율.
/// index 0(가장 안쪽)이 가장 작고, 마지막 레이어가 전체 크기가 된다.
double layerScale(int layerIndex, int layerCount) {
  return (layerIndex + 1) / layerCount;
}

/// 이름에 해당하는 도형을 (cx, cy) 중심 · 지정 크기로 그린 닫힌 Path.
Path buildShapePath(String name, double cx, double cy, double size) {
  final points = _templatePoints[name];
  final path = Path();
  if (points == null || points.isEmpty) return path;

  for (int i = 0; i < points.length; i++) {
    // 템플릿 좌표는 0~100 범위이므로 중심 기준 -size/2 ~ +size/2로 변환.
    final px = cx + (points[i].x - 50) / 50 * (size / 2);
    final py = cy + (points[i].y - 50) / 50 * (size / 2);
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
