import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/game/state/unlock_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('스테이지 1~20 구성', () {
    test('총 20단계가 있고 번호가 순서대로 붙는다', () {
      expect(RunPresets.stageCount, 20);
      expect(RunPresets.stages.length, 20);
      for (int i = 0; i < 20; i++) {
        expect(RunPresets.stages[i].stageNumber, i + 1);
        expect(RunPresets.stages[i].id, 'stage_${i + 1}');
      }
    });

    test('난이도 구간이 1씩 슬라이딩한다 (N단계 = N ~ N+2)', () {
      for (final config in RunPresets.stages) {
        final n = config.stageNumber!;
        expect(config.minDifficulty, n.toDouble(), reason: '$n단계 min');
        expect(config.maxDifficulty, n + 2.0, reason: '$n단계 max');
      }
    });

    test('11단계부터는 난이도 표가 레벨 10에서 캡되어 실질 난이도가 같다', () {
      final atTen = DifficultyTable.paramsFor(10);
      for (int n = 11; n <= 20; n++) {
        final config = RunPresets.stages[n - 1];
        final params = DifficultyTable.paramsFor(config.minDifficulty);
        expect(params.fallSpeed, atTen.fallSpeed, reason: '$n단계 낙하속도');
        expect(params.maxSimultaneousShapes, atTen.maxSimultaneousShapes,
            reason: '$n단계 동시 등장 수');
        expect(params.recognitionThreshold, atTen.recognitionThreshold,
            reason: '$n단계 통과 기준');
      }
    });

    test('5단계는 단일 보스, 10단계는 쌍둥이 보스, 나머지는 일반 스테이지', () {
      for (final config in RunPresets.stages) {
        final n = config.stageNumber!;
        if (n == 5) {
          expect(config.bossFromDifficulty, RunPresets.bossDifficulty);
          expect(config.bossKind, BossKind.single);
        } else if (n == 10) {
          expect(config.bossFromDifficulty, 10);
          expect(config.bossKind, BossKind.twin);
          expect(config.duration, isNull, reason: '쌍둥이전은 시간 제한 없음');
        } else {
          expect(config.bossFromDifficulty, isNull, reason: '$n단계는 보스 없음');
          expect(config.duration, RunPresets.stageDuration);
        }
      }
    });

    test('다층 도형은 4단계부터 섞여 나오고 확률이 완만히 오른다', () {
      for (final config in RunPresets.stages) {
        final n = config.stageNumber!;
        if (n < RunPresets.multiLayerFromStage) {
          expect(config.maxLayers, 1, reason: '$n단계');
          expect(config.multiLayerChance, 0, reason: '$n단계');
        } else {
          expect(config.maxLayers, 2, reason: '$n단계');
          expect(config.multiLayerChance, greaterThan(0), reason: '$n단계');
        }
      }
      expect(RunPresets.stages[19].multiLayerChance,
          greaterThan(RunPresets.stages[3].multiLayerChance));
    });

    test('구간 테마가 난이도에 맞게 붙는다', () {
      expect(RunPresets.stages[0].resolvedTheme.name, '공장 초입');
      expect(RunPresets.stages[4].resolvedTheme.name, '공장 초입'); // 5단계
      expect(RunPresets.stages[5].resolvedTheme.name, '가속 라인'); // 6단계
    });

    test('이름 있는 프리셋들이 생성된 목록과 같은 것을 가리킨다', () {
      expect(RunPresets.stage1.stageNumber, 1);
      expect(RunPresets.stage5.stageNumber, 5);
      expect(RunPresets.stage10.stageNumber, 10);
      expect(RunPresets.stage10.bossKind, BossKind.twin);
    });

    test('특별 스테이지는 스테이지 목록에 포함되지 않는다', () {
      expect(RunPresets.specialStage.stageNumber, isNull);
      expect(
        RunPresets.stages.any((c) => c.id == RunPresets.specialStage.id),
        isFalse,
      );
    });

    test('레이드 체크포인트에는 단계 번호가 없다', () {
      for (final raid in RunPresets.raidCheckpoints) {
        expect(raid.stageNumber, isNull);
      }
    });
  });

  group('스테이지 순차 해금', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      UnlockState.instance.resetForTest();
    });
    tearDown(() => UnlockState.instance.resetForTest());

    test('처음에는 1단계만 열려 있다', () {
      expect(UnlockState.instance.isStageUnlocked(1), isTrue);
      for (int n = 2; n <= 20; n++) {
        expect(UnlockState.instance.isStageUnlocked(n), isFalse, reason: '$n단계');
      }
    });

    test('N단계를 깨면 N+1단계까지만 열린다', () async {
      await UnlockState.instance.markStageCleared(3);

      expect(UnlockState.instance.highestClearedStage, 3);
      for (int n = 1; n <= 4; n++) {
        expect(UnlockState.instance.isStageUnlocked(n), isTrue, reason: '$n단계');
      }
      expect(UnlockState.instance.isStageUnlocked(5), isFalse);
    });

    test('낮은 단계를 다시 깨도 진행도가 깎이지 않는다', () async {
      await UnlockState.instance.markStageCleared(7);
      await UnlockState.instance.markStageCleared(2);

      expect(UnlockState.instance.highestClearedStage, 7);
      expect(UnlockState.instance.isStageUnlocked(8), isTrue);
    });

    test('저장된 진행도는 다시 읽어도 유지된다', () async {
      await UnlockState.instance.markStageCleared(6);
      UnlockState.instance.unlockTimeSlow();
      // 저장 완료를 기다린다.
      await Future<void>.delayed(Duration.zero);

      // 앱을 다시 켠 상황을 흉내낸다(메모리 상태만 초기화 후 재로드).
      UnlockState.instance.resetForTest();
      expect(UnlockState.instance.highestClearedStage, 0);

      await UnlockState.instance.load();
      expect(UnlockState.instance.highestClearedStage, 6);
      expect(UnlockState.instance.timeSlowUnlocked, isTrue);
    });

    test('진행도가 바뀌면 리스너에게 알린다', () async {
      var notified = 0;
      void listener() => notified++;
      UnlockState.instance.addListener(listener);

      await UnlockState.instance.markStageCleared(1);
      expect(notified, greaterThan(0));

      UnlockState.instance.removeListener(listener);
    });
  });
}
