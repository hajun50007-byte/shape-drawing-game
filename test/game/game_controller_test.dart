import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/core/shape_templates.dart';
import 'package:shape_drawing_game/core/stage_theme.dart';
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
    test('바깥 레이어부터 순서대로 벗겨진다', () {
      final controller = _controllerFor(RunPresets.specialStage);
      // index 0 = 안쪽(triangle), index 1 = 바깥(circle)
      controller.shapes.add(_shape(['triangle', 'circle']));
      final shape = controller.shapes.single;
      expect(shape.activeName, 'circle');

      // 안쪽 레이어(triangle)를 먼저 그려도 아무 일도 일어나지 않는다.
      _draw(controller, 'triangle');
      expect(shape.clearedLayers, 0);

      // 바깥 레이어(circle)를 그리면 한 겹 벗겨진다.
      _draw(controller, 'circle');
      expect(shape.clearedLayers, 1);
      expect(shape.activeName, 'triangle');
      expect(shape.isCleared, isFalse);
    });

    test('활성 레이어도 일반 도형과 함께 한 번에 클리어된다', () {
      final controller = _controllerFor(RunPresets.specialStage);
      // 다층 도형의 바깥 레이어가 삼각형이고, 일반 삼각형도 떠 있다.
      controller.shapes.addAll([
        _shape(['circle', 'triangle'], id: 1),
        _shape(['triangle'], id: 2, y: 150),
      ]);

      _draw(controller, 'triangle');

      final multi = controller.shapes.firstWhere((s) => s.id == 1);
      final plain = controller.shapes.firstWhere((s) => s.id == 2);
      expect(multi.clearedLayers, 1, reason: '다층 도형의 바깥 레이어가 벗겨져야 한다');
      expect(plain.isCleared, isTrue, reason: '일반 삼각형도 같이 제거되어야 한다');
      // 두 개를 클리어했으니 점수도 2개분을 받는다.
      expect(controller.score, greaterThan(0));
      expect(controller.comboGauge,
          closeTo(GameController.gaugeGainPerClear * 2, 1e-9));
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

  group('토글 더블클리어 스킬', () {
    test('게이지가 부족하면 켜지지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.toggleSkill();
      expect(controller.isSkillActive, isFalse);
    });

    test('다시 누르면 꺼진다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle');

      controller.toggleSkill();
      expect(controller.isSkillActive, isTrue);
      controller.toggleSkill();
      expect(controller.isSkillActive, isFalse);
    });

    test('게이지가 바닥나면 자동으로 꺼진다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle');
      controller.toggleSkill();
      expect(controller.isSkillActive, isTrue);

      // 게이지를 다 태울 만큼 시간을 흘린다.
      controller.update(const Duration(seconds: 5));
      expect(controller.comboGauge, 0);
      expect(controller.isSkillActive, isFalse);
    });

    test('켜진 상태에서 성공하면 다른 그룹까지 두 번 클리어된다', () {
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
      controller.toggleSkill();
      expect(controller.isSkillActive, isTrue);

      _draw(controller, 'circle');
      final square = controller.shapes.firstWhere((s) => s.id == 5);
      expect(square.isCleared, isFalse, reason: '두 번째 클리어는 딜레이 후에 발동한다');

      // 딜레이(1초)가 지나면 남아 있던 사각형까지 클리어된다.
      controller.update(GameController.doubleClearDelay);
      expect(square.isCleared, isTrue);
    });

    test('두 번째 클리어는 1초 딜레이 뒤에 발동한다', () {
      expect(GameController.doubleClearDelay, const Duration(seconds: 1));
    });

    test('켜져 있는 동안 게이지가 소모된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle');

      final before = controller.comboGauge;
      controller.toggleSkill();
      controller.update(const Duration(milliseconds: 500));

      expect(controller.comboGauge, lessThan(before));
    });
  });

  group('보스', () {
    test('난이도 5 스테이지에서 등장하며 크고 중앙에서 내려온다', () {
      final controller = _controllerFor(RunPresets.stage5);
      controller.update(const Duration(milliseconds: 16));

      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      expect(boss.layers.length, GameController.bossLayers);
      expect(boss.layers.length, 10);
      // 낙하 구역(400x500)의 짧은 변 기준 60%.
      expect(boss.size, closeTo(400 * GameController.bossSizeFraction, 1e-9));
      expect(boss.x, closeTo(200, 1e-9));
    });

    test('등장 연출 중에는 판정 대상이 아니고 낙하하지 않는다', () {
      final controller = _controllerFor(RunPresets.stage5);
      controller.update(const Duration(milliseconds: 16));

      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      expect(boss.isIntroPlaying, isTrue);
      expect(boss.isActionable, isFalse);

      final yDuringIntro = boss.y;
      controller.update(const Duration(milliseconds: 200));
      expect(boss.y, yDuringIntro, reason: '연출 중에는 내려오지 않는다');

      // 연출이 끝나면 판정 대상이 되고 아주 느리게 내려온다.
      controller.update(GameController.bossIntroDuration);
      expect(boss.isIntroPlaying, isFalse);
      expect(boss.isActionable, isTrue);
      controller.update(const Duration(milliseconds: 500));
      expect(boss.y, greaterThan(yDuringIntro));
    });

    test('화면에 한 번에 하나만 존재한다', () {
      final controller = _controllerFor(RunPresets.stage5);
      for (int i = 0; i < 200; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.where((s) => s.isBoss).length, lessThanOrEqualTo(1));
    });

    test('보스가 떠 있는 동안 일반 도형 스폰이 멈추고, 정리되면 재개된다', () {
      final controller = _controllerFor(RunPresets.stage5);
      controller.update(const Duration(milliseconds: 16));
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      // 보스전 동안에는 일반 도형이 늘지 않는다.
      for (int i = 0; i < 100; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.where((s) => !s.isBoss), isEmpty);

      // 보스를 없애면 다시 스폰이 재개된다.
      controller.shapes.remove(boss);
      for (int i = 0; i < 100; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.any((s) => !s.isBoss), isTrue);
    });

    test('보스 낙하 속도는 난이도와 무관한 고정값이다', () {
      final controller = _controllerFor(RunPresets.stage5);
      controller.update(const Duration(milliseconds: 16));
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      // 등장 연출을 끝낸다.
      controller.update(GameController.bossIntroDuration);
      final start = boss.y;
      controller.update(const Duration(seconds: 1));

      expect(boss.y - start, closeTo(GameController.bossFallSpeed, 1.0));
    });

    test('보스가 없는 스테이지에서는 등장하지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      for (int i = 0; i < 200; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.any((s) => s.isBoss), isFalse);
    });
  });

  group('도형별 통과 기준 보정', () {
    test('사각형만 기본 기준보다 8점 낮다', () {
      for (final level in [1.0, 3.0, 5.0, 7.0]) {
        final base = DifficultyTable.paramsFor(level).recognitionThreshold;
        expect(DifficultyTable.thresholdFor(level, 'square'), base - 8);
        expect(DifficultyTable.thresholdFor(level, 'circle'), base);
        expect(DifficultyTable.thresholdFor(level, 'triangle'), base);
      }
    });

    test('보정값이 없는 이름은 기본 기준을 그대로 쓴다', () {
      final base = DifficultyTable.paramsFor(1).recognitionThreshold;
      expect(DifficultyTable.thresholdFor(1, 'unknown'), base);
    });

    test('보정된 기준이 실제 판정에 적용된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['square']));

      _draw(controller, 'square');

      expect(controller.shapes.single.isCleared, isTrue);
      expect(controller.lastAppliedThreshold,
          DifficultyTable.paramsFor(RunPresets.stage1.minDifficulty)
                  .recognitionThreshold -
              8);
    });
  });

  group('쌍둥이 보스', () {
    List<FallingShape> twinsOf(GameController c) =>
        c.shapes.where((s) => s.isBoss).toList();

    GameController spawnedTwins() {
      final controller = _controllerFor(RunPresets.stage10);
      controller.update(const Duration(milliseconds: 16));
      return controller;
    }

    test('7층짜리 둘이 좌우에서 동시에 등장한다', () {
      final controller = spawnedTwins();
      final twins = twinsOf(controller);

      expect(twins.length, 2);
      for (final t in twins) {
        expect(t.layers.length, GameController.twinBossLayers);
        expect(t.layers.length, 7);
      }
      // 좌측 25% / 우측 75% 지점.
      expect(twins.map((t) => t.x), unorderedEquals([100.0, 300.0]));
    });

    test('5단계 보스보다 작다', () {
      final single = _controllerFor(RunPresets.stage5)
        ..update(const Duration(milliseconds: 16));
      final twin = spawnedTwins();

      final singleSize = single.shapes.firstWhere((s) => s.isBoss).size;
      expect(twinsOf(twin).first.size, lessThan(singleSize));
    });

    test('두 보스의 도형 시퀀스가 서로 다르다', () {
      final twins = twinsOf(spawnedTwins());
      expect(twins[0].layers, isNot(equals(twins[1].layers)));
    });

    test('좌우 이동 없이 수직으로만 하강한다', () {
      final controller = spawnedTwins();
      final twins = twinsOf(controller);
      final xs = twins.map((t) => t.x).toList();

      controller.update(GameController.bossIntroDuration);
      controller.update(const Duration(seconds: 2));

      expect(twins.map((t) => t.x).toList(), xs);
    });

    test('한쪽이 먼저 쓰러지면 남은 쪽의 남은 층수가 10층으로 늘어난다', () {
      final controller = spawnedTwins();
      final twins = twinsOf(controller);
      final victim = twins[0];
      final survivor = twins[1];

      // 남은 쪽에서 두 층을 미리 벗겨 진행도를 만들어 둔다.
      survivor.clearedLayers = 2;
      expect(survivor.remainingLayers, 5);

      // 한쪽을 전부 제거한다.
      victim.clearedLayers = victim.layers.length;
      controller.update(const Duration(milliseconds: 16));

      expect(survivor.remainingLayers, GameController.twinBossReinforcedLayers);
      expect(survivor.clearedLayers, 2, reason: '이미 진행된 층은 유지된다');
      expect(controller.status, GameStatus.playing);
    });

    test('둘 다 제거해야 스테이지가 클리어된다', () {
      final controller = spawnedTwins();
      final twins = twinsOf(controller);

      twins[0].clearedLayers = twins[0].layers.length;
      controller.update(const Duration(milliseconds: 16));
      expect(controller.status, GameStatus.playing,
          reason: '한쪽만 제거해서는 클리어되지 않는다');

      final survivor =
          controller.shapes.firstWhere((s) => s.isBoss && !s.isCleared);
      survivor.clearedLayers = survivor.layers.length;
      controller.update(const Duration(milliseconds: 16));

      expect(controller.status, GameStatus.cleared);
    });
  });

  group('난이도 곡선', () {
    test('낙하 속도가 최대치의 65%에 못 미치면 동시 등장 개수가 기본값', () {
      final rampSpeed = DifficultyTable.shapeRampStartSpeed;
      expect(rampSpeed, closeTo(DifficultyTable.maxFallSpeed * 0.65, 1e-9));

      for (final level in [1.0, 2.0, 3.0]) {
        final params = DifficultyTable.paramsFor(level);
        expect(params.fallSpeed, lessThan(rampSpeed));
        expect(params.maxSimultaneousShapes,
            DifficultyTable.baseSimultaneousShapes);
      }
    });

    test('65%를 넘어서면 레벨 10까지 개수가 단조 증가해 상한에 도달한다', () {
      final startLevel = DifficultyTable.shapeRampStartLevel;
      // 80 -> 200 구간에서 130(65%)은 레벨 3.5.
      expect(startLevel, closeTo(3.5, 1e-9));

      var previous = DifficultyTable.baseSimultaneousShapes;
      for (double level = startLevel; level <= 10.0; level += 0.5) {
        final count = DifficultyTable.paramsFor(level).maxSimultaneousShapes;
        expect(count, greaterThanOrEqualTo(previous), reason: 'level $level');
        previous = count;
      }
      expect(DifficultyTable.paramsFor(10).maxSimultaneousShapes,
          DifficultyTable.simultaneousShapesCap);
    });

    test('최대 낙하 속도는 기존 값(200)을 유지한다', () {
      expect(DifficultyTable.maxFallSpeed, 200);
      expect(DifficultyTable.paramsFor(7).fallSpeed, 200);
      expect(DifficultyTable.paramsFor(10).fallSpeed, 200);
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
      // 1~5단계는 "공장 초입", 6단계부터 "가속 라인".
      expect(RunPresets.stage1.resolvedTheme.name, '공장 초입');
      expect(RunPresets.stage5.resolvedTheme.name, '공장 초입');
      expect(StageTheme.forDifficulty(5).name, '공장 초입');
      expect(StageTheme.forDifficulty(6).name, '가속 라인');
    });

    test('일반 다층 도형은 최대 2층까지만 쓴다', () {
      expect(RunPresets.stage1.maxLayers, 1);
      expect(RunPresets.specialStage.maxLayers, 2);
      expect(RunPresets.stage5.maxLayers, 2);
    });

    test('보스는 난이도 5부터 등장하며 레이드에도 같은 규칙이 적용된다', () {
      expect(RunPresets.stage1.bossFromDifficulty, isNull);
      expect(RunPresets.stage5.bossFromDifficulty, 5);
      for (final raid in RunPresets.raidCheckpoints) {
        expect(raid.bossFromDifficulty, 5);
      }
    });
  });
}
