import 'dart:ui' show Color;

/// 화면에 떨어지고 있는 도형 하나.
///
/// 다층(N-layer) 도형은 [layers]에 안쪽부터 바깥쪽 순서로 이름이 담긴다.
/// 플레이어는 안쪽 레이어부터 순서대로 그려서 벗겨내야 하며, 레이어가
/// 남아 있는 동안에도 낙하 타이머는 하나로 공유된다(레이어를 깼다고
/// 낙하가 리셋되지 않는다).
class FallingShape {
  FallingShape({
    required this.id,
    required this.layers,
    required this.x,
    required this.y,
    required this.size,
    required this.color,
  }) : assert(layers.isNotEmpty);

  final int id;

  /// index 0 = 가장 안쪽 레이어. 이 순서대로 클리어해야 한다.
  final List<String> layers;

  final double x;
  final double size;
  final Color color;

  double y;

  /// 지금까지 벗겨낸 레이어 수.
  int clearedLayers = 0;

  /// 레이어를 깼을 때의 흰색 플래시 잔여 시간. 0보다 크면 낙하와 놓침
  /// 판정이 모두 멈춘다.
  Duration flashRemaining = Duration.zero;

  bool get isMultiLayer => layers.length > 1;

  /// 지금 그려서 맞춰야 하는 레이어 이름.
  String get activeName => layers[clearedLayers.clamp(0, layers.length - 1)];

  /// 모든 레이어를 벗겨냈는지.
  bool get isCleared => clearedLayers >= layers.length;

  /// 플래시 중이라 낙하/판정에서 제외되는 상태인지.
  bool get isFlashing => flashRemaining > Duration.zero;

  /// 클리어 애니메이션까지 끝나 목록에서 제거해도 되는 상태인지.
  bool get isFinished => isCleared && !isFlashing;

  /// 매칭/놓침 판정 대상이 되는 살아있는 도형인지.
  bool get isActionable => !isCleared && !isFlashing;
}
