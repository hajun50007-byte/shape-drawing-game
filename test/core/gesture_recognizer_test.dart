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

    test('사각형을 그리면 원으로 오인식되지 않는다', () {
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

    test('반지름 비율 페널티 곡선은 start~end 사이에서 선형으로 감소한다', () {
      const start = UnistrokeRecognizer.ratioPenaltyStart;
      const end = UnistrokeRecognizer.ratioPenaltyEnd;

      // 현재 튜닝값. 바꿀 때 의도적으로 바꾸도록 고정해둔다.
      expect(start, 0.15);
      expect(end, 0.45);

      expect(UnistrokeRecognizer.ratioPenalty(0), 1.0);
      expect(UnistrokeRecognizer.ratioPenalty(start), 1.0);
      expect(UnistrokeRecognizer.ratioPenalty(end), 0.0);
      expect(UnistrokeRecognizer.ratioPenalty(end + 0.2), 0.0);
      expect(UnistrokeRecognizer.ratioPenalty((start + end) / 2),
          closeTo(0.5, 1e-9));
    });

    test('대각선-십자 비율이 도형별로 뚜렷하게 갈린다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      double ratioOf(String name) => recognizer
          .recognize(ShapeTemplates.all.firstWhere((t) => t.name == name).points)
          .candidateRatio;

      // 원은 모든 방향의 반지름이 같아 1에 수렴하고,
      // 사각형은 모서리가 변보다 √2배 멀어 1.4 근처가 된다.
      expect(ratioOf('circle'), closeTo(1.0, 0.05));
      expect(ratioOf('square'), greaterThan(1.3));
      expect(ratioOf('square') - ratioOf('circle'),
          greaterThan(UnistrokeRecognizer.ratioPenaltyStart));
    });

    test('사각형을 그리면 원 후보가 비율 페널티로 크게 깎인다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);
      final result = recognizer.recognize(ShapeTemplates.square.points);

      // 하드 컷이 아니므로 모든 템플릿의 채점 내역이 남는다.
      expect(result.evaluations.map((e) => e.name),
          containsAll(['circle', 'triangle', 'square']));

      final square = result.evaluations.firstWhere((e) => e.name == 'square');
      final circle = result.evaluations.firstWhere((e) => e.name == 'circle');

      expect(result.name, 'square');
      expect(square.penalty, 1.0);
      // 원은 비율 차이(≈0.36)로 감점돼 기본 점수만 볼 때보다 훨씬 벌어진다.
      expect(circle.penalty, lessThan(0.5));
      expect(circle.finalScore, lessThan(square.finalScore / 2));
    });

    test('면적이 없는 직선은 어떤 템플릿과도 비율이 달라 unknown', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      final line = [
        for (int i = 0; i <= 20; i++) Point(i * 5.0, i * 5.0),
      ];

      final result = recognizer.recognize(line);
      expect(result.name, 'unknown');
      expect(result.score, 0);
    });
  });
}
