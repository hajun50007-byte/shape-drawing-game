import 'package:flutter/material.dart';

import '../core/difficulty.dart';
import 'loadout_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '도형 그리기 게임',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '떨어지는 도형과 같은 모양을 아래 패드에 그려서 없애보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 32),
                  const _SectionLabel('스테이지 모드'),
                  const _ModeButton(label: '1단계', config: RunPresets.stage1),
                  const _ModeButton(label: '2단계', config: RunPresets.stage2),
                  const _ModeButton(label: '3단계', config: RunPresets.stage3),
                  const _ModeButton(label: '4단계 · 다층', config: RunPresets.stage4),
                  const _ModeButton(
                      label: '5단계 · 보스 등장', config: RunPresets.stage5),
                  const _ModeButton(
                      label: '10단계 · 쌍둥이 보스', config: RunPresets.stage10),
                  const SizedBox(height: 24),
                  const _SectionLabel('특별 스테이지'),
                  const _ModeButton(
                      label: '다층 도형 집중 · 2층',
                      config: RunPresets.specialStage),
                  const SizedBox(height: 24),
                  const _SectionLabel('레이드 모드'),
                  for (final config in RunPresets.raidCheckpoints)
                    _ModeButton(
                      label: '${config.minDifficulty.round()}단계 체크포인트',
                      config: config,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.config});

  final String label;
  final RunConfig config;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoadoutScreen(runConfig: config),
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                config.resolvedTheme.name,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
