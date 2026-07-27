import 'package:flutter/material.dart';

import '../core/difficulty.dart';
import 'loadout_screen.dart';
import 'state/unlock_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      body: SafeArea(
        // 진행도가 바뀌면(스테이지 클리어) 잠금 표시가 즉시 갱신되도록 구독.
        child: AnimatedBuilder(
          animation: UnlockState.instance,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
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
                    // 진행도를 값으로 넘겨야 한다. const 위젯으로 두면
                    // 인스턴스가 그대로라 AnimatedBuilder가 리빌드해도
                    // 서브트리가 갱신되지 않아 잠금 표시가 멈춰 버린다.
                    _StageGrid(
                      highestClearedStage:
                          UnlockState.instance.highestClearedStage,
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel('레이드 모드'),
                    for (final config in RunPresets.raidCheckpoints)
                      _RaidButton(
                        label: '${config.minDifficulty.round()}단계 체크포인트',
                        config: config,
                      ),
                  ],
                ),
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

/// 1~20단계 타일. 아직 열리지 않은 단계는 회색조 + 자물쇠로 구분한다.
class _StageGrid extends StatelessWidget {
  const _StageGrid({required this.highestClearedStage});

  /// 진행도를 필드로 받아야 값이 바뀔 때 위젯 동등성이 깨져 리빌드된다.
  final int highestClearedStage;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final config in RunPresets.stages)
          _StageTile(
            stage: config.stageNumber!,
            config: config,
            unlocked: config.stageNumber! <= highestClearedStage + 1,
          ),
      ],
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.config,
    required this.unlocked,
  });

  final int stage;
  final RunConfig config;
  final bool unlocked;

  bool get _isBossStage => config.bossFromDifficulty != null;

  @override
  Widget build(BuildContext context) {
    final accent = _isBossStage ? Colors.purpleAccent : Colors.white70;
    final borderColor = unlocked ? accent : Colors.white12;

    return SizedBox(
      width: 62,
      height: 62,
      child: Material(
        color: unlocked
            ? (_isBossStage
                ? Colors.purple.withValues(alpha: 0.18)
                : Colors.white10)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: unlocked
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoadoutScreen(runConfig: config),
                    ),
                  );
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!unlocked)
                  const Icon(Icons.lock, size: 16, color: Colors.white24)
                else if (_isBossStage)
                  const Icon(Icons.whatshot, size: 14, color: Colors.purpleAccent),
                const SizedBox(height: 2),
                Text(
                  '$stage',
                  style: TextStyle(
                    color: unlocked ? Colors.white : Colors.white24,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RaidButton extends StatelessWidget {
  const _RaidButton({required this.label, required this.config});

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
