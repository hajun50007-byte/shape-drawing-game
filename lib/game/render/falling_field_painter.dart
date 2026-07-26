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

      // 바깥(index 큰 쪽) -> 안쪽(index 작은 쪽) 순서로 그려야 안쪽이 위에 보인다.
      for (int i = layerCount - 1; i >= shape.clearedLayers; i--) {
        final scale = layerScale(i, layerCount);
        final path = buildShapePath(
          shape.layers[i],
          shape.x,
          shape.y,
          shape.size * scale,
        );
        paint.color = shape.isFlashing
            ? Colors.white
            : ShapePalette.layerShade(baseColor, i, layerCount);
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
