import 'dart:ui' show Color;

/// 화면에 떨어지고 있는 도형 하나.
///
/// 다층(N-layer) 도형은 [layers]에 안쪽부터 바깥쪽 순서로 이름이 담긴다
/// (index 0 = 가장 안쪽). 플레이어는 바깥 레이어부터 순서대로 그려서
/// 벗겨내며, 레이어가 남아 있는 동안에도 낙하 타이머는 하나로 공유된다
/// (레이어를 깼다고 낙하가 리셋되지 않는다).
class FallingShape {
  FallingShape({
    required this.id,
    required this.layers,
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    this.isBoss = false,
    this.introDuration = Duration.zero,
  })  : assert(layers.isNotEmpty),
        introRemaining = introDuration;

  final int id;

  /// index 0 = 가장 안쪽 레이어. 클리어는 바깥(마지막 index)부터 진행된다.
  ///
  /// 고정 길이가 아니다 — 쌍둥이 보스처럼 전투 중 남은 층수가 바뀌는
  /// 경우가 있어 [setRemainingLayers]로 교체할 수 있다.
  final List<String> layers;

  final double x;
  final double size;
  final Color color;

  /// 보스 도형인지. 보스는 크고 느리며 화면에 하나만 존재한다.
  final bool isBoss;

  /// 등장 연출 길이. 0이면 연출 없이 바로 낙하한다.
  final Duration introDuration;

  double y;

  /// 지금까지 벗겨낸 레이어 수(바깥에서부터).
  int clearedLayers = 0;

  /// 레이어를 깼을 때의 흰색 플래시 잔여 시간. 0보다 크면 낙하와 놓침
  /// 판정이 모두 멈춘다.
  Duration flashRemaining = Duration.zero;

  /// 등장 연출 잔여 시간. 연출 중에는 낙하도 판정도 하지 않는다.
  Duration introRemaining;

  bool get isMultiLayer => layers.length > 1;

  /// 지금 그려서 맞춰야 하는 레이어 이름. 바깥(마지막 index)부터 벗겨진다.
  String get activeName =>
      layers[(layers.length - 1 - clearedLayers).clamp(0, layers.length - 1)];

  /// 아직 남아 있는 가장 바깥 레이어의 index. 렌더링 시작점으로 쓴다.
  int get outermostRemainingIndex => layers.length - 1 - clearedLayers;

  /// 아직 벗겨내지 않은 레이어 수.
  int get remainingLayers => layers.length - clearedLayers;

  /// 남은 레이어를 [names]로 통째로 교체한다(index 0 = 가장 안쪽).
  /// 이미 벗겨낸 진행([clearedLayers])은 그대로 유지되고, 벗겨낸 레이어의
  /// 이름은 렌더링·판정 어디에도 쓰이지 않으므로 자리만 채워둔다.
  void setRemainingLayers(List<String> names) {
    assert(names.isNotEmpty);
    final peeled = layers.sublist(layers.length - clearedLayers);
    layers
      ..clear()
      ..addAll(names)
      ..addAll(peeled);
  }

  /// 모든 레이어를 벗겨냈는지.
  bool get isCleared => clearedLayers >= layers.length;

  /// 플래시 중이라 낙하/판정에서 제외되는 상태인지.
  bool get isFlashing => flashRemaining > Duration.zero;

  /// 등장 연출 중인지.
  bool get isIntroPlaying => introRemaining > Duration.zero;

  /// 등장 연출 진행도 0~1.
  double get introProgress {
    if (introDuration == Duration.zero) return 1;
    final done = introDuration - introRemaining;
    return (done.inMicroseconds / introDuration.inMicroseconds).clamp(0.0, 1.0);
  }

  /// 클리어 애니메이션까지 끝나 목록에서 제거해도 되는 상태인지.
  bool get isFinished => isCleared && !isFlashing;

  /// 매칭/놓침 판정 대상이 되는 살아있는 도형인지.
  bool get isActionable => !isCleared && !isFlashing && !isIntroPlaying;
}
