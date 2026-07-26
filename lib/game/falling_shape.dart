/// 화면에 떨어지고 있는 도형 하나의 상태.
/// (x, y)는 도형 중심의 픽셀 좌표, y는 매 프레임 낙하 속도만큼 증가한다.
class FallingShape {
  FallingShape({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.size,
  });

  final int id;
  final String name;
  final double x;
  final double size;
  double y;

  /// 매칭에 성공해 제거 애니메이션(플래시) 중인지 여부.
  /// true인 동안은 낙하도, "놓침" 판정도 멈춘다.
  bool destroying = false;
}
