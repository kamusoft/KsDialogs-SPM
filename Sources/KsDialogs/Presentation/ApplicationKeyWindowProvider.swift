#if canImport(UIKit)
import UIKit

/// 前面でアクティブなシーンの key window をアプリケーションから取得する既定の供給元。
///
/// 提示先・前面の判定は、どちらもつながっているシーンの写しから作る。
final class ApplicationKeyWindowProvider: DialogKeyWindowProvider {
    /// シーンの写しを読む口。既定はアプリケーションのつながっているシーン。
    private let sceneSnapshots: @MainActor @Sendable () -> [DialogWindowSceneSnapshot]

    /// - Parameter sceneSnapshots: シーンの写しを読む口。前面を離れた合図の判定もこれを読み直す
    init(
        sceneSnapshots: @escaping @MainActor @Sendable () -> [DialogWindowSceneSnapshot] =
            ApplicationKeyWindowProvider.connectedSceneSnapshots
    ) {
        self.sceneSnapshots = sceneSnapshots
    }

    @MainActor
    var keyWindow: UIWindow? {
        Self.selectKeyWindow(from: sceneSnapshots())
    }

    @MainActor
    var isAppInForeground: Bool {
        Self.isAppInForeground(from: sceneSnapshots())
    }

    /// アプリケーションにつながっているシーンの写し。
    @MainActor
    static func connectedSceneSnapshots() -> [DialogWindowSceneSnapshot] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { DialogWindowSceneSnapshot(activationState: $0.activationState, windows: $0.windows) }
    }

    /// 提示先の出現の合図を購読する。
    ///
    /// 提示先の条件は「前面でアクティブなシーン」と「key window」の 2 つからなる。
    /// どちらか片方だけを見ると、もう片方が後から満たされたときに合図が来ない
    /// (起動直後は window が key になった後にシーンがアクティブになる)。
    /// そこで、window が key になった通知とシーンがアクティブになった通知の両方で合図を送る。
    @MainActor
    func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration {
        let center = NotificationCenter.default
        let tokens = Self.hostAppearanceNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Self.deliverOnMainThread(handler)
            }
        }
        let box = UncheckedSendableBox(tokens)
        return DialogHostAppearanceRegistration {
            for token in box.value {
                center.removeObserver(token)
            }
        }
    }

    /// アプリが前面を離れた合図を購読する。
    ///
    /// シーンが背面へ入った通知を受けた時点で前面かどうかを読み直し、前面のシーンが 1 つも
    /// 無くなっていたときだけ合図を送る。複数のシーンを持つアプリでは、1 つのシーンが背面へ入っても
    /// 別のシーンが前面にいれば、利用者はまだアプリを見ているので前面を離れたとみなさない
    /// (core/ADR-0043)。
    @MainActor
    func observeForegroundDeparture(
        _ handler: @escaping DialogForegroundDepartureHandler
    ) -> DialogHostAppearanceRegistration {
        let center = NotificationCenter.default
        let sceneSnapshots = self.sceneSnapshots
        let token = center.addObserver(
            forName: Self.foregroundDepartureNotification,
            object: nil,
            queue: nil
        ) { _ in
            Self.deliverOnMainThread {
                guard !Self.isAppInForeground(from: sceneSnapshots()) else { return }
                handler()
            }
        }
        let box = UncheckedSendableBox(token)
        return DialogHostAppearanceRegistration {
            center.removeObserver(box.value)
        }
    }

    /// 合図のきっかけにする通知。提示先の条件の 2 つの要素に 1 つずつ対応する。
    static let hostAppearanceNotifications: [Notification.Name] = [
        UIWindow.didBecomeKeyNotification,
        UIScene.didActivateNotification,
    ]

    /// 前面を離れた合図のきっかけにする通知。
    static let foregroundDepartureNotification: Notification.Name = UIScene.didEnterBackgroundNotification

    /// 合図を UI スレッドで届ける。
    ///
    /// UIKit はこれらの通知を UI スレッドで送るので、ふだんはその場で届ける
    /// (届く順序を通知の順序と揃え、送った直後に受け取り側の状態が変わっているようにする)。
    /// UI スレッド以外から送られた場合だけ、UI スレッドへ移してから届ける。
    private static func deliverOnMainThread(_ handler: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handler()
            }
        } else {
            Task { @MainActor in
                handler()
            }
        }
    }

    /// 提示起点にできる window を選ぶ。
    /// 前面でアクティブなシーンの key window だけを採用し、無ければ nil を返す
    /// (背面・非アクティブのシーンや key でない window へ重ねると、利用者から見えない場所に出てしまう)。
    @MainActor
    static func selectKeyWindow(from snapshots: [DialogWindowSceneSnapshot]) -> UIWindow? {
        snapshots
            .filter(\.isForegroundActive)
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// アプリが前面にいるかを判定する。
    /// 前面 (アクティブでなくてもよい) のシーンが 1 つ以上あれば前面とする。
    /// シーンが 1 つもつながっていない間 (アプリの初期化処理など) は背面とみなす。
    static func isAppInForeground(from snapshots: [DialogWindowSceneSnapshot]) -> Bool {
        snapshots.contains(where: \.isForeground)
    }
}
#endif
