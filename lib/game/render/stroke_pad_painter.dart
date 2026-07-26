import 'package:flutter/material.dart';

import '../../core/gesture_recognizer.dart' as core;

/// 드로잉 결과 피드백 상태.
enum StrokeFeedback { hit, miss }

/// 하단 드로잉 패드 전용 페인터. 사용자가 그리고 있는 궤적만 패드 로컬
/// 좌표 기준으로 그린다. 패드 밖으로 삐져나가지 않게 하는 클리핑은
/// 이 페인터를 감싸는 ClipRect가 담당한다.
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
