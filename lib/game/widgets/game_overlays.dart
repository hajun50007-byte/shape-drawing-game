import 'package:flutter/material.dart';

/// 라이프가 깎일 때 화면 테두리가 붉게 깜빡이는 실패 피드백.
/// [intensity]는 0~1이며 컨트롤러가 시간에 따라 줄여준다.
class DamageFlashOverlay extends StatelessWidget {
  const DamageFlashOverlay({super.key, required this.intensity});

  final double intensity;

  @override
  Widget build(BuildContext context) {
    final t = intensity.clamp(0.0, 1.0);
    // 이 오버레이는 스킬 버튼 위에 깔리므로 항상 터치를 통과시켜야 한다.
    if (t <= 0) return const IgnorePointer(child: SizedBox.expand());
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.55 * t),
              blurRadius: 28 * t,
              spreadRadius: 6 * t,
              blurStyle: BlurStyle.inner,
            ),
          ],
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.85 * t),
            width: 5 * t,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 라이프가 얼마 안 남았을 때 배경을 아주 은은하게 붉게 물들인다.
/// 실패 순간의 [DamageFlashOverlay]와 달리 상시 깔리는 상태 표시라
/// 훨씬 약하게, 가장자리에서 안쪽으로 옅게만 번지게 한다.
class LowLifeTintOverlay extends StatelessWidget {
  const LowLifeTintOverlay({super.key, required this.active});

  final bool active;

  /// 가장자리에서의 최대 농도. 은은해야 하므로 아주 낮게 잡는다.
  static const double edgeOpacity = 0.16;

  @override
  Widget build(BuildContext context) {
    if (!active) return const IgnorePointer(child: SizedBox.expand());
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.0,
            colors: [
              Colors.red.withValues(alpha: 0),
              Colors.red.withValues(alpha: edgeOpacity),
            ],
            stops: const [0.55, 1.0],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class GameEndOverlay extends StatelessWidget {
  const GameEndOverlay({
    super.key,
    required this.cleared,
    required this.score,
    required this.onRetry,
    required this.onHome,
  });

  final bool cleared;
  final int score;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cleared ? '스테이지 클리어!' : '게임 오버',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text('점수 $score',
              style: const TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(onPressed: onRetry, child: const Text('다시 하기')),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: onHome, child: const Text('홈으로')),
            ],
          ),
        ],
      ),
    );
  }
}
