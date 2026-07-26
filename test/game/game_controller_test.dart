import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/core/shape_templates.dart';
import 'package:shape_drawing_game/game/model/falling_shape.dart';
import 'package:shape_drawing_game/game/state/game_controller.dart';

GameController _controllerFor(RunConfig config) {
  final controller = GameController(runConfig: config, random: math.Random(7));
  controller.setFieldSize(const Size(400, 500));
  return controller;
}

FallingShape _shape(List<String> layers, {int id = 1, double y = 100}) {
  return FallingShape(
    id: id,
    layers: layers,
    x: 200,
    y: y,
    size: 72,
    color: Colors.red,
  );
}

/// 템플릿 좌표를 그대로 드로잉 패드 입력으로 흘려보낸다.
void _draw(GameController controller, String shapeName) {
  final template =
      ShapeTemplates.all.firstWhere((t) => t.name == shapeName).points;
  controller.startStroke(template.first.x, template.first.y);
  for (final p in template.skip(1)) {
    controller.extendStroke(p.x, p.y);
  }
  controller.endStroke();
}

void main() {
  // 컨트롤러가 성공 시 HapticFeedback/SystemSound를 호출하므로 플랫폼
  // 채널을 쓸 수 있게 바인딩을 초기화한다.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('매칭', () {
    test('같은 이름의 도형이 여러 개면 한 번에 모두 클리어된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2, y: 150),
        _shape(['square'], id: 3, y: 200),
      ]);

      _draw(controller, 'circle');

      final cleared = controller.shapes.where((s) => s.isCleared).toList();
      expect(cleared.map((s) => s.id), unorderedEquals([1, 2]));
      expect(controller.shapes.firstWhere((s) => s.id == 3).isCleared, isFalse);
      expect(controller.score, greaterThan(0));
    });

    test('인식 실패 시 유사도 점수와 통과 기준이 기록된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle']));

      // 거의 직선이라 어떤 템플릿에도 맞지 않는다.
      controller.startStroke(0, 0);
      controller.extendStroke(50, 50);
      controller.extendStroke(100, 100);
      controller.endStroke();

      expect(controller.shapes.single.isCleared, isFalse);
      expect(controller.lastMissScore, isNotNull);
      expect(controller.lastMissThreshold, isNotNull);
    });
  });

  group('다층 도형', () {
    test('안쪽 레이어부터 순서대로 벗겨진다', () {
      final controller = _controllerFor(RunPresets.specialStage);
      // index 0 = 안쪽(triangle), index 1 = 바깥(circle)
      controller.shapes.add(_shape(['triangle', 'circle']));
      final shape = controller.shapes.single;

      // 바깥 레이어(circle)를 먼저 그려도 아무 일도 일어나지 않는다.
      _draw(controller, 'circle');
      expect(shape.clearedLayers, 0);

      // 안쪽 레이어(triangle)를 그리면 한 겹 벗겨진다.
      _draw(controller, 'triangle');
      expect(shape.clearedLayers, 1);
      expect(shape.activeName, 'circle');
      expect(shape.isCleared, isFalse);
    });

    test('모든 레이어를 벗기면 플래시가 끝난 뒤 제거된다', () {
      final controller = _controllerFor(RunPresets.specialStage);
      controller.shapes.add(_shape(['circle', 'circle']));

      _draw(controller, 'circle');
      // 플래시 중에는 남아 있다.
      controller.update(const Duration(milliseconds: 200));
      _draw(controller, 'circle');
      expect(controller.shapes.single.isCleared, isTrue);

      controller.update(const Duration(milliseconds: 200));
      expect(controller.shapes, isEmpty);
    });
  });

  group('홀드 더블클리어 스킬', () {
    test('게이지가 부족하면 홀드되지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.setSkillHeld(true);
      expect(controller.isSkillActive, isFalse);
    });

    test('홀드 중 성공하면 다른 그룹까지 두 번 클리어된다', () {
      final controller = _controllerFor(RunPresets.stage1);

      // 게이지를 최소 발동치(0.3) 이상으로 채운다.
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle');
      expect(controller.isSkillReady, isTrue);

      // 플래시가 끝나 목록에서 빠지도록 시간을 흘린다.
      controller.update(const Duration(milliseconds: 200));
      expect(controller.shapes, isEmpty);

      controller.shapes.addAll([
        _shape(['circle'], id: 4, y: 100),
        _shape(['square'], id: 5, y: 300),
      ]);
      controller.setSkillHeld(true);
      expect(controller.isSkillActive, isTrue);

      _draw(controller, 'circle');

      // 그린 원뿐 아니라, 가장 아래에 있던 사각형까지 함께 클리어된다.
      expect(controller.shapes.every((s) => s.isCleared), isTrue);
    });

    test('홀드 중에는 게이지가 소모된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle');

      final before = controller.comboGauge;
      controller.setSkillHeld(true);
      controller.update(const Duration(milliseconds: 500));

      expect(controller.comboGauge, lessThan(before));
    });
  });

  group('난이도 표시', () {
    test('내부 보간은 소수, 표시는 내림한 정수', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.update(const Duration(seconds: 30));

      expect(controller.difficultyLevel, greaterThan(1.0));
      expect(controller.displayLevel, controller.difficultyLevel.floor());
    });
  });

  group('프리셋 파라미터', () {
    test('스테이지는 1분, 시작 라이프는 5', () {
      expect(RunPresets.stage1.duration, const Duration(minutes: 1));
      expect(RunPresets.stage1.startLives, 5);
      expect(RunPresets.raidCheckpoints.first.startLives, 5);
    });

    test('스테이지 구간별 테마가 지정된다', () {
      expect(RunPresets.stage1.resolvedTheme.name, '공장 초입');
      expect(RunPresets.boss10.resolvedTheme.name, '가속 라인');
    });

    test('다층 스테이지만 레이어 수가 1보다 크다', () {
      expect(RunPresets.stage1.maxLayers, 1);
      expect(RunPresets.specialStage.maxLayers, 2);
      expect(RunPresets.boss10.maxLayers, 3);
      expect(RunPresets.boss20.maxLayers, 4);
    });
  });
}
