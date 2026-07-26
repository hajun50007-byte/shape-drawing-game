import 'package:flutter/material.dart';

/// 상단 상태 표시줄. 난이도는 정수 레벨로만 보여준다(내부는 소수 보간 유지).
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.score,
    required this.lives,
    required this.displayLevel,
    required this.themeName,
    required this.remaining,
  });

  final int score;
  final int lives;
  final int displayLevel;
  final String themeName;
  final Duration? remaining;

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('❤️ x$lives', style: _style),
            Text('Lv.$displayLevel', style: _style),
            Text('점수 $score', style: _style),
            if (remaining != null)
              Text(_formatDuration(remaining!), style: _style),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          themeName,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final minutes = clamped.inMinutes;
    final seconds = clamped.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 인식 실패 시 유사도/통과 기준 점수를 잠깐 보여주는 디버그용 배지.
class DebugScoreBadge extends StatelessWidget {
  const DebugScoreBadge({
    super.key,
    required this.score,
    required this.threshold,
  });

  final double score;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '[DEBUG] 유사도 ${score.toStringAsFixed(1)} / 필요 ${threshold.toStringAsFixed(1)}',
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
      ),
    );
  }
}
