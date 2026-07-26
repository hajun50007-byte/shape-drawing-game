import 'package:flutter/material.dart';

/// 액티브 스킬 버튼 + 게이지 하나. 캐릭터/아이콘 없이 버튼과 게이지로만
/// 표시한다. 두 스킬(더블클리어 토글 / 전체 레이어 제거)이 각자 독립된
/// 게이지로 이 위젯을 하나씩 쓴다.
class SkillButton extends StatelessWidget {
  const SkillButton({
    super.key,
    required this.label,
    required this.gauge,
    required this.isReady,
    required this.onPressed,
    this.isActive = false,
    this.activeLabel,
    this.accent = Colors.purple,
    this.activeAccent = Colors.purpleAccent,
  });

  /// 평소 표시할 짧은 라벨.
  final String label;

  /// 켜진 상태에서 표시할 라벨. null이면 [label]을 그대로 쓴다.
  final String? activeLabel;

  final double gauge;

  /// 지금 누를 수 있는지.
  final bool isReady;

  /// 토글형 스킬이 켜져 있는지. 발동형 스킬은 항상 false.
  final bool isActive;

  final VoidCallback onPressed;
  final Color accent;
  final Color activeAccent;

  static const double _width = 76;

  @override
  Widget build(BuildContext context) {
    final enabled = isReady || isActive;
    final color = isActive
        ? activeAccent
        : isReady
            ? accent
            : Colors.white24;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: _width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: gauge.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: enabled ? onPressed : null,
          child: Container(
            width: _width,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: isActive ? 0.45 : 0.18),
              border: Border.all(color: color, width: 2),
            ),
            child: Text(
              isActive ? (activeLabel ?? label) : label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white38,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
