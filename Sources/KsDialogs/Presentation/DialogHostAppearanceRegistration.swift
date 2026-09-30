#if canImport(UIKit)
/// 提示先の出現の合図を受け取る口。合図は UI スレッドで届く。
typealias DialogHostAppearanceHandler = @MainActor () -> Void

/// 供給元の合図 (提示先の出現・アプリが前面を離れたこと) の購読1件。
///
/// 解除するまで合図が届き続ける。解除は何度呼んでもよく、2 回目以降は何もしない。
@MainActor
final class DialogHostAppearanceRegistration {
    private var onCancel: (@MainActor () -> Void)?

    /// - Parameter onCancel: 解除したときに1回だけ呼ぶ後始末 (購読元からの取り外し)
    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    /// 購読を解除する。解除後は合図が届かない。
    func cancel() {
        guard let onCancel else { return }
        self.onCancel = nil
        onCancel()
    }
}
#endif
