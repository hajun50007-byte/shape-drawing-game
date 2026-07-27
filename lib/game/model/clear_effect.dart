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

/// 크러쉬형 반짝임. 클리어된 도형 반경 주변의 3~4개 지점마다 미니 도형
/// 3개가 가상 삼각형 꼭짓점에 배치되고, 0.1초 간격으로 켜졌다 꺼지길
/// 3번 반복해 폭죽처럼 보인다.
class ShapeSparkle extends TimedEffect {
  ShapeSparkle({
    required this.shapeName,
    required this.centerX,
    required this.centerY,
    required this.miniSize,
    required this.clusters,
    required this.blinkInterval,
    required this.blinkCount,
    required super.duration,
  });

  final String shapeName;

  /// 이 반짝임이 퍼져 나가는 중심. 새 반짝임을 겹치지 않게 배치할 때
  /// 기존 반짝임들과의 거리를 재는 기준점이다.
  final double centerX;
  final double centerY;

  final double miniSize;

  /// 각 지점의 미니 도형 3개 좌표(가상 삼각형 꼭짓점).
  final List<List<SparklePoint>> clusters;

  /// 켜짐/꺼짐이 전환되는 간격.
  final Duration blinkInterval;

  /// 총 켜짐(on) 횟수. 뒤로 갈수록(마지막 켜짐일수록) [visibleAlpha]가
  /// 낮아져 뚝 끊기지 않고 서서히 흐려지며 사라진다.
  final int blinkCount;

  /// 현재 프레임의 표시 알파. 꺼짐 구간이면 0이고, 켜짐 구간이면 순서가
  /// 지날수록(마지막 깜빡임일수록) 점점 낮아진다.
  double get visibleAlpha {
    if (blinkInterval == Duration.zero) return 1;
    final step = elapsed.inMicroseconds ~/ blinkInterval.inMicroseconds;
    if (step.isOdd) return 0; // 꺼짐 구간
    if (blinkCount <= 1) return 1;
    final onCycleIndex = step ~/ 2;
    return (1 - onCycleIndex / blinkCount).clamp(0.0, 1.0);
  }

  /// 지금 프레임에 뭔가 그려야 하는지.
  bool get isVisible => visibleAlpha > 0;
}

/// 반짝임 미니 도형 하나의 절대 좌표.
class SparklePoint {
  const SparklePoint(this.x, this.y);
  final double x;
  final double y;
}

/// 제거 위치에서 위로 떠오르며 사라지는 획득 점수 텍스트.
class ScorePopup extends TimedEffect {
  ScorePopup({
    required this.startX,
    required this.startY,
    required this.score,
    required this.riseDistance,
    required super.duration,
    this.label,
  });

  final double startX;
  final double startY;
  final int score;

  /// "COMBO"처럼 점수 뒤에 붙는 강조 라벨. null이면 점수만 표시한다.
  final String? label;

  /// 수명 동안 위로 떠오르는 총 거리(px).
  final double riseDistance;

  double get x => startX;
  double get y => startY - riseDistance * progress;
}
