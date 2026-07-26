import 'package:flutter/material.dart';

/// 더블클리어 액티브 스킬 버튼 + 콤보 게이지.
/// 한 번 누르면 켜진 채로 유지되며 게이지가 소모되고, 다시 누르면 꺼진다.
/// (별도 캐릭터/아이콘 없이 버튼과 게이지로만 표시)
class SkillButton extends StatelessWidget {
  const SkillButton({
    super.key,
    required this.gauge,
    required this.isReady,
    required this.isActive,
    required this.onToggle,
  });

  final double gauge;
  final bool isReady;
  final bool isActive;
  final VoidCallback onToggle;

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
          onTap: (isReady || isActive) ? onToggle : null,
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
              isActive ? '2배 ON' : '2배',
              style: TextStyle(
                color: (isReady || isActive) ? Colors.white : Colors.white38,
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
