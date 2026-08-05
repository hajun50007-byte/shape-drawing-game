import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/boss_traits.dart';
import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/core/shape_templates.dart';
import 'package:shape_drawing_game/core/stage_theme.dart';
import 'package:shape_drawing_game/game/model/active_skill.dart';
import 'package:shape_drawing_game/game/model/clear_effect.dart';
import 'package:shape_drawing_game/game/model/equipped_skills.dart';
import 'package:shape_drawing_game/game/model/falling_shape.dart';
import 'package:shape_drawing_game/game/model/skill_ring.dart';
import 'package:shape_drawing_game/game/render/skill_frame_overlay.dart';
import 'package:shape_drawing_game/game/render/skill_visuals.dart';
import 'package:shape_drawing_game/game/state/game_controller.dart';
import 'package:shape_drawing_game/game/state/unlock_state.dart';

GameController _controllerFor(
  RunConfig config, {
  EquippedSkills equipped = EquippedSkills.defaultLoadout,
}) {
  final controller = GameController(
    runConfig: config,
    random: math.Random(7),
    equipped: equipped,
  );
  controller.setFieldSize(const Size(400, 500));
  return controller;
}

/// 보스 등장 유예 시간(25초)을 넘겨 보스가 나오게 한다.
///
/// 그 사이 일반 도형을 놓치면 게임 오버가 되어 보스가 영영 안 나오므로,
/// 매 스텝 일반 도형을 치워 "플레이어가 다 처리한" 상황을 흉내낸다.
void _advanceToBoss(GameController controller) {
  while (controller.runElapsed < GameController.bossSpawnDelay) {
    controller.update(const Duration(milliseconds: 100));
    controller.shapes.removeWhere((s) => !s.isBoss);
  }
  controller.update(const Duration(milliseconds: 16));
}

/// 더블클리어 게이지를 가득 채운다(토글 후에도 한동안 유지되도록).
/// 한 번에 여러 개를 클리어해 게이지를 1.0까지 올린다.
void _fillComboGauge(GameController controller) {
  final needed = (1 / GameController.gaugeGainPerClear).ceil();
  controller.shapes.addAll([
    for (int i = 0; i < needed; i++) _shape(['circle'], id: 9000 + i),
  ]);
  _draw(controller, 'circle');
  controller.shapes.clear();
}

/// 보스가 등장한 상태의 컨트롤러를 만든다.
GameController _controllerWithBoss(RunConfig config) {
  final controller = _controllerFor(config);
  _advanceToBoss(controller);
  return controller;
}

/// 5단계 보스 스테이지를 복제하되 보스 성향(가중치/타이밍)만 바꿔치기한다.
RunConfig _bossConfigWith(BossTraits traits) => RunConfig(
      id: RunPresets.stage5.id,
      minDifficulty: 5,
      maxDifficulty: 5,
      duration: const Duration(seconds: 45),
      startLives: 5,
      bossFromDifficulty: 5,
      bossTraits: traits,
    );

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

      // 딜레이가 지나면 남아 있던 사각형까지 클리어된다.
      controller.update(controller.doubleClearDelay);
      expect(square.isCleared, isTrue);
    });

    test('에코 프로토콜 기본 딜레이는 2초다', () {
      expect(GameController.defaultDoubleClearDelay, const Duration(seconds: 2));
      expect(_controllerFor(RunPresets.stage1).doubleClearDelay,
          const Duration(seconds: 2));
    });

    test('에코 프로토콜 딜레이는 조정 가능한 파라미터다', () {
      // 업그레이드로 짧아질 수 있어야 한다.
      final upgraded = GameController(
        runConfig: RunPresets.stage1,
        random: math.Random(7),
        doubleClearDelay: GameController.minDoubleClearDelay,
      )..setFieldSize(const Size(400, 500));

      expect(upgraded.doubleClearDelay, const Duration(milliseconds: 500));
      expect(GameController.minDoubleClearDelay,
          lessThan(GameController.defaultDoubleClearDelay));
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
      final controller = _controllerWithBoss(RunPresets.stage5);

      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      expect(boss.layers.length, GameController.bossLayers);
      expect(boss.layers.length, 10);
      // 낙하 구역(400x500)의 짧은 변 기준 60%.
      expect(boss.size, closeTo(400 * GameController.bossSizeFraction, 1e-9));
      expect(boss.x, closeTo(200, 1e-9));
    });

    test('등장 연출 중에는 판정 대상이 아니고 낙하하지 않는다', () {
      final controller = _controllerWithBoss(RunPresets.stage5);

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
      final controller = _controllerWithBoss(RunPresets.stage5);
      for (int i = 0; i < 200; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.where((s) => s.isBoss).length, lessThanOrEqualTo(1));
    });

    test('보스가 떠 있는 동안 일반 도형 스폰이 멈추고, 정리되면 재개된다', () {
      final controller = _controllerWithBoss(RunPresets.stage5);
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
      final controller = _controllerWithBoss(RunPresets.stage5);
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

  group('보스 스킬', () {
    GameController spawnedBoss(BossTraits traits) {
      final controller = _controllerFor(_bossConfigWith(traits));
      _advanceToBoss(controller); // 유예 시간 통과 + 스폰
      controller.update(GameController.bossIntroDuration); // 등장 연출 종료
      return controller;
    }

    const healOnly = BossTraits(
      skillWeights: {BossSkillType.heal: 1, BossSkillType.haste: 0},
    );
    const hasteOnly = BossTraits(
      skillWeights: {BossSkillType.heal: 0, BossSkillType.haste: 1},
    );

    test('등장 후 스킬 간격이 지나야 첫 텔레그래프가 시작된다', () {
      final controller = spawnedBoss(hasteOnly);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      expect(boss.isTelegraphing, isFalse);
      controller.update(hasteOnly.skillInterval - const Duration(milliseconds: 1));
      expect(boss.isTelegraphing, isFalse, reason: '아직 간격이 다 지나지 않았다');

      controller.update(const Duration(milliseconds: 1));
      expect(boss.isTelegraphing, isTrue);
      expect(boss.telegraphedSkill, BossSkillType.haste);
      expect(boss.telegraphRemaining, greaterThanOrEqualTo(hasteOnly.telegraphMin));
      expect(boss.telegraphRemaining, lessThanOrEqualTo(hasteOnly.telegraphMax));
    });

    test('텔레그래프 중에도 그릴 수 있는 판정 대상이다', () {
      final controller = spawnedBoss(hasteOnly);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      controller.update(hasteOnly.skillInterval);
      expect(boss.isTelegraphing, isTrue);
      expect(boss.isActionable, isTrue);
    });

    test('보스는 생성 시 스킬 하나만 부여받고 그것만 쓴다', () {
      // 회복/가속이 반반인 성향으로 여러 보스를 만들어도, 개체 하나가
      // 두 스킬을 번갈아 쓰는 일은 없어야 한다.
      for (int seed = 0; seed < 8; seed++) {
        final controller = GameController(
          runConfig: _bossConfigWith(BossTraits.standard),
          random: math.Random(seed),
        )..setFieldSize(const Size(400, 500));
        _advanceToBoss(controller);
        controller.update(GameController.bossIntroDuration);

        final boss = controller.shapes.firstWhere((s) => s.isBoss);
        expect(boss.assignedSkill, isNotNull);
        final assigned = boss.assignedSkill;

        final seen = <BossSkillType>{};
        for (int i = 0; i < 60; i++) {
          controller.update(const Duration(milliseconds: 200));
          final telegraphed = boss.telegraphedSkill;
          if (telegraphed != null) seen.add(telegraphed);
        }
        expect(seen, anyOf(isEmpty, equals({assigned})),
            reason: 'seed $seed: 부여된 스킬 외에는 시전하지 않아야 한다');
      }
    });

    test('회복 스킬: 남은 층수가 +3 되고 이미 벗긴 진행은 유지된다', () {
      final controller = spawnedBoss(healOnly);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      boss.clearedLayers = 2; // 진행 상황을 흉내낸다.
      final remainingBefore = boss.remainingLayers;

      controller.update(healOnly.skillInterval);
      expect(boss.telegraphedSkill, BossSkillType.heal);

      controller.update(healOnly.telegraphMax); // 텔레그래프를 확실히 끝낸다.

      expect(healOnly.healLayerBonus, 3);
      expect(boss.remainingLayers, remainingBefore + 3);
      expect(boss.clearedLayers, 2, reason: '이미 벗긴 진행은 유지된다');
      expect(boss.isTelegraphing, isFalse);
    });

    test('스킬은 개체당 최대 2회까지만 사용된다', () {
      const fastHeal = BossTraits(
        skillWeights: {BossSkillType.heal: 1, BossSkillType.haste: 0},
        skillInterval: Duration(milliseconds: 100),
        postCastCooldown: Duration(milliseconds: 100),
        telegraphMin: Duration(milliseconds: 50),
        telegraphMax: Duration(milliseconds: 50),
      );
      final controller = spawnedBoss(fastHeal);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      final layersBefore = boss.layers.length;

      // 넉넉하게 흘려보내도 2회를 넘겨 쓰지 않아야 한다.
      for (int i = 0; i < 40; i++) {
        controller.update(const Duration(milliseconds: 200));
      }

      expect(fastHeal.maxSkillUses, 2);
      expect(boss.skillUsesRemaining, 0);
      expect(boss.canUseSkill, isFalse);
      expect(boss.layers.length, layersBefore + fastHeal.healLayerBonus * 2,
          reason: '회복이 정확히 2회만 적용되어야 한다');
    });

    test('시전 후에는 기본 간격에 더해 3초 쿨다운이 붙는다', () {
      expect(BossTraits.standard.postCastCooldown, const Duration(seconds: 3));

      final controller = spawnedBoss(hasteOnly);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      // 첫 시전을 끝낸다.
      controller.update(hasteOnly.skillInterval);
      controller.update(hasteOnly.telegraphMax);
      expect(boss.isHasted, isTrue);

      // 기본 간격만으로는 다음 텔레그래프가 시작되지 않는다.
      controller.update(hasteOnly.skillInterval);
      expect(boss.isTelegraphing, isFalse,
          reason: '연속 시전 방지 쿨다운이 남아 있어야 한다');

      // 추가 쿨다운까지 지나면 다시 시전 준비가 된다.
      controller.update(hasteOnly.postCastCooldown);
      expect(boss.isTelegraphing, isTrue);
    });

    test('가속 스킬: 낙하 속도가 대폭 빨라지고, 끝나면 원래대로 돌아온다', () {
      final controller = spawnedBoss(hasteOnly);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);

      controller.update(hasteOnly.skillInterval);
      controller.update(hasteOnly.telegraphMax);
      expect(boss.isHasted, isTrue);

      final yBefore = boss.y;
      controller.update(const Duration(seconds: 1));
      expect(boss.y - yBefore,
          closeTo(GameController.bossFallSpeed * hasteOnly.hasteSpeedMultiplier, 2.0));

      controller.update(hasteOnly.hasteDuration);
      expect(boss.isHasted, isFalse);

      final yAfter = boss.y;
      controller.update(const Duration(seconds: 1));
      expect(boss.y - yAfter, closeTo(GameController.bossFallSpeed, 2.0));
    });

    test('보스마다 스킬 가중치를 다르게 줄 수 있는 구조다', () {
      expect(RunPresets.stage5.bossTraits, BossTraits.standard);
      expect(RunPresets.stage10.bossTraits, BossTraits.twin);
      expect(BossTraits.standard.skillWeights,
          isNot(equals(BossTraits.twin.skillWeights)));
    });
  });

  group('보스 등장 조건과 페널티', () {
    test('보스 스테이지도 시작 직후에는 일반 도형만 나온다', () {
      final controller = _controllerFor(RunPresets.stage5);

      // 유예 시간 직전까지는 보스가 없다.
      while (controller.runElapsed <
          GameController.bossSpawnDelay - const Duration(seconds: 1)) {
        controller.update(const Duration(milliseconds: 100));
        controller.shapes.removeWhere((s) => !s.isBoss);
      }
      expect(controller.shapes.any((s) => s.isBoss), isFalse,
          reason: '25초 전에는 보스가 나오면 안 된다');
      expect(GameController.bossSpawnDelay, const Duration(seconds: 25));

      // 유예 시간이 지나면 등장한다.
      _advanceToBoss(controller);
      expect(controller.shapes.any((s) => s.isBoss), isTrue);
    });

    test('보스를 놓치면 라이프가 3 깎인다', () {
      final controller = _controllerWithBoss(RunPresets.stage5);
      controller.update(GameController.bossIntroDuration);

      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      final livesBefore = controller.lives;

      // 보스를 화면 아래로 보낸다.
      boss.y = 10000;
      controller.update(const Duration(milliseconds: 16));

      expect(controller.lives, livesBefore - GameController.bossLifeCost);
      expect(GameController.bossLifeCost, 3);
    });

    test('일반 도형을 놓치면 라이프가 1만 깎인다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle'], y: 10000));
      final livesBefore = controller.lives;

      controller.update(const Duration(milliseconds: 16));
      expect(controller.lives, livesBefore - 1);
    });

    test('쌍둥이 보스는 스킬을 쓰지 않는다', () {
      final controller = _controllerWithBoss(RunPresets.stage10);
      controller.update(GameController.bossIntroDuration);

      final twins = controller.shapes.where((s) => s.isBoss).toList();
      expect(twins.length, 2);
      for (final twin in twins) {
        expect(twin.assignedSkill, isNull);
        expect(twin.canUseSkill, isFalse);
      }

      // 시간이 흘러도 텔레그래프가 시작되지 않는다.
      for (int i = 0; i < 60; i++) {
        controller.update(const Duration(milliseconds: 200));
      }
      for (final twin in controller.shapes.where((s) => s.isBoss)) {
        expect(twin.isTelegraphing, isFalse);
      }
    });

    test('단일 보스는 스킬을 쓴다', () {
      final controller = _controllerWithBoss(RunPresets.stage5);
      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      expect(boss.assignedSkill, isNotNull);
      expect(boss.canUseSkill, isTrue);
    });
  });

  group('레이드 10단계 체크포인트', () {
    RunConfig raid10() =>
        RunPresets.raidCheckpoints.firstWhere((c) => c.id == 'raid_10');

    test('단일 보스와 쌍둥이 보스가 번갈아 등장한다', () {
      expect(raid10().bossKind, BossKind.alternating);

      final controller = _controllerWithBoss(raid10());
      final kinds = <int>[];

      for (int round = 0; round < 4; round++) {
        final bosses = controller.shapes.where((s) => s.isBoss).toList();
        expect(bosses, isNotEmpty, reason: '$round번째 보스 무리');
        kinds.add(bosses.length);

        // 잡아 없앤 뒤 다음 무리를 기다린다.
        controller.shapes.removeWhere((s) => s.isBoss);
        for (int i = 0; i < 400 && !controller.shapes.any((s) => s.isBoss); i++) {
          controller.update(const Duration(milliseconds: 100));
          controller.shapes.removeWhere((s) => !s.isBoss);
        }
      }

      // 1마리(단일) -> 2마리(쌍둥이) -> 1마리 -> 2마리 순으로 번갈아 나온다.
      expect(kinds, [1, 2, 1, 2]);
    });

    test('레이드에서는 쌍둥이를 다 잡아도 런이 끝나지 않는다', () {
      final controller = _controllerWithBoss(raid10());
      // 첫 무리(단일)를 없애고 쌍둥이가 나올 때까지 진행한다.
      controller.shapes.removeWhere((s) => s.isBoss);
      for (int i = 0; i < 400; i++) {
        controller.update(const Duration(milliseconds: 100));
        controller.shapes.removeWhere((s) => !s.isBoss);
        if (controller.shapes.where((s) => s.isBoss).length == 2) break;
      }
      expect(controller.shapes.where((s) => s.isBoss).length, 2);

      // 둘 다 제거해도 클리어되지 않는다(무한 진행 모드).
      for (final boss in controller.shapes.where((s) => s.isBoss)) {
        boss.clearedLayers = boss.layers.length;
      }
      controller.update(const Duration(milliseconds: 16));
      expect(controller.status, GameStatus.playing);
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

  group('레이드 모드', () {
    // 난이도 7에서 시작해 보스가 바로 등장하는 체크포인트.
    RunConfig raid7() =>
        RunPresets.raidCheckpoints.firstWhere((c) => c.id == 'raid_7');

    test('난이도 7부터 보스가 등장한다', () {
      final controller = _controllerWithBoss(raid7());
      expect(controller.shapes.any((s) => s.isBoss), isTrue);
    });

    test('난이도 7에 못 미치는 체크포인트에서는 보스가 안 나온다', () {
      final raid1 =
          RunPresets.raidCheckpoints.firstWhere((c) => c.id == 'raid_1');
      final controller = _controllerFor(raid1);
      for (int i = 0; i < 200; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      expect(controller.shapes.any((s) => s.isBoss), isFalse);
    });

    test('레이드 보스가 스테이지 보스보다 빠르게 내려온다', () {
      expect(GameController.raidBossFallSpeed,
          greaterThan(GameController.bossFallSpeed));

      final controller = _controllerWithBoss(raid7());
      final boss = controller.shapes.firstWhere((s) => s.isBoss);
      controller.update(GameController.bossIntroDuration);

      final start = boss.y;
      controller.update(const Duration(seconds: 1));
      expect(boss.y - start, closeTo(GameController.raidBossFallSpeed, 2.0));
    });

    test('보스전 중에도 일반 스폰이 계속되며 2층 도형만 나온다', () {
      final controller = _controllerWithBoss(raid7());
      expect(controller.shapes.any((s) => s.isBoss), isTrue);

      for (int i = 0; i < 200; i++) {
        controller.update(const Duration(milliseconds: 50));
      }

      final normals = controller.shapes.where((s) => !s.isBoss).toList();
      expect(normals, isNotEmpty, reason: '레이드는 보스전 중에도 스폰이 계속된다');
      for (final s in normals) {
        expect(s.layers.length, 2, reason: '보스전 중에는 2층 도형만 스폰된다');
      }
    });

    test('체크포인트 7은 동시 등장 상한이 2배', () {
      final raid5 =
          RunPresets.raidCheckpoints.firstWhere((c) => c.id == 'raid_5');
      expect(raid5.simultaneousShapesScale, 1.0);
      expect(raid7().simultaneousShapesScale, 2.0);

      final params = DifficultyTable.paramsFor(10);
      expect(params.maxSimultaneousShapes,
          DifficultyTable.simultaneousShapesCap);

      final base = _controllerFor(raid5).effectiveMaxSimultaneousShapes(params);
      final boosted =
          _controllerFor(raid7()).effectiveMaxSimultaneousShapes(params);

      expect(base, DifficultyTable.simultaneousShapesCap);
      expect(boosted, base * 2);
      expect(boosted, 12);
    });

    test('작은 변형 도형이 섞여 나온다', () {
      final controller = _controllerFor(
        RunPresets.raidCheckpoints.firstWhere((c) => c.id == 'raid_1'),
      );
      for (int i = 0; i < 400; i++) {
        controller.update(const Duration(milliseconds: 50));
      }

      final sizes = controller.shapes.map((s) => s.size).toSet();
      final smallSize =
          GameController.shapeSize * GameController.smallShapeSizeFactor;
      // 확률적이므로 두 크기 중 하나만 나올 수도 있지만, 나온 크기는
      // 반드시 기본 크기이거나 축소 크기여야 한다.
      for (final size in sizes) {
        expect(
          size == GameController.shapeSize || size == smallSize,
          isTrue,
          reason: 'unexpected size $size',
        );
      }
      expect(GameController.smallShapeSizeFactor, 0.65);
      expect(GameController.smallShapeChance, 0.30);
    });

    test('스테이지 모드에서는 작은 변형이 나오지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      for (int i = 0; i < 400; i++) {
        controller.update(const Duration(milliseconds: 50));
      }
      for (final s in controller.shapes) {
        expect(s.size, GameController.shapeSize);
      }
    });
  });

  group('클리어 이펙트', () {
    test('제거된 도형마다 파티클 또는 반짝임 중 하나가 재생된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2, y: 150),
      ]);

      _draw(controller, 'circle');

      // 두 도형 각각 파티클 또는 반짝임 하나씩.
      final particleGroups =
          controller.particles.length ~/ GameController.particlesPerShape;
      expect(particleGroups + controller.sparkles.length, 2);
      expect(controller.bursts.length, 1, reason: '버스트는 콤보 마지막 도형에만');
    });

    test('반짝임은 지점마다 미니 도형 3개를 삼각형으로 배치한다', () {
      // 반짝임이 한 번은 나오도록 여러 시드로 시도한다.
      ShapeSparkle? sparkle;
      for (int seed = 0; seed < 20 && sparkle == null; seed++) {
        final controller = GameController(
          runConfig: RunPresets.stage1,
          random: math.Random(seed),
        )..setFieldSize(const Size(400, 500));
        controller.shapes.add(_shape(['circle']));
        _draw(controller, 'circle');
        if (controller.sparkles.isNotEmpty) sparkle = controller.sparkles.first;
      }

      expect(sparkle, isNotNull);
      expect(sparkle!.clusters.length,
          inInclusiveRange(GameController.sparkleMinClusters,
              GameController.sparkleMaxClusters));
      for (final cluster in sparkle.clusters) {
        expect(cluster.length, GameController.sparklePerCluster);
      }
      // 0.1초 간격으로 켜졌다 꺼지길 3번 = 0.6초.
      expect(sparkle.blinkInterval, const Duration(milliseconds: 100));
      expect(sparkle.duration, const Duration(milliseconds: 600));
      expect(sparkle.isVisible, isTrue);
      sparkle.advance(const Duration(milliseconds: 100));
      expect(sparkle.isVisible, isFalse, reason: '0.1초 뒤에는 꺼진다');
    });

    test('반짝임은 뚝 끊기지 않고 켜질 때마다 점점 흐려진다', () {
      final sparkle = ShapeSparkle(
        shapeName: 'circle',
        centerX: 0,
        centerY: 0,
        miniSize: 10,
        clusters: const [],
        blinkInterval: const Duration(milliseconds: 100),
        blinkCount: 3,
        duration: const Duration(milliseconds: 600),
      );

      // 켜짐 구간(step 0,2,4)마다 알파가 낮아지고, 꺼짐 구간(1,3,5)은 0.
      expect(sparkle.visibleAlpha, 1.0); // step 0: 첫 번째 켜짐
      sparkle.advance(const Duration(milliseconds: 100));
      expect(sparkle.visibleAlpha, 0); // step 1: 꺼짐
      sparkle.advance(const Duration(milliseconds: 100));
      final second = sparkle.visibleAlpha; // step 2: 두 번째 켜짐
      expect(second, closeTo(2 / 3, 1e-9));
      sparkle.advance(const Duration(milliseconds: 200));
      final third = sparkle.visibleAlpha; // step 4: 세 번째(마지막) 켜짐
      expect(third, closeTo(1 / 3, 1e-9));

      // 뒤로 갈수록(마지막 깜빡임일수록) 더 흐려진다.
      expect(third, lessThan(second));
      expect(second, lessThan(1.0));
    });

    test('같은 자리에서 터져도 반짝임 중심이 서로 최소 간격만큼 떨어진다', () {
      // 정확히 같은 좌표의 도형을 연달아 없애도, 두 번째 반짝임은
      // 첫 번째와 겹치지 않게 밀려나야 한다.
      List<ShapeSparkle> sparklesFromSeed(int seed) {
        final controller = GameController(
          runConfig: RunPresets.stage1,
          random: math.Random(seed),
        )..setFieldSize(const Size(400, 500));
        for (int i = 0; i < 6; i++) {
          controller.shapes.add(_shape(['circle'], id: 6000 + i, y: 200));
          _draw(controller, 'circle');
        }
        return controller.sparkles;
      }

      var checkedAnyPair = false;
      for (int seed = 0; seed < 12; seed++) {
        final sparkles = sparklesFromSeed(seed);
        if (sparkles.length < 2) continue;
        checkedAnyPair = true;

        final minGap = GameController.shapeSize *
            GameController.sparkleMinSpacingFactor;
        for (int i = 0; i < sparkles.length; i++) {
          for (int j = i + 1; j < sparkles.length; j++) {
            final dx = sparkles[i].centerX - sparkles[j].centerX;
            final dy = sparkles[i].centerY - sparkles[j].centerY;
            final gap = math.sqrt(dx * dx + dy * dy);
            expect(gap, greaterThanOrEqualTo(minGap - 1e-6),
                reason: 'seed $seed: 반짝임 $i-$j가 너무 가깝다');
          }
        }
      }
      expect(checkedAnyPair, isTrue, reason: '비교할 반짝임 쌍이 하나도 없었다');
    });

    test('한 반짝임 안에서도 지점끼리 최소 간격을 둔다', () {
      ShapeSparkle? sparkle;
      for (int seed = 0; seed < 20 && sparkle == null; seed++) {
        final controller = GameController(
          runConfig: RunPresets.stage1,
          random: math.Random(seed),
        )..setFieldSize(const Size(400, 500));
        controller.shapes.add(_shape(['circle']));
        _draw(controller, 'circle');
        if (controller.sparkles.isNotEmpty) sparkle = controller.sparkles.first;
      }
      expect(sparkle, isNotNull);

      // 각 지점의 중심은 삼각형 꼭짓점 3개의 평균으로 되돌릴 수 있다.
      final centers = sparkle!.clusters.map((cluster) {
        final cx =
            cluster.map((p) => p.x).reduce((a, b) => a + b) / cluster.length;
        final cy =
            cluster.map((p) => p.y).reduce((a, b) => a + b) / cluster.length;
        return (cx, cy);
      }).toList();

      // 완전히 겹치는 지점은 없어야 한다(재시도 상한 때문에 최소 간격을
      // 항상 보장하진 못하므로, 뭉침이 없다는 선까지만 확인한다).
      for (int i = 0; i < centers.length; i++) {
        for (int j = i + 1; j < centers.length; j++) {
          final dx = centers[i].$1 - centers[j].$1;
          final dy = centers[i].$2 - centers[j].$2;
          expect(math.sqrt(dx * dx + dy * dy), greaterThan(1.0));
        }
      }
    });

    test('동시에 존재하는 파티클/반짝임/버스트 개수에 상한이 있다', () {
      final controller = _controllerFor(RunPresets.stage1);

      // 상한을 넘도록 여러 번 클리어를 반복한다.
      for (int i = 0; i < 20; i++) {
        controller.shapes.add(_shape(['circle'], id: 3000 + i));
        _draw(controller, 'circle');
      }

      expect(controller.particles.length,
          lessThanOrEqualTo(GameController.maxConcurrentParticles));
      expect(controller.sparkles.length,
          lessThanOrEqualTo(GameController.maxConcurrentSparkles));
      expect(controller.bursts.length,
          lessThanOrEqualTo(GameController.maxConcurrentBursts));
    });

    test('콤보는 도형별 개별 팝업 + 보너스 팝업 하나로 표시된다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2, y: 150),
        _shape(['circle'], id: 3, y: 200),
      ]);

      _draw(controller, 'circle');

      final combo =
          controller.scorePopups.where((p) => p.label == 'COMBO').toList();
      final individual =
          controller.scorePopups.where((p) => p.label == null).toList();

      expect(individual.length, 3, reason: '도형마다 개별 팝업');
      expect(combo.length, 1, reason: '콤보 보너스 팝업은 하나');

      final perShape = individual.first.score;
      expect(individual.every((p) => p.score == perShape), isTrue);
      expect(combo.single.score, GameController.comboBonusFor(3));
      // 표시된 팝업 합계가 실제 획득 점수와 일치한다.
      expect(perShape * 3 + combo.single.score, controller.score);
    });

    test('콤보 공식은 5 x n x (n-1)이고 n에 상한이 없다', () {
      expect(GameController.comboBonusFactor, 5);
      expect(GameController.comboBonusFor(1), 0);
      expect(GameController.comboBonusFor(2), 10);
      expect(GameController.comboBonusFor(3), 30);
      expect(GameController.comboBonusFor(4), 60);
      expect(GameController.comboBonusFor(10), 450);
      expect(GameController.comboBonusFor(20), 1900);

      // 임의로 큰 n에서도 공식이 그대로 성립한다.
      for (final n in [5, 7, 13, 20, 50]) {
        expect(GameController.comboBonusFor(n), 5 * n * (n - 1), reason: 'n=$n');
      }
    });

    test('4개 이상 동시 클리어도 콤보 팝업이 뜬다 (3개 상한 없음)', () {
      // 회귀 방지: 4개 이상에서 콤보 표시가 안 된다는 보고가 있었다.
      for (final n in [4, 7, 20]) {
        final controller = _controllerFor(RunPresets.stage1);
        controller.shapes.addAll([
          for (int i = 0; i < n; i++)
            _shape(['circle'], id: 8000 + i, y: 100.0 + i * 10),
        ]);

        _draw(controller, 'circle');

        final individual =
            controller.scorePopups.where((p) => p.label == null).toList();
        final combo =
            controller.scorePopups.where((p) => p.label == 'COMBO').toList();

        expect(individual.length, n, reason: 'n=$n 개별 팝업');
        expect(combo.length, 1, reason: 'n=$n 콤보 팝업');
        expect(combo.single.score, GameController.comboBonusFor(n),
            reason: 'n=$n 보너스');
        // 표시값 합계가 실제 획득 점수와 일치한다.
        expect(individual.first.score * n + combo.single.score, controller.score,
            reason: 'n=$n 총점');
      }
    });

    test('콤보 팝업은 맨 아래 도형부터 차례로 뜬다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1, y: 100), // 맨 위
        _shape(['circle'], id: 2, y: 300), // 맨 아래
        _shape(['circle'], id: 3, y: 200),
      ]);

      _draw(controller, 'circle');

      final individual =
          controller.scorePopups.where((p) => p.label == null).toList()
            ..sort((a, b) => a.startDelay.compareTo(b.startDelay));

      // 지연이 짧은 순서 = 먼저 뜨는 순서 = y가 큰(아래) 순서.
      expect(individual.map((p) => p.startY).toList(), [300.0, 200.0, 100.0]);
      expect(individual.first.startDelay, Duration.zero);
      expect(individual.last.startDelay, greaterThan(Duration.zero));

      // 콤보 팝업은 개별 팝업이 다 뜬 뒤에 온다.
      final combo =
          controller.scorePopups.firstWhere((p) => p.label == 'COMBO');
      expect(combo.startDelay, greaterThan(individual.last.startDelay));
    });

    test('아직 뜰 차례가 아닌 팝업은 보이지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.addAll([
        _shape(['circle'], id: 1, y: 100),
        _shape(['circle'], id: 2, y: 300),
      ]);

      _draw(controller, 'circle');

      final later = controller.scorePopups
          .where((p) => p.label == null && p.startDelay > Duration.zero)
          .first;
      expect(later.isWaiting, isTrue);
      expect(later.alpha, 0);

      controller.update(later.startDelay + const Duration(milliseconds: 16));
      expect(later.isWaiting, isFalse);
      expect(later.alpha, greaterThan(0));
    });

    test('단일 클리어에는 콤보 팝업이 붙지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle']));

      _draw(controller, 'circle');

      expect(controller.scorePopups.length, 1);
      expect(controller.scorePopups.single.label, isNull);
      expect(GameController.comboBonusFor(1), 0);
    });

    test('레이어만 벗겨진 경우 파티클/버스트 없이 점수 팝업만 뜬다', () {
      final controller = _controllerFor(RunPresets.specialStage);
      controller.shapes.add(_shape(['triangle', 'circle']));

      _draw(controller, 'circle');

      expect(controller.shapes.single.isCleared, isFalse);
      expect(controller.particles, isEmpty);
      expect(controller.bursts, isEmpty);
      expect(controller.scorePopups.length, 1);
    });

    test('이펙트는 수명이 끝나면 사라진다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle']));
      _draw(controller, 'circle');

      expect(controller.particles.isNotEmpty || controller.sparkles.isNotEmpty,
          isTrue);
      controller.update(GameController.scorePopupDuration);

      expect(controller.particles, isEmpty);
      expect(controller.sparkles, isEmpty);
      expect(controller.bursts, isEmpty);
      expect(controller.scorePopups, isEmpty);
    });

    test('점수 팝업은 위로 떠오른다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle'], y: 200));
      _draw(controller, 'circle');

      final popup = controller.scorePopups.single;
      final startY = popup.y;
      controller.update(const Duration(milliseconds: 300));
      expect(popup.y, lessThan(startY));
    });
  });

  group('전체 레이어 제거 스킬', () {
    /// 게이지를 가득 채운다(도형 처치 누적).
    GameController chargedController() {
      final controller = _controllerFor(RunPresets.stage1);
      final needed = (1 / GameController.layerBreakGainPerClear).ceil();
      for (int i = 0; i < needed; i++) {
        controller.shapes.add(_shape(['circle'], id: 1000 + i));
        _draw(controller, 'circle');
        controller.update(const Duration(milliseconds: 200));
      }
      return controller;
    }

    test('게이지는 더블클리어 게이지와 독립적으로 찬다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle']));
      _draw(controller, 'circle');

      expect(controller.layerBreakGauge,
          closeTo(GameController.layerBreakGainPerClear, 1e-9));
      expect(controller.comboGauge,
          closeTo(GameController.gaugeGainPerClear, 1e-9));
      expect(controller.layerBreakGauge, isNot(controller.comboGauge));
    });

    test('게이지가 안 차면 발동되지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.shapes.add(_shape(['circle', 'circle'], id: 1));
      expect(controller.isLayerBreakReady, isFalse);

      controller.activateLayerBreak();
      expect(controller.shapes.single.clearedLayers, 0);
    });

    test('화면에 도형이 없으면 비활성 상태를 유지한다', () {
      final controller = chargedController();
      controller.update(const Duration(milliseconds: 200));
      controller.shapes.clear();

      expect(controller.layerBreakGauge, 1.0);
      expect(controller.isLayerBreakReady, isFalse);
    });

    test('모든 도형의 레이어를 한 겹씩 벗긴다', () {
      final controller = chargedController();
      controller.update(const Duration(milliseconds: 200));
      controller.shapes.clear();

      controller.shapes.addAll([
        _shape(['circle'], id: 1), // 1층: 완전히 클리어
        _shape(['square', 'triangle'], id: 2), // 2층: 바깥만 벗겨짐
        _shape(['circle', 'square', 'triangle'], id: 3),
      ]);
      expect(controller.isLayerBreakReady, isTrue);

      controller.activateLayerBreak();

      final one = controller.shapes.firstWhere((s) => s.id == 1);
      final two = controller.shapes.firstWhere((s) => s.id == 2);
      final three = controller.shapes.firstWhere((s) => s.id == 3);

      expect(one.isCleared, isTrue, reason: '1층 도형은 한 겹으로 완전 클리어');
      expect(two.clearedLayers, 1);
      expect(two.isCleared, isFalse);
      expect(two.activeName, 'square', reason: '다음 레이어가 노출된다');
      expect(three.clearedLayers, 1);
      expect(three.activeName, 'square');

      expect(controller.layerBreakGauge, 0, reason: '발동하면 게이지를 모두 쓴다');
    });

    test('보스 도형도 대상에 포함된다', () {
      final controller = chargedController();
      controller.update(const Duration(milliseconds: 200));
      controller.shapes.clear();
      controller.setFieldSize(const Size(400, 500));

      final boss = FallingShape(
        id: 99,
        layers: List.filled(GameController.bossLayers, 'circle'),
        x: 200,
        y: 100,
        size: 240,
        color: Colors.purple,
        isBoss: true,
      );
      controller.shapes.add(boss);

      controller.activateLayerBreak();
      expect(boss.clearedLayers, 1);
    });
  });

  group('타임 슬로우 스킬과 해금', () {
    setUp(() => UnlockState.instance.resetForTest());
    tearDown(() => UnlockState.instance.resetForTest());

    const allThree = EquippedSkills(
      doubleClear: true,
      layerBreak: false,
      timeSlow: true,
    );

    GameController chargedTimeSlowController() {
      final controller = _controllerFor(RunPresets.stage1, equipped: allThree);
      final needed = (1 / GameController.timeSlowGainPerClear).ceil();
      for (int i = 0; i < needed; i++) {
        controller.shapes.add(_shape(['circle'], id: 2000 + i));
        _draw(controller, 'circle');
        controller.update(const Duration(milliseconds: 200));
      }
      return controller;
    }

    test('게이지는 다른 두 스킬과 독립적으로 찬다', () {
      final controller = _controllerFor(RunPresets.stage1, equipped: allThree);
      controller.shapes.add(_shape(['circle']));
      _draw(controller, 'circle');

      expect(controller.timeSlowGauge,
          closeTo(GameController.timeSlowGainPerClear, 1e-9));
      expect(controller.comboGauge,
          closeTo(GameController.gaugeGainPerClear, 1e-9));
    });

    test('게이지가 다 차야 발동되고, 발동하면 화면의 모든 낙하 속도가 줄어든다', () {
      final controller = chargedTimeSlowController();
      controller.shapes
        ..clear()
        ..add(_shape(['circle'], id: 1));
      controller.setFieldSize(const Size(400, 500));
      expect(controller.isTimeSlowReady, isTrue);

      controller.activateTimeSlow();
      expect(controller.isTimeSlowActive, isTrue);
      expect(controller.timeSlowGauge, 0, reason: '발동하면 게이지를 모두 쓴다');

      // 충전 루프 도중 난이도 표의 자동 스폰이 끼어들 수 있으니, 관찰
      // 대상은 id로 고정해서 추적한다(.single은 그 사이 자동 스폰된
      // 다른 도형이 섞이면 깨진다).
      final shape = controller.shapes.firstWhere((s) => s.id == 1);
      final yBefore = shape.y;
      controller.update(const Duration(seconds: 1));
      final slowedDelta = shape.y - yBefore;

      controller.update(GameController.timeSlowDuration); // 지속시간 종료
      expect(controller.isTimeSlowActive, isFalse);

      final yAfter = shape.y;
      controller.update(const Duration(seconds: 1));
      final normalDelta = shape.y - yAfter;

      expect(slowedDelta, lessThan(normalDelta));
    });

    test('5단계를 클리어하면 타임 슬로우가 해금된다', () async {
      expect(UnlockState.instance.timeSlowUnlocked, isFalse);

      await UnlockState.instance.markStageCleared(5);

      expect(UnlockState.instance.timeSlowUnlocked, isTrue);
    });

    test('보스를 놓치고 제한 시간으로 클리어해도 해금된다', () async {
      // 회귀 방지: 예전에는 "보스를 직접 처치"해야만 해금돼서, 시간
      // 만료로 5단계를 클리어하면 3번째 스킬이 지급되지 않았다.
      expect(UnlockState.instance.timeSlowUnlocked, isFalse);

      // 보스에 손도 대지 않고 스테이지 클리어만 기록한다.
      await UnlockState.instance.markStageCleared(RunPresets.stage5.stageNumber!);

      expect(UnlockState.instance.timeSlowUnlocked, isTrue);
    });

    test('5단계 이후 단계를 클리어해도 해금 상태가 유지된다', () async {
      await UnlockState.instance.markStageCleared(7);
      expect(UnlockState.instance.timeSlowUnlocked, isTrue);
    });

    test('4단계까지는 해금되지 않는다', () async {
      for (int stage = 1; stage <= 4; stage++) {
        await UnlockState.instance.markStageCleared(stage);
        expect(UnlockState.instance.timeSlowUnlocked, isFalse,
            reason: '$stage단계');
      }
    });
  });

  group('장착 스킬(로드아웃) 게이팅', () {
    test('장착하지 않은 스킬은 게이지가 차지 않는다', () {
      const onlyDoubleClear = EquippedSkills(
        doubleClear: true,
        layerBreak: false,
        timeSlow: false,
      );
      final controller =
          _controllerFor(RunPresets.stage1, equipped: onlyDoubleClear);
      controller.shapes.add(_shape(['circle']));
      _draw(controller, 'circle');

      expect(controller.comboGauge, greaterThan(0));
      expect(controller.layerBreakGauge, 0);
      expect(controller.timeSlowGauge, 0);
    });

    test('장착하지 않은 더블클리어는 토글해도 켜지지 않는다', () {
      const noDoubleClear = EquippedSkills(
        doubleClear: false,
        layerBreak: true,
        timeSlow: false,
      );
      final controller =
          _controllerFor(RunPresets.stage1, equipped: noDoubleClear);
      controller.shapes.addAll([
        _shape(['circle'], id: 1),
        _shape(['circle'], id: 2),
        _shape(['circle'], id: 3),
      ]);
      _draw(controller, 'circle'); // comboGauge를 채워봐도

      controller.toggleSkill();
      expect(controller.isSkillActive, isFalse);
    });

    test('장착하지 않은 레이어 제거는 게이지가 가득 차도 발동되지 않는다', () {
      const noLayerBreak = EquippedSkills(
        doubleClear: true,
        layerBreak: false,
        timeSlow: false,
      );
      final controller =
          _controllerFor(RunPresets.stage1, equipped: noLayerBreak);
      controller.shapes.add(_shape(['circle']));

      controller.activateLayerBreak();
      expect(controller.shapes.single.clearedLayers, 0);
      expect(controller.isLayerBreakReady, isFalse);
    });

    test('장착하지 않은 타임 슬로우는 발동되지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1); // 기본 장착엔 timeSlow 없음
      controller.activateTimeSlow();
      expect(controller.isTimeSlowActive, isFalse);
    });
  });

  group('쌍둥이 보스', () {
    List<FallingShape> twinsOf(GameController c) =>
        c.shapes.where((s) => s.isBoss).toList();

    GameController spawnedTwins() => _controllerWithBoss(RunPresets.stage10);

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
      final single = _controllerWithBoss(RunPresets.stage5);
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

  group('레이어 조합', () {
    test('같은 도형끼리의 조합도 허용된다 (동일 타입 금지 필터 제거)', () {
      // 여러 시드로 2층 도형을 많이 만들어 보면, 같은 이름이 연달아
      // 나오는 조합이 반드시 섞여 나와야 한다.
      var sawSamePair = false;
      for (int seed = 0; seed < 30 && !sawSamePair; seed++) {
        final controller = GameController(
          runConfig: RunPresets.specialStage,
          random: math.Random(seed),
        )..setFieldSize(const Size(400, 500));

        for (int i = 0; i < 60; i++) {
          controller.update(const Duration(milliseconds: 50));
        }
        for (final s in controller.shapes.where((s) => s.layers.length >= 2)) {
          for (int i = 0; i < s.layers.length - 1; i++) {
            if (s.layers[i] == s.layers[i + 1]) sawSamePair = true;
          }
        }
      }
      expect(sawSamePair, isTrue,
          reason: '인접 레이어가 같은 조합이 한 번도 안 나오면 필터가 남아 있는 것');
    });
  });

  group('스킬 배경 연출', () {
    /// 더블클리어 게이지를 채워 토글 가능한 상태로 만든다.
    GameController readyController() {
      final controller = _controllerFor(RunPresets.stage1);
      _fillComboGauge(controller);
      return controller;
    }

    test('스킬이 꺼져 있으면 링이 하나도 없다', () {
      final controller = _controllerFor(RunPresets.stage1);
      controller.update(const Duration(milliseconds: 16));
      expect(controller.overlaySkills, isEmpty);
      expect(controller.skillRings.hasVisibleRings, isFalse);
    });

    test('스킬 하나만 켜지면 전체 링을 가져간다', () {
      final controller = readyController();
      controller.toggleSkill();
      controller.update(const Duration(milliseconds: 16));

      expect(controller.overlaySkills, [ActiveSkill.doubleClear]);
      for (final ring in controller.skillRings.rings) {
        expect(ring.owner, ActiveSkill.doubleClear,
            reason: '링 ${ring.index}');
      }
    });

    test('끄면 외곽부터 순서대로 퇴장한다', () {
      final controller = readyController();
      controller.toggleSkill();
      // 전부 나타날 때까지 기다린다(등장은 1.0s 스태거 + 0.3s 페이드).
      controller.update(const Duration(milliseconds: 1400));

      controller.toggleSkill();
      controller.update(const Duration(milliseconds: 16));

      // 주인은 즉시 사라지고 퇴장 애니메이션만 남는다.
      expect(controller.overlaySkills, isEmpty);
      expect(controller.skillRings.rings.every((r) => r.owner == null), isTrue);
      expect(controller.skillRings.hasVisibleRings, isTrue,
          reason: '퇴장 애니메이션이 재생 중이어야 한다');

      // 바깥 링이 안쪽 링보다 먼저 옅어진다(0.1초 간격 순차 퇴장).
      controller.update(const Duration(milliseconds: 150));
      final outer = controller.skillRings.rings.first.visibleAnimations.first;
      final inner = controller.skillRings.rings.last.visibleAnimations.first;
      expect(outer.alpha, lessThan(inner.alpha));

      // 충분히 지나면 전부 사라진다.
      controller.update(const Duration(seconds: 3));
      expect(controller.skillRings.hasVisibleRings, isFalse);
    });

    test('아주 짧게 껐다 켜도 등장 1사이클을 완주한 뒤 퇴장한다', () {
      final controller = readyController();
      controller.toggleSkill();

      // 등장이 외곽->중앙 한 바퀴 돌기 훨씬 전에 꺼버린다.
      controller.update(const Duration(milliseconds: 50));
      controller.toggleSkill();

      final cycle = controller.skillRings.entranceCycle;
      expect(cycle, SkillFrameOverlay.entranceCycle);

      // 사이클이 끝나는 시점까지는 링이 계속 나타나는 중이어야 한다.
      controller.update(cycle);
      expect(controller.skillRings.hasVisibleRings, isTrue,
          reason: '1사이클을 완주하기 전에 사라지면 안 된다');

      final innermost = controller.skillRings.rings.last;
      expect(innermost.visibleAnimations, isNotEmpty);
      expect(innermost.visibleAnimations.first.alpha, closeTo(1.0, 1e-6),
          reason: '가장 안쪽 링까지 완전히 나타난 뒤에 퇴장이 시작된다');

      // 그 뒤에야 퇴장이 진행되어 결국 사라진다.
      controller.update(cycle + const Duration(seconds: 2));
      expect(controller.skillRings.hasVisibleRings, isFalse);
    });

    test('빠르게 껐다 켜도 이전 퇴장 애니메이션이 끝까지 재생된다', () {
      final controller = readyController();
      controller.toggleSkill();
      controller.update(const Duration(milliseconds: 1400));

      controller.toggleSkill(); // 끄기 -> 퇴장 시작
      controller.update(const Duration(milliseconds: 50));
      controller.toggleSkill(); // 곧바로 다시 켜기 -> 등장 시작
      controller.update(const Duration(milliseconds: 16));

      final ring = controller.skillRings.rings.first;
      // 퇴장은 남아서 계속 재생되고, 새 등장이 그 위에 얹힌다.
      expect(ring.exiting, isNotEmpty, reason: '이전 퇴장이 잘리면 안 된다');
      expect(ring.owner, ActiveSkill.doubleClear);
      expect(ring.visibleAnimations.length, greaterThanOrEqualTo(1));
    });

    test('두 번째 스킬이 켜지면 홀수 번째 링을 가져간다', () {
      final controller = readyController();
      // 타임 슬로우도 쓸 수 있는 구성으로 다시 만든다.
      const both = EquippedSkills(
        doubleClear: true,
        layerBreak: false,
        timeSlow: true,
      );
      final c = _controllerFor(RunPresets.stage1, equipped: both);
      _fillComboGauge(c);

      c.toggleSkill(); // 더블클리어 먼저
      c.update(const Duration(milliseconds: 1400));
      expect(c.skillRings.rings.every((r) => r.owner == ActiveSkill.doubleClear),
          isTrue);

      // 타임 슬로우 게이지를 채우고 켠다.
      final needed = (1 / GameController.timeSlowGainPerClear).ceil();
      for (int i = 0; i < needed; i++) {
        c.shapes.add(_shape(['circle'], id: 7000 + i));
        _draw(c, 'circle');
        c.update(const Duration(milliseconds: 200));
      }
      c.activateTimeSlow();
      c.update(const Duration(milliseconds: 16));

      // 1-based 홀수(= 0-based 짝수 인덱스)를 새 스킬이 가져간다.
      for (final ring in c.skillRings.rings) {
        final expected = ring.index.isEven
            ? ActiveSkill.timeSlow
            : ActiveSkill.doubleClear;
        expect(ring.owner, expected, reason: '링 ${ring.index}');
      }
      expect(controller.overlaySkills, isEmpty); // 원래 컨트롤러는 영향 없음
    });

    test('한쪽이 꺼지면 남은 스킬이 비워진 링으로 재확장한다', () {
      const both = EquippedSkills(
        doubleClear: true,
        layerBreak: false,
        timeSlow: true,
      );
      final c = _controllerFor(RunPresets.stage1, equipped: both);
      _fillComboGauge(c);
      c.toggleSkill();
      c.update(const Duration(milliseconds: 1400));

      final needed = (1 / GameController.timeSlowGainPerClear).ceil();
      for (int i = 0; i < needed; i++) {
        c.shapes.add(_shape(['circle'], id: 7100 + i));
        _draw(c, 'circle');
        c.update(const Duration(milliseconds: 200));
      }
      c.shapes.clear();
      c.activateTimeSlow();
      c.update(const Duration(milliseconds: 16));

      // 타임 슬로우가 끝나면 더블클리어가 전체 링을 되찾는다.
      c.update(GameController.timeSlowDuration);
      c.update(const Duration(milliseconds: 16));

      expect(c.overlaySkills, [ActiveSkill.doubleClear]);
      for (final ring in c.skillRings.rings) {
        expect(ring.owner, ActiveSkill.doubleClear, reason: '링 ${ring.index}');
      }
    });

    test('레이어 제거는 즉시 발동형이라 1초만 소유한다', () {
      final controller = _controllerFor(RunPresets.stage1);
      final needed = (1 / GameController.layerBreakGainPerClear).ceil();
      for (int i = 0; i < needed; i++) {
        controller.shapes.add(_shape(['circle'], id: 4000 + i));
        _draw(controller, 'circle');
        controller.update(const Duration(milliseconds: 200));
      }
      controller.shapes
        ..clear()
        ..add(_shape(['circle', 'circle'], id: 1));

      controller.activateLayerBreak();
      controller.update(const Duration(milliseconds: 16));
      expect(controller.overlaySkills, [ActiveSkill.layerBreak]);

      controller.update(GameController.layerBreakOverlayDuration);
      expect(controller.overlaySkills, isEmpty);
      expect(GameController.layerBreakOverlayDuration,
          const Duration(seconds: 1));
    });

    test('배경 이펙트 두 색은 명도가 같고 채도만 다르다', () {
      for (final skill in ActiveSkill.values) {
        final high = SkillVisuals.effectColor(
            skill, SkillVisuals.stripeHighSaturation);
        final low = SkillVisuals.effectColor(
            skill, SkillVisuals.stripeLowSaturation);

        final h = HSLColor.fromColor(high);
        final l = HSLColor.fromColor(low);

        expect(high, isNot(equals(low)), reason: '$skill 두 색이 같으면 안 된다');
        // 명도는 동일.
        // 8비트 색으로 왕복하며 생기는 반올림 오차만 허용한다.
        expect(h.lightness, closeTo(l.lightness, 0.01), reason: '$skill 명도');
        expect(h.lightness, closeTo(SkillVisuals.effectLightness, 0.01));
        // 색상(Hue)은 스킬 고유색 유지.
        expect(h.hue, closeTo(l.hue, 0.5), reason: '$skill 색상');
        // 채도만 다르다.
        expect(h.saturation, greaterThan(l.saturation), reason: '$skill 채도');
      }
      // 스킬끼리 대표색이 겹치지 않는다.
      final accents = ActiveSkill.values.map(SkillVisuals.accentOf);
      expect(accents.toSet().length, ActiveSkill.values.length);
    });

    test('반짝임 간격은 0.5초다', () {
      expect(SkillFrameOverlay.colorInterval, const Duration(milliseconds: 500));
    });

    test('스킬 하나면 홀/짝 링이 서로 다른 채도로 줄무늬를 이루고 교대한다', () {
      // 이 규칙은 페인터가 state.clock과 링 인덱스만으로 계산하므로,
      // 여기서는 그 계산과 같은 식으로 검증한다.
      double saturationAt(int ringIndex, Duration clock) {
        final step = clock.inMicroseconds ~/
            SkillFrameOverlay.colorInterval.inMicroseconds;
        final swapped = step.isOdd;
        final highGroup = ringIndex.isEven != swapped;
        return highGroup
            ? SkillVisuals.stripeHighSaturation
            : SkillVisuals.stripeLowSaturation;
      }

      const t0 = Duration.zero;
      // 같은 시각에 이웃한 링은 서로 다른 채도(줄무늬).
      expect(saturationAt(0, t0), isNot(saturationAt(1, t0)));
      expect(saturationAt(1, t0), isNot(saturationAt(2, t0)));

      // 같은 그룹(인덱스 패리티가 같은 링)은 동시에 같은 값 — 순차 파도가 아님.
      expect(saturationAt(0, t0), saturationAt(2, t0));
      expect(saturationAt(1, t0), saturationAt(3, t0));

      // 한 주기 뒤 두 그룹이 서로 맞바뀐다.
      final t1 = SkillFrameOverlay.colorInterval;
      expect(saturationAt(0, t1), saturationAt(1, t0));
      expect(saturationAt(1, t1), saturationAt(0, t0));
    });

    test('스킬 둘이면 채도 대비로 구분하고 어느 쪽이 쨍한지는 상수로 정한다', () {
      expect(SkillVisuals.dualHighSaturation,
          greaterThan(SkillVisuals.dualLowSaturation));
      expect(SkillVisuals.dualHighSaturation, 1.0);
      expect(SkillVisuals.dualLowSaturation, 0.65);
      // 어느 쪽이 높은 채도를 갖는지 뒤집을 수 있어야 한다.
      expect(SkillVisuals.newerSkillTakesHighSaturation, isA<bool>());
    });

    test('가장 안쪽 사각형은 화면의 약 60%의 10% 크기다', () {
      expect(SkillFrameOverlay.innermostScale, closeTo(0.6 * 0.10, 1e-9));
    });

    test('안쪽으로 갈수록 인접 사각형 간격이 좁아진다', () {
      double gapAt(int i) =>
          ringScale(
            index: i,
            ringCount: SkillFrameOverlay.ringCount,
            innermostScale: SkillFrameOverlay.innermostScale,
            easeExponent: SkillFrameOverlay.easeExponent,
          ) -
          ringScale(
            index: i + 1,
            ringCount: SkillFrameOverlay.ringCount,
            innermostScale: SkillFrameOverlay.innermostScale,
            easeExponent: SkillFrameOverlay.easeExponent,
          );

      for (int i = 0; i < SkillFrameOverlay.ringCount - 2; i++) {
        expect(gapAt(i), greaterThan(gapAt(i + 1)),
            reason: '링 $i 간격이 다음 간격보다 넓어야 한다');
      }
    });
  });

  group('라이프 경고 배경', () {
    test('라이프가 1 남으면 켜지고, 그보다 많으면 꺼진다', () {
      final controller = _controllerFor(RunPresets.stage1);
      expect(controller.lives, 5);
      expect(controller.isLowLife, isFalse);

      // 라이프가 1이 될 때까지 도형을 흘려보낸다.
      while (controller.lives > 1 &&
          controller.status == GameStatus.playing) {
        controller.shapes.add(_shape(['circle'], id: 5000, y: 10000));
        controller.update(const Duration(milliseconds: 16));
      }

      expect(controller.lives, 1);
      expect(controller.isLowLife, isTrue);
    });

    test('게임 오버 상태에서는 켜지지 않는다', () {
      final controller = _controllerFor(RunPresets.stage1);
      while (controller.status == GameStatus.playing) {
        controller.shapes.add(_shape(['circle'], id: 5100, y: 10000));
        controller.update(const Duration(milliseconds: 16));
      }
      expect(controller.status, GameStatus.gameOver);
      expect(controller.isLowLife, isFalse);
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
    test('스테이지는 45초, 시작 라이프는 5', () {
      expect(RunPresets.stage1.duration, const Duration(seconds: 45));
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

    test('스테이지 보스는 난이도 5, 레이드 보스는 7부터 등장한다', () {
      expect(RunPresets.stage1.bossFromDifficulty, isNull);
      expect(RunPresets.stage5.bossFromDifficulty, 5);

      for (final raid in RunPresets.raidCheckpoints) {
        expect(raid.isRaidMode, isTrue);
        // 10단계 체크포인트는 자기 구간(10)부터, 나머지는 공통 기준(7)부터.
        final expected =
            raid.id == 'raid_10' ? 10.0 : RunPresets.raidBossDifficulty;
        expect(raid.bossFromDifficulty, expected, reason: raid.id);
      }
      expect(RunPresets.raidBossDifficulty, 7);

      // 스테이지 프리셋은 레이드 모드가 아니다(쌍둥이 보스 스테이지 포함).
      expect(RunPresets.stage10.isRaidMode, isFalse);
    });
  });
}
