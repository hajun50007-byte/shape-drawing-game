import 'package:flutter/material.dart';

import 'game/home_screen.dart';
import 'game/state/unlock_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장된 스테이지 진행도·스킬 해금 상태를 먼저 읽어온다.
  await UnlockState.instance.load();
  runApp(const ShapeDrawingGameApp());
}

class ShapeDrawingGameApp extends StatelessWidget {
  const ShapeDrawingGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '도형 그리기 게임',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
