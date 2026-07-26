import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/gesture_recognizer.dart';
import 'package:shape_drawing_game/core/shape_templates.dart';

void main() {
  group('ShapeTemplates', () {
    test('원/삼각형/사각형 3종만 등록되어 있다 (별 제거됨)', () {
      final names = ShapeTemplates.all.map((t) => t.name).toList();
      expect(names, ['circle', 'triangle', 'square']);
      expect(names, isNot(contains('star')));
    });
  });

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

    test('extent 게이트: 사각형을 그리면 원으로 오인식되지 않는다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      // 시작점을 옮겨 그린 사각형(모서리가 아닌 변 중간부터 시작).
      final square = ShapeTemplates.square.points;
      final shifted = [
        ...square.sublist(square.length ~/ 3),
        ...square.sublist(0, square.length ~/ 3),
      ];

      final result = recognizer.recognize(shifted);
      expect(result.name, 'square');
    });

    test('extent 게이트: 면적 비율이 어느 템플릿과도 다르면 unknown', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      // 거의 직선에 가까운 궤적은 면적이 0에 수렴해 어떤 템플릿의
      // extent와도 0.12 이상 차이가 난다.
      final line = [
        for (int i = 0; i <= 20; i++) Point(i * 5.0, i * 5.0),
      ];

      final result = recognizer.recognize(line);
      expect(result.name, 'unknown');
      expect(result.score, 0);
    });
  });
}
