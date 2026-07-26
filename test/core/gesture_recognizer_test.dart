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

    test('extent 페널티 곡선은 start~end 사이에서 선형으로 감소한다', () {
      const start = UnistrokeRecognizer.extentPenaltyStart;
      const end = UnistrokeRecognizer.extentPenaltyEnd;

      // 현재 튜닝값. 바꿀 때 의도적으로 바꾸도록 고정해둔다.
      expect(start, 0.22);
      expect(end, 0.55);

      expect(UnistrokeRecognizer.extentPenalty(0), 1.0);
      expect(UnistrokeRecognizer.extentPenalty(start), 1.0);
      expect(UnistrokeRecognizer.extentPenalty(end), 0.0);
      expect(UnistrokeRecognizer.extentPenalty(end + 0.2), 0.0);
      expect(UnistrokeRecognizer.extentPenalty((start + end) / 2),
          closeTo(0.5, 1e-9));
    });

    test('느슨한 범위에서 원-사각형은 서로 감점하지 않는다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);
      final result = recognizer.recognize(ShapeTemplates.square.points);

      // 하드 컷이 아니므로 모든 템플릿의 채점 내역이 남는다.
      expect(result.evaluations.map((e) => e.name),
          containsAll(['circle', 'triangle', 'square']));

      final square = result.evaluations.firstWhere((e) => e.name == 'square');
      final circle = result.evaluations.firstWhere((e) => e.name == 'circle');
      final triangle =
          result.evaluations.firstWhere((e) => e.name == 'triangle');

      // 원-사각형 extent 차이(≈0.214)는 start(0.22) 안이라 둘 다 감점 없음.
      // 즉 이 둘의 구분은 순환정렬 기본 점수가 담당한다.
      expect(circle.extentDiff, lessThan(UnistrokeRecognizer.extentPenaltyStart));
      expect(circle.penalty, 1.0);
      expect(square.penalty, 1.0);
      expect(circle.baseScore, lessThan(square.baseScore));
      expect(result.name, 'square');

      // 삼각형처럼 명백히 다른 도형만 extent로 걸러진다.
      expect(triangle.penalty, lessThan(0.5));
      expect(triangle.finalScore, lessThan(square.finalScore));
    });

    test('면적이 없는 직선은 통과 기준에 한참 못 미치는 점수만 받는다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);

      final line = [
        for (int i = 0; i <= 20; i++) Point(i * 5.0, i * 5.0),
      ];

      final result = recognizer.recognize(line);
      // 느슨해진 범위에서는 삼각형 페널티가 완전히 0이 되지 않아 이름이
      // 붙을 수 있지만, 어떤 난이도의 통과 기준(52~72)에도 못 미친다.
      expect(result.score, lessThan(20));
    });
  });
}
