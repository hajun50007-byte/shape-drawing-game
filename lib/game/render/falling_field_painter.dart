import 'package:flutter/material.dart';

import '../model/falling_shape.dart';
import 'shape_geometry.dart';
import 'shape_palette.dart';

/// 상단 낙하 구역 전용 페인터. 도형을 단색 채우기로 그린다.
/// 다층 도형은 바깥 레이어부터 그려서 안쪽 레이어가 위에 보이게 하고,
/// 이미 벗겨낸 레이어는 그리지 않는다.
class FallingFieldPainter extends CustomPainter {
  FallingFieldPainter({required this.shapes, required this.background});

  final List<FallingShape> shapes;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final shape in shapes) {
      final layerCount = shape.layers.length;
      final baseColor = ShapePalette.ensureContrast(shape.color, background);

      // 등장 연출: 작게 시작해 제자리 크기까지 커지며 서서히 진해진다.
      final intro = shape.introProgress;
      final introScale = 0.3 + 0.7 * intro;
      final introAlpha = (0.25 + 0.75 * intro).clamp(0.0, 1.0);

      // 클리어는 바깥부터 진행되므로 남아 있는 가장 바깥 레이어부터 그리고,
      // 안쪽(index 작은 쪽)을 나중에 그려야 위에 보인다.
      for (int i = shape.outermostRemainingIndex; i >= 0; i--) {
        final scale = layerScale(i, layerCount) * introScale;
        final path = buildShapePath(
          shape.layers[i],
          shape.x,
          shape.y,
          shape.size * scale,
        );
        final color = shape.isFlashing
            ? Colors.white
            : ShapePalette.layerShade(baseColor, i, layerCount);
        paint.color =
            introAlpha >= 1 ? color : color.withValues(alpha: introAlpha);
        canvas.drawPath(path, paint);
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
