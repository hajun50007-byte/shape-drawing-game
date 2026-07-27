import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shape_drawing_game/core/difficulty.dart';
import 'package:shape_drawing_game/main.dart';
import 'package:shape_drawing_game/game/state/unlock_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UnlockState.instance.resetForTest();
  });
  tearDown(() => UnlockState.instance.resetForTest());

  testWidgets('홈 화면에 타이틀과 20개 스테이지 타일이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    expect(find.text('도형 그리기 게임'), findsOneWidget);
    expect(find.text('스테이지 모드'), findsOneWidget);

    // 1~20단계 타일이 모두 그려진다.
    for (int stage = 1; stage <= RunPresets.stageCount; stage++) {
      expect(find.text('$stage'), findsOneWidget, reason: '$stage단계 타일');
    }
  });

  testWidgets('진행도가 없으면 1단계만 열려 있고 나머지는 잠겨 있다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    // 잠긴 19개 단계에 자물쇠가 표시된다.
    expect(find.byIcon(Icons.lock), findsNWidgets(RunPresets.stageCount - 1));
  });

  testWidgets('클리어한 만큼 다음 단계가 열린다', (WidgetTester tester) async {
    UnlockState.instance.setHighestClearedStageForTest(3);
    await tester.pumpWidget(const ShapeDrawingGameApp());

    // 1~4단계가 열리고 나머지 16개가 잠긴다.
    expect(find.byIcon(Icons.lock), findsNWidgets(RunPresets.stageCount - 4));
  });

  testWidgets('잠긴 스테이지는 눌러도 이동하지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('스킬 장착'), findsNothing);
    expect(find.text('도형 그리기 게임'), findsOneWidget);
  });

  testWidgets('1단계를 누르면 로드아웃 화면을 거쳐 게임 화면으로 이동한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 페이지 전환 애니메이션

    // 타임 슬로우 미해금 상태에서는 기본 두 스킬이 이미 선택되어 있다.
    expect(find.text('스킬 장착'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 페이지 전환 애니메이션
    await tester.pump(const Duration(milliseconds: 16)); // 게임 루프 1프레임

    expect(find.text('점수 0'), findsOneWidget);
    expect(find.text('❤️ x5'), findsOneWidget);
    expect(find.text('Lv.1'), findsOneWidget);
  });

  testWidgets('특별 스테이지는 UI에 노출되지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    expect(find.text('특별 스테이지'), findsNothing);
    expect(find.textContaining('다층 도형 집중'), findsNothing);
  });
}
