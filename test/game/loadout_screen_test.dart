import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/game/loadout_screen.dart';
import 'package:shape_drawing_game/game/state/unlock_state.dart';

void main() {
  setUp(() => UnlockState.instance.resetForTest());
  tearDown(() => UnlockState.instance.resetForTest());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LoadoutScreen(runConfig: RunPresets.stage1),
    ));
  }

  testWidgets('타임 슬로우 미해금 상태에서는 기본 두 스킬이 이미 선택되어 바로 시작할 수 있다',
      (tester) async {
    await pump(tester);

    expect(find.text('타임 슬로우'), findsOneWidget);
    final startButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '시작하기'));
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets('미해금 상태에서는 카드를 눌러도 선택이 바뀌지 않는다', (tester) async {
    await pump(tester);

    // 잠긴 타임 슬로우를 눌러도 아무 효과가 없어야 한다.
    await tester.tap(find.text('타임 슬로우'));
    await tester.pump();

    final startButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '시작하기'));
    expect(startButton.onPressed, isNotNull, reason: '여전히 기본 두 개가 선택된 상태');
  });

  testWidgets('해금 후에는 하나를 빼야 세 번째를 고를 수 있다', (tester) async {
    UnlockState.instance.unlockTimeSlow();
    await pump(tester);

    // 이미 더블클리어+레이어 제거 2개가 선택된 상태라, 바로 타임 슬로우를
    // 누르면 무시된다(정확히 2개 규칙).
    await tester.tap(find.text('타임 슬로우'));
    await tester.pump();
    var startButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '시작하기'));
    expect(startButton.onPressed, isNotNull, reason: '아직 기존 2개 그대로');

    // 하나를 빼면 타임 슬로우를 고를 수 있다.
    await tester.tap(find.text('더블클리어'));
    await tester.pump();
    await tester.tap(find.text('타임 슬로우'));
    await tester.pump();

    startButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '시작하기'));
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets('하나만 선택된 상태에서는 시작할 수 없다', (tester) async {
    UnlockState.instance.unlockTimeSlow();
    await pump(tester);

    await tester.tap(find.text('더블클리어')); // 2개 -> 1개
    await tester.pump();

    final startButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '시작하기'));
    expect(startButton.onPressed, isNull);
  });
}
