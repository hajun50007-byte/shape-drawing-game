import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/gesture_recognizer.dart';
import 'package:shape_drawing_game/core/shape_templates.dart';

void main() {
  group('UnistrokeRecognizer', () {
    test('각 템플릿 자신의 궤적을 그대로 넣으면 높은 점수로 스스로를 인식한다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      for (final template in ShapeTemplates.all) {
        final result = recognizer.recognize(template.points);
        expect(result.name, template.name);
        expect(result.score, greaterThan(90));
      }
    });

    test('포인트가 2개 미만이면 unknown/0점을 반환한다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      final result = recognizer.recognize([const Point(0, 0)]);

      expect(result.name, 'unknown');
      expect(result.score, 0);
    });

    test('점 순서를 뒤집어(반시계 방향) 그려도 높은 점수로 인식한다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      for (final template in ShapeTemplates.all) {
        final reversed = template.points.reversed.toList();
        final result = recognizer.recognize(reversed);
        expect(result.name, template.name);
        expect(result.score, greaterThan(90));
      }
    });
  });
}
