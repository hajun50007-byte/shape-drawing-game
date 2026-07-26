// 도형 클리어 연출용 이펙트들.
//
// 전부 컨트롤러의 틱으로만 시간이 흐르며(별도 타이머 없음), isDone이 되면
// 목록에서 제거된다. 렌더링은 FallingFieldPainter가 담당한다.

/// 시간 기반 이펙트의 공통 수명 관리.
abstract class TimedEffect {
  TimedEffect({required this.duration});

  final Duration duration;
  Duration elapsed = Duration.zero;

  void advance(Duration dt) => elapsed += dt;

  /// 0~1 진행도.
  double get progress {
    if (duration == Duration.zero) return 1;
    return (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  bool get isDone => elapsed >= duration;
}

/// 콤보의 마지막 도형이 사라질 때, 그 도형의 실루엣을 따라 흰색이 퍼졌다
/// 사라지는 버스트.
class ShapeBurst extends TimedEffect {
  ShapeBurst({
    required this.shapeName,
    required this.x,
    required this.y,
    required this.size,
    required super.duration,
  });

  final String shapeName;
  final double x;
  final double y;
  final double size;
}

/// 도형 제거 시 그 도형 모양으로 사방으로 튀는 작은 흰색 파티클.
class ShapeParticle extends TimedEffect {
  ShapeParticle({
    required this.shapeName,
    required this.startX,
    required this.startY,
    required this.size,
    required this.velocityX,
    required this.velocityY,
    required super.duration,
  });

  final String shapeName;
  final double startX;
  final double startY;
  final double size;
  final double velocityX;
  final double velocityY;

  double get _seconds => elapsed.inMicroseconds / Duration.microsecondsPerSecond;

  double get x => startX + velocityX * _seconds;
  double get y => startY + velocityY * _seconds;
}

/// 제거 위치에서 위로 떠오르며 사라지는 획득 점수 텍스트.
class ScorePopup extends TimedEffect {
  ScorePopup({
    required this.startX,
    required this.startY,
    required this.score,
    required this.riseDistance,
    required super.duration,
  });

  final double startX;
  final double startY;
  final int score;

  /// 수명 동안 위로 떠오르는 총 거리(px).
  final double riseDistance;

  double get x => startX;
  double get y => startY - riseDistance * progress;
}
