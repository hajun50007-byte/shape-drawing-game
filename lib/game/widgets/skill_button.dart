import 'package:flutter/material.dart';

/// 홀드 더블클리어 액티브 스킬 버튼 + 콤보 게이지.
/// 게이지가 최소치 이상 차야 누를 수 있고, 누르고 있는 동안 게이지가
/// 소모된다. (별도 캐릭터/아이콘 없이 버튼과 게이지로만 표시)
class SkillButton extends StatelessWidget {
  const SkillButton({
    super.key,
    required this.gauge,
    required this.isReady,
    required this.isActive,
    required this.onHoldChanged,
  });

  final double gauge;
  final bool isReady;
  final bool isActive;
  final ValueChanged<bool> onHoldChanged;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Colors.purpleAccent
        : isReady
            ? Colors.purple
            : Colors.white24;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 76,
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
          onTapDown: isReady ? (_) => onHoldChanged(true) : null,
          onTapUp: (_) => onHoldChanged(false),
          onTapCancel: () => onHoldChanged(false),
          child: Container(
            width: 76,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: isActive ? 0.45 : 0.18),
              border: Border.all(color: color, width: 2),
            ),
            child: Text(
              '홀드',
              style: TextStyle(
                color: isReady ? Colors.white : Colors.white38,
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
