#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 既定の供給元 (`ApplicationKeyWindowProvider`) に読ませるシーンの写しを、テストが差し替える。
///
/// テストの実行体はシーンを持たないので、シーンの活動状態はここで作る。供給元は判定のたびに
/// `snapshots` を読み直すので、通知を送る前に書き換えれば「通知の時点の状態」を再現できる。
@MainActor
final class DialogTestSceneStates {
    var snapshots: [DialogWindowSceneSnapshot]

    /// - Parameter states: シーンごとの活動状態。window は持たせない
    init(_ states: [UIScene.ActivationState]) {
        snapshots = states.map { DialogWindowSceneSnapshot(activationState: $0, windows: []) }
    }

    /// シーンごとの活動状態を置き換える。window は持たせない。
    func set(_ states: [UIScene.ActivationState]) {
        snapshots = states.map { DialogWindowSceneSnapshot(activationState: $0, windows: []) }
    }

    /// この写しを読む既定の供給元を作る。
    func makeProvider() -> ApplicationKeyWindowProvider {
        ApplicationKeyWindowProvider(sceneSnapshots: { self.snapshots })
    }
}
#endif
