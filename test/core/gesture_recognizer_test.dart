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

    test('extent 페널티 곡선: 0.08 이하는 감점 없음, 0.30 이상은 0', () {
      expect(UnistrokeRecognizer.extentPenalty(0), 1.0);
      expect(UnistrokeRecognizer.extentPenalty(0.08), 1.0);
      expect(UnistrokeRecognizer.extentPenalty(0.30), 0.0);
      expect(UnistrokeRecognizer.extentPenalty(0.5), 0.0);
      // 중간값은 선형 감소 — 0.19는 정확히 절반.
      expect(UnistrokeRecognizer.extentPenalty(0.19), closeTo(0.5, 1e-9));
    });

    test('하드 컷이 아니라 소프트 페널티라 모든 템플릿이 채점된다', () {
      final recognizer = UnistrokeRecognizer(ShapeTemplates.all);
      final result = recognizer.recognize(ShapeTemplates.square.points);

      // extent 차이가 커도 후보에서 빠지지 않고 내역이 남는다.
      expect(result.evaluations.map((e) => e.name),
          containsAll(['circle', 'triangle', 'square']));
      expect(result.candidateExtent, greaterThan(0));

      final square = result.evaluations.firstWhere((e) => e.name == 'square');
      expect(square.penalty, 1.0);
      expect(square.finalScore, closeTo(square.baseScore, 1e-9));

      // 원은 extent 차이(≈0.21)로 감점돼 사각형보다 낮은 최종 점수가 된다.
      final circle = result.evaluations.firstWhere((e) => e.name == 'circle');
      expect(circle.penalty, lessThan(1.0));
      expect(circle.finalScore, lessThan(square.finalScore));
    });

    test('extent 페널티: 면적 비율이 어느 템플릿과도 다르면 unknown', () {
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
