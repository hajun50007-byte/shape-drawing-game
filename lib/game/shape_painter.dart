import 'package:flutter/material.dart';

import '../core/gesture_recognizer.dart' as core;
import '../core/shape_templates.dart';
import 'falling_shape.dart';

enum StrokeFeedback { hit, miss }

// ShapeTemplates.all은 호출마다 좌표를 새로 계산하므로, 그리기용 좌표는
// 한 번만 계산해 모듈 전역에서 캐싱한다.
final Map<String, List<core.Point>> _templatePoints = {
  for (final t in ShapeTemplates.all) t.name: t.points,
};

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

/// 상단 낙하 구역 전용 페인터. 도형만 그리며 사용자 입력은 받지 않는 순수
/// 표시 영역이다. 매칭에 성공해 destroying 상태인 도형은 흰색으로 플래시한다.
class FallingFieldPainter extends CustomPainter {
  FallingFieldPainter({required this.shapes});

  final List<FallingShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    final normalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white70;

    final flashFill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    final flashStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    for (final shape in shapes) {
      final path = _pathForTemplate(shape.name, shape.x, shape.y, shape.size);
      if (shape.destroying) {
        canvas.drawPath(path, flashFill);
        canvas.drawPath(path, flashStroke);
      } else {
        canvas.drawPath(path, normalPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FallingFieldPainter oldDelegate) {
    // shapes는 매 프레임 같은 리스트 인스턴스를 제자리에서 mutate하므로
    // 참조 비교로는 변경을 감지할 수 없다. 항상 다시 그린다.
    return true;
  }
}

/// 하단 드로잉 패드 전용 페인터. 사용자가 그리고 있는 궤적만 패드 로컬
/// 좌표 기준으로 그린다.
class StrokePadPainter extends CustomPainter {
  StrokePadPainter({required this.strokePoints, required this.feedback});

  final List<core.Point> strokePoints;
  final StrokeFeedback? feedback;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokePoints.length < 2) return;

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = switch (feedback) {
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

  @override
  bool shouldRepaint(covariant StrokePadPainter oldDelegate) => true;
}
