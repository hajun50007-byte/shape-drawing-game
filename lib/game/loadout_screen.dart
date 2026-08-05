import 'package:flutter/material.dart';

import '../core/difficulty.dart';
import 'game_screen.dart';
import 'model/active_skill.dart';
import 'model/equipped_skills.dart';
import 'render/skill_visuals.dart';
import 'state/unlock_state.dart';

/// 런(스테이지/레이드) 시작 전, 액티브 스킬 3개 중 2개를 골라 장착하는
/// 화면. 타임 슬로우가 아직 해금되지 않았으면 나머지 둘만 선택지가 있는
/// 셈이라 카드들을 비활성 상태로 보여주고 바로 시작할 수 있게 한다.
class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({super.key, required this.runConfig});

  final RunConfig runConfig;

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

enum _SkillKind { doubleClear, layerBreak, timeSlow }

class _LoadoutScreenState extends State<LoadoutScreen> {
  bool _doubleClear = true;
  bool _layerBreak = true;
  bool _timeSlow = false;

  bool get _timeSlowUnlocked => UnlockState.instance.timeSlowUnlocked;

  int get _selectedCount =>
      (_doubleClear ? 1 : 0) + (_layerBreak ? 1 : 0) + (_timeSlow ? 1 : 0);

  void _toggle(_SkillKind kind) {
    final current = switch (kind) {
      _SkillKind.doubleClear => _doubleClear,
      _SkillKind.layerBreak => _layerBreak,
      _SkillKind.timeSlow => _timeSlow,
    };
    // 이미 2개를 골랐는데 새로 켜려는 시도면, 먼저 하나를 꺼야 한다.
    if (!current && _selectedCount >= 2) return;

    setState(() {
      switch (kind) {
        case _SkillKind.doubleClear:
          _doubleClear = !_doubleClear;
        case _SkillKind.layerBreak:
          _layerBreak = !_layerBreak;
        case _SkillKind.timeSlow:
          _timeSlow = !_timeSlow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _timeSlowUnlocked;
    final canStart = _selectedCount == 2;

    return Scaffold(
      backgroundColor: const Color(0xFF10131A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('스킬 장착'),
      ),
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
                    '액티브 스킬 3개 중 2개를 장착하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  _SkillCard(
                    title: '더블클리어',
                    description: '토글로 켜두면 성공할 때마다 다른 그룹도 함께 클리어',
                    color: SkillVisuals.accentOf(ActiveSkill.doubleClear),
                    selected: _doubleClear,
                    locked: false,
                    interactive: unlocked,
                    onTap: () => _toggle(_SkillKind.doubleClear),
                  ),
                  const SizedBox(height: 12),
                  _SkillCard(
                    title: '레이어 제거',
                    description: '화면의 모든 도형에서 바깥 레이어를 한 겹씩 벗김',
                    color: SkillVisuals.accentOf(ActiveSkill.layerBreak),
                    selected: _layerBreak,
                    locked: false,
                    interactive: unlocked,
                    onTap: () => _toggle(_SkillKind.layerBreak),
                  ),
                  const SizedBox(height: 12),
                  _SkillCard(
                    title: '타임 슬로우',
                    description: '몇 초간 화면의 모든 낙하 속도 감소',
                    color: SkillVisuals.accentOf(ActiveSkill.timeSlow),
                    selected: _timeSlow,
                    locked: !unlocked,
                    interactive: unlocked,
                    onTap: () => _toggle(_SkillKind.timeSlow),
                  ),
                  if (!unlocked) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '5단계 보스를 클리어하면 타임 슬로우가 해금되어\n'
                      '자유롭게 2개를 고를 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canStart
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GameScreen(
                                    runConfig: widget.runConfig,
                                    equipped: EquippedSkills(
                                      doubleClear: _doubleClear,
                                      layerBreak: _layerBreak,
                                      timeSlow: _timeSlow,
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: const Text('시작하기'),
                    ),
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

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.title,
    required this.description,
    required this.color,
    required this.selected,
    required this.locked,
    required this.interactive,
    required this.onTap,
  });

  final String title;
  final String description;
  final Color color;
  final bool selected;

  /// 아직 해금되지 않아 잠긴 상태(타임 슬로우 전용).
  final bool locked;

  /// 지금 탭이 먹는지. 해금 전에는 세 카드 모두 고를 게 없어 비활성이다.
  final bool interactive;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (locked || !interactive) ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? color.withValues(alpha: 0.22) : Colors.white10,
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              locked
                  ? Icons.lock
                  : (selected ? Icons.check_circle : Icons.circle_outlined),
              color:
                  locked ? Colors.white38 : (selected ? color : Colors.white38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: locked ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: locked ? Colors.white24 : Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
