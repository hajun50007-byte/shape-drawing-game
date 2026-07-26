import 'package:flutter/material.dart';

import '../../core/gesture_recognizer.dart' as core;
import '../render/stroke_pad_painter.dart';

/// 하단 고정 드로잉 패드. 이 위젯 안에서만 궤적 입력을 받으며, 패드 밖으로
/// 손가락이 나가도 선이 삐져나오지 않도록 ClipRect로 렌더링을 가둔다.
class DrawingPad extends StatelessWidget {
  const DrawingPad({
    super.key,
    required this.width,
    required this.height,
    required this.background,
    required this.strokePoints,
    required this.feedback,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final double width;
  final double height;
  final Color background;
  final List<core.Point> strokePoints;
  final StrokeFeedback? feedback;
  final void Function(Offset localPosition) onStart;
  final void Function(Offset localPosition) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background,
        border: const Border(
          top: BorderSide(color: Colors.white24, width: 2),
        ),
      ),
      child: GestureDetector(
        onPanStart: (d) => onStart(d.localPosition),
        onPanUpdate: (d) => onUpdate(d.localPosition),
        onPanEnd: (_) => onEnd(),
        // 패드 영역 밖으로는 아무것도 렌더링되지 않게 클리핑.
        child: ClipRect(
          child: CustomPaint(
            size: Size(width, height),
            painter: StrokePadPainter(
              strokePoints: strokePoints,
              feedback: feedback,
            ),
          ),
        ),
      ),
    );
  }
}
