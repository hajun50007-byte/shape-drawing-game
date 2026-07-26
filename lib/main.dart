import 'package:flutter/material.dart';

import 'game/home_screen.dart';

void main() {
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
