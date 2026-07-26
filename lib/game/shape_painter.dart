import 'package:flutter/material.dart';

import '../core/gesture_recognizer.dart' as core;
import '../core/shape_templates.dart';
import 'falling_shape.dart';

enum StrokeFeedback { hit, miss }

/// 낙하 중인 도형들과 사용자가 그리고 있는 궤적을 함께 그리는 페인터.
class GameCanvasPainter extends CustomPainter {
  GameCanvasPainter({
    required this.shapes,
    required this.strokePoints,
    required this.strokeFeedback,
  });

  final List<FallingShape> shapes;
  final List<core.Point> strokePoints;
  final StrokeFeedback? strokeFeedback;

  // ShapeTemplates.all은 호출마다 좌표를 새로 계산하므로, 그리기용 좌표는
  // 한 번만 계산해 static으로 캐싱한다.
  static final Map<String, List<core.Point>> _templatePoints = {
    for (final t in ShapeTemplates.all) t.name: t.points,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final shapePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white70;

    for (final shape in shapes) {
      canvas.drawPath(
        _pathForTemplate(shape.name, shape.x, shape.y, shape.size),
        shapePaint,
      );
    }

    if (strokePoints.length > 1) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = switch (strokeFeedback) {
          StrokeFeedback.hit => Colors.greenAccent,
          StrokeFeedback.miss => Colors.redAccent,
          null => Colors.amberAccent,
        };

      final path = Path()..moveTo(strokePoints.first.x, strokePoints.first.y);
      for (final p in strokePoints.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  Path _pathForTemplate(String name, double cx, double cy, double size) {
    final templatePoints = _templatePoints[name]!;
    final path = Path();
    for (int i = 0; i < templatePoints.length; i++) {
      // 템플릿 좌표는 0~100 범위이므로 도형 중심 기준 -size/2 ~ +size/2로 변환.
      final px = cx + (templatePoints[i].x - 50) / 50 * (size / 2);
      final py = cy + (templatePoints[i].y - 50) / 50 * (size / 2);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant GameCanvasPainter oldDelegate) {
    // shapes/strokePoints는 매 프레임 같은 리스트 인스턴스를 제자리에서
    // mutate하므로 참조 비교로는 변경을 감지할 수 없다. 게임 루프가 매 프레임
    // setState로 새 페인터를 만드는 빈도 자체가 낮지 않으니 항상 다시 그린다.
    return true;
  }
}
