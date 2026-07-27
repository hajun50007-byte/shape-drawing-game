import 'package:flutter_test/flutter_test.dart';

import 'package:shape_drawing_game/main.dart';

void main() {
  testWidgets('홈 화면에 타이틀과 스테이지 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    expect(find.text('도형 그리기 게임'), findsOneWidget);
    expect(find.text('1단계'), findsOneWidget);
    expect(find.text('2단계'), findsOneWidget);
    expect(find.text('3단계'), findsOneWidget);
  });

  testWidgets('스테이지 버튼을 누르면 로드아웃 화면을 거쳐 게임 화면으로 이동한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShapeDrawingGameApp());

    await tester.tap(find.text('1단계'));
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
}
