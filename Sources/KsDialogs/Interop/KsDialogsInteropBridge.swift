#if canImport(UIKit)
import Foundation
import UIKit

/// KMP からの委譲呼び出しを受ける ObjC 互換面 (kmp/ADR-0002)。
///
/// ジェネリクスと associated value を持つ結果は ObjC 表現に出せないため、
/// ViewModel と結果値を型消去したまま受け渡し、型の復元は委譲元が担う。
/// レジストリは Swift の型付き入口と同一のものを共有するため、
/// どちらの入口で登録しても同じ紐付けが引ける。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない。
/// 利用者向けの入口は型付きの `Dialog` (iOS Native) と `KsDialogsKmp` (KMP 共有コードの ViewModel 向け) で、
/// 登録・表示・結果取得はそちらだけで完結する (kmp/ADR-0003・0004)。
@objc(KSDInteropDialogBridge)
public final class KsDialogsInteropBridge: NSObject, Sendable {
    /// 既定のレジストリと提示先解決を使う共有インスタンス。
    @objc(sharedBridge)
    public static let shared = KsDialogsInteropBridge()

    private let registry: DialogViewRegistry
    private let presentationSurface: any DialogPresentationSurface

    public override convenience init() {
        self.init(presentationSurface: UIKitDialogPresentationSurface())
    }

    init(registry: DialogViewRegistry = .shared, presentationSurface: any DialogPresentationSurface) {
        self.registry = registry
        self.presentationSurface = presentationSurface
        super.init()
    }

    /// ViewModel のクラスをキーに View factory を登録する。
    /// factory は show のたびに呼ばれ、View を毎回新規に生成する。
    ///
    /// 結果値は型を消して運ばれ委譲元では型を復元できないため、その ViewModel の宣言結果型を
    /// ここで受け取り、結果報告の時点で値を確かめる。
    @objc(registerViewFactoryForViewModelClass:resultType:factory:)
    public func registerViewFactory(
        forViewModelClass viewModelClass: AnyClass,
        resultType: KsDialogsInteropResultType,
        factory: @escaping @MainActor (Any, KsDialogsInteropNotifier) -> UIView
    ) {
        let boxedFactory = UncheckedSendableBox(factory)
        let erasedFactory = DialogViewFactory { viewModel, resultChannel in
            DialogContent(
                view: boxedFactory.value(
                    viewModel,
                    KsDialogsInteropNotifier(resultChannel: resultChannel, resultType: resultType)
                )
            )
        }
        registry.register(erasedFactory, forKey: DialogViewModelKey(viewModelClass))
    }

    /// ViewModel を渡してダイアログを表示し、結果を completion で1回だけ返す。
    /// 構成エラーは throw ではなく error 判別の結果として返す。
    ///
    /// 戻り値は、この1回の show を取り消すためのハンドルである。委譲元の待機が打ち切られたときに
    /// これを使うと、その1枚だけが閉じて結果が cancelled で確定する。
    ///
    /// `placement` を渡すと、中身の View に添付された placement をまるごと置換して配置を決める。
    /// nil のときは添付された値、添付もなければ契約の既定値になる (core/ADR-0015)。
    /// 静的メタ属性はこの面を渡らず、中身の View への添付だけで供給される。
    @objc(showViewModel:placement:completion:)
    @discardableResult
    public func show(
        _ viewModel: Any,
        placement: KsDialogsInteropPlacement? = nil,
        completion: @escaping (KsDialogsInteropResult) -> Void
    ) -> KsDialogsInteropShowHandle {
        show(
            viewModel,
            resolvedPlacement: placement.map { DialogPlacement($0) },
            completion: completion
        )
    }

    /// 置き場所をライブラリの型のまま受け取る提示。
    ///
    /// 型付きの KMP 向け公開面はこちらへ委譲し、ObjC 表現への往復を挟まない。
    /// 結果の運び方も取り消しの手立ても ObjC 面の show と同一である。
    @discardableResult
    func show(
        _ viewModel: Any,
        resolvedPlacement: DialogPlacement?,
        completion: @escaping (KsDialogsInteropResult) -> Void
    ) -> KsDialogsInteropShowHandle {
        let boxedViewModel = UncheckedSendableBox(viewModel)
        let boxedCompletion = UncheckedSendableBox(completion)
        let presentation = Task { @MainActor in
            do {
                let outcome = try await DialogPresenter.present(
                    viewModel: boxedViewModel.value,
                    registry: registry,
                    presentationSurface: presentationSurface,
                    placement: resolvedPlacement
                )
                boxedCompletion.value(KsDialogsInteropResult(outcome: outcome))
            } catch {
                boxedCompletion.value(KsDialogsInteropResult(error: error))
            }
        }
        return KsDialogsInteropShowHandle(presentation: presentation)
    }
}
#endif
