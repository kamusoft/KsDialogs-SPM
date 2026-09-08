#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 提示面の差し替え実装。
/// UIKit の提示遷移はテスト実行環境 (シーンを持たないテストランナー) では完走しないため、
/// 器の重なりだけをこの面で観察する。UIKit 実装との対応は次のとおり:
///
/// - `present` は最前面への提示に対応し、器を重なりの一番上へ積んでウィンドウに載せる
/// - `dismiss` は提示元からの閉鎖に対応し、その器と、その上に重なっている器を一緒に外す
///   (UIKit の dismiss は、提示した ViewController より手前のものもまとめて閉じる)。
///   実際に外れ終わった時点で完了を知らせるところまでが対応関係で、
///   `holdsDismissalCompletion` を立てると「閉鎖の要求は届いたが撤去はまだ終わっていない」
///   状態を作れる (提示機構の撤去が即座には終わらない実機の順序を再現する)
///
/// 器をウィンドウに載せるのは、実効値のスナップショット時点が「画面に載せたあとの
/// 初回レイアウトパス完了時点」だからで、載せずに観察すると本番と違う順序になる。
@MainActor
final class DialogTestPresentationSurface: DialogPresentationSurface {
    /// 下から順に並んだ、提示中のダイアログの器。
    private(set) var presentedContainers: [DialogContainerViewController] = []

    /// present が呼ばれた時点 (ウィンドウに載せる前) の中身の View の矩形 (下から順)。
    /// 提示より前にサイズが確定しているかを観察するために記録する。
    private(set) var contentFramesAtPresentation: [CGRect] = []

    /// 提示先が存在するか。false にすると提示先不在の状況を再現できる。
    var isPresentationHostAvailable = true

    /// true の間は器をウィンドウへ載せない。
    /// 器を組み立てたが提示はまだ始まっていない状況を、待ち合わせに頼らずに作れる。
    var holdsWindowAttachment = false

    /// ウィンドウへ載せるのを保留していた器を、まとめて載せる。
    func attachHeldContainers() {
        holdsWindowAttachment = false
        for container in presentedContainers where container.view.window == nil {
            attach(container)
        }
    }

    /// 提示したときに器が占める矩形。
    var presentationBounds = CGRect(x: 0, y: 0, width: 390, height: 844)

    /// 器を載せるウィンドウ。
    /// 器の View がウィンドウに載った状態を作るのが目的なので、画面には出さない。
    private lazy var hostWindow = UIWindow(frame: presentationBounds)

    var canPresent: Bool {
        isPresentationHostAvailable
    }

    func present(_ container: DialogContainerViewController) {
        presentedContainers.append(container)
        // 器の View 階層 (覆い・中身の配置) を実際に組み立てる。
        container.loadViewIfNeeded()
        contentFramesAtPresentation.append(container.contentView.frame)
        guard !holdsWindowAttachment else { return }
        attach(container)
    }

    /// 器をウィンドウに載せ、画面上での初回レイアウトパスをその場で走らせる。
    private func attach(_ container: DialogContainerViewController) {
        hostWindow.frame = presentationBounds
        container.view.frame = hostWindow.bounds
        hostWindow.addSubview(container.view)
        hostWindow.layoutIfNeeded()
    }

    /// 器が OS 都合で画面から外れる状況を作る (画面破棄・提示関係の外部からの解除)。
    /// 器から見た見え方は閉鎖と同じ「提示の連なりから外れた」なので、閉鎖と同じ経路で外す。
    /// OS 都合の消失は器の関与なしに完了しているため、保留の設定に関わらずその場で外す。
    func simulateHostLoss(of container: DialogContainerViewController) {
        removeFromPresentation(container)
    }

    /// 一番手前の器を OS 都合の消失として外し、面もテストも器を強く握っていない状態にする。
    /// 器を強く握ったまま観察すると「配送が器の生存に依存していないか」を確かめられないため、
    /// 器そのものは呼び出し側へ渡さず、生存だけを見られる弱参照を返す。
    /// - Returns: 外した器への弱参照。提示中の器が無ければ nil
    func simulateHostLossOfTopmostContainer() -> DialogWeakContainerReference? {
        guard let container = presentedContainers.last else { return nil }
        let reference = DialogWeakContainerReference(container)
        removeFromPresentation(container)
        return reference
    }

    /// true の間は閉鎖の要求を受け取っても撤去まで進めず、要求を溜める。
    var holdsDismissalCompletion = false

    /// 撤去を保留している閉鎖要求。
    private var heldDismissals: [(container: DialogContainerViewController, completion: DialogRemovalCompletion)] = []

    /// 撤去を待っている閉鎖要求の数。
    var heldDismissalCount: Int {
        heldDismissals.count
    }

    /// 保留していた閉鎖要求の撤去をまとめて進め、完了を知らせる。
    func completeHeldDismissals() {
        holdsDismissalCompletion = false
        let pending = heldDismissals
        heldDismissals = []
        for held in pending {
            removeFromPresentation(held.container)
            held.completion()
        }
    }

    func dismiss(
        _ container: DialogContainerViewController,
        completion: @escaping DialogRemovalCompletion
    ) {
        guard !holdsDismissalCompletion else {
            heldDismissals.append((container, completion))
            return
        }
        removeFromPresentation(container)
        completion()
    }

    /// 器と、その上に重なっている器を提示の連なりから外す。
    private func removeFromPresentation(_ container: DialogContainerViewController) {
        guard let index = presentedContainers.firstIndex(where: { $0 === container }) else { return }
        let removedContainers = Array(presentedContainers[index...])
        presentedContainers.removeSubrange(index...)
        // 画面から外れたことを器へ伝える (UIKit が閉鎖時に行う出現状態の遷移に対応)。
        for removedContainer in removedContainers {
            removedContainer.view.removeFromSuperview()
            removedContainer.beginAppearanceTransition(false, animated: false)
            removedContainer.endAppearanceTransition()
        }
    }
}
#endif
