import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../core/gesture_recognizer.dart';

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

/// 마지막 인식의 반지름 비율/페널티/점수 내역을 보여주는 디버그 패널.
/// 릴리즈 빌드에서는 렌더링되지 않으며, 비율 페널티 곡선(0.15 / 0.45)을
/// 실제 값 변화를 보며 튜닝하기 위한 것이다.
class DebugRecognitionPanel extends StatelessWidget {
  const DebugRecognitionPanel({
    super.key,
    required this.recognition,
    required this.threshold,
    required this.baseThreshold,
  });

  final RecognitionResult? recognition;

  /// 도형별 보정이 반영된, 실제로 적용된 통과 기준.
  final double threshold;

  /// 보정 전 기본 통과 기준.
  final double baseThreshold;

  static const _label = TextStyle(color: Colors.orangeAccent, fontSize: 11);
  static const _row = TextStyle(color: Colors.white70, fontSize: 11);

  /// 도형별 보정이 걸렸을 때만 "(기본 64.0 −8.0)"처럼 덧붙인다.
  String _adjustmentLabel() {
    final delta = threshold - baseThreshold;
    if (delta.abs() < 0.05) return '';
    final sign = delta < 0 ? '−' : '+';
    return ' (기본 ${baseThreshold.toStringAsFixed(1)}'
        ' $sign${delta.abs().toStringAsFixed(1)})';
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || recognition == null) return const SizedBox.shrink();
    final r = recognition!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[DEBUG] ratio ${r.candidateRatio.toStringAsFixed(3)}'
            ' · 통과기준 ${threshold.toStringAsFixed(1)}'
            '${_adjustmentLabel()}'
            ' · 판정 ${r.name} ${r.score.toStringAsFixed(1)}',
            style: _label,
          ),
          const SizedBox(height: 2),
          for (final e in r.evaluations)
            Text(
              '${e.name.padRight(9)} r${e.templateRatio.toStringAsFixed(2)}'
              ' Δ${e.ratioDiff.toStringAsFixed(3)}'
              '  p${e.penalty.toStringAsFixed(2)}'
              '  ${e.baseScore.toStringAsFixed(1)} → ${e.finalScore.toStringAsFixed(1)}',
              style: _row,
            ),
        ],
      ),
    );
  }
}
