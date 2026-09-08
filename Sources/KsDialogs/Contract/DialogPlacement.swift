/// ダイアログの器に渡す動的メタ属性 (置き場所)。
///
/// 同じ View を呼び出しごとに違う位置へ出せるよう、ダイアログの中身 (View) への添付に加えて
/// show の引数でも供給できる (core/ADR-0015)。show の引数で渡した値は添付された値を
/// **オブジェクトまるごと置換**し、フィールド単位では合成しない。
///
/// 全フィールドに既定値があるため、何も設定しなければ契約の既定値 (中央配置・移動なし) で動く。
/// 数値はすべて論理単位 (pt) で、非有限値は 0 として扱う。
public struct DialogPlacement: Sendable, Equatable {
    /// 水平方向の配置。既定は中央。
    public var horizontalAlignment: DialogAlignment

    /// 垂直方向の配置。既定は中央。
    public var verticalAlignment: DialogAlignment

    /// 配置を決めた後に加える水平方向の移動量。正の値で右へ動く。既定は 0。
    public var offsetX: Double

    /// 配置を決めた後に加える垂直方向の移動量。正の値で下へ動く。既定は 0。
    public var offsetY: Double

    public init(
        horizontalAlignment: DialogAlignment = .center,
        verticalAlignment: DialogAlignment = .center,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}
