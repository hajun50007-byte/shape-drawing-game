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

/// 삼각형 안에 다음 레이어가 들어갈 때 위로 밀어 올리는 비율
/// (감싸는 삼각형 레이어의 크기 대비).
///
/// 삼각형은 아래로 갈수록 넓어져서, 내용물을 기하학적 중심에 두면
/// 시각적으로 아래로 쏠려 보인다. 살짝 올려야 가운데처럼 보인다.
const double triangleInnerOffsetFactor = 0.09;

/// [enclosingShapeName]이 감쌀 때, 그 안쪽 레이어에 적용할 y 오프셋.
/// 화면 좌표는 y가 아래로 증가하므로 음수가 "위쪽"이다.
double innerLayerOffsetY(String enclosingShapeName, double enclosingSize) {
  if (enclosingShapeName != 'triangle') return 0;
  return -enclosingSize * triangleInnerOffsetFactor;
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
