import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/boss_traits.dart';

void main() {
  group('BossTraits', () {
    test('rollTelegraphDuration은 항상 min~max 범위 안에서 나온다', () {
      const traits = BossTraits(
        skillWeights: {BossSkillType.heal: 1, BossSkillType.haste: 1},
      );
      final random = math.Random(1);
      for (int i = 0; i < 200; i++) {
        final d = traits.rollTelegraphDuration(random);
        expect(d, greaterThanOrEqualTo(traits.telegraphMin));
        expect(d, lessThanOrEqualTo(traits.telegraphMax));
      }
    });

    test('기본 텔레그래프 범위는 1.0~1.5초다', () {
      expect(
          BossTraits.standard.telegraphMin, const Duration(milliseconds: 1000));
      expect(
          BossTraits.standard.telegraphMax, const Duration(milliseconds: 1500));
    });

    test('min==max면 항상 그 값을 반환한다', () {
      const traits = BossTraits(
        skillWeights: {BossSkillType.heal: 1, BossSkillType.haste: 1},
        telegraphMin: Duration(milliseconds: 1200),
        telegraphMax: Duration(milliseconds: 1200),
      );
      final random = math.Random(2);
      expect(traits.rollTelegraphDuration(random),
          const Duration(milliseconds: 1200));
    });

    test('standard와 twin은 서로 다른 가중치를 쓴다 (보스별 성향 재사용 구조)', () {
      expect(BossTraits.standard.skillWeights,
          isNot(equals(BossTraits.twin.skillWeights)));
    });
  });
}
