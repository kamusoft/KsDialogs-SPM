#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

/// ViewModel 型をキーに View factory と ViewModel factory を引くレジストリ (core/ADR-0004・0021)。
///
/// 既定 singleton エントリと DI 注入で使うインスタンスは `shared` を共有するため、
/// どちらの入口から登録しても同じ紐付けが引ける。
/// 登録・解決は任意のスレッドから行える。
public final class DialogViewRegistry: @unchecked Sendable {
    /// 全入口が共有する既定のレジストリ。
    public static let shared = DialogViewRegistry()

    private let lock = NSLock()
    private var entries: [DialogViewModelKey: DialogRegistryEntry] = [:]

    public init() {}

    /// ViewModel 型に対する View factory を登録する。
    /// 同じ型・同じスロットへの再登録は後勝ちで置き換え、ViewModel factory のスロットは保持される。
    /// factory は show のたびに呼ばれ、View を毎回新規に生成する (core/ADR-0005)。
    ///
    /// factory が失敗を投げた show は結果を返さずに失敗し、ダイアログは提示されない。
    public func register<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> UIView
    ) {
        register(
            DialogViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel 型に対する SwiftUI の中身の factory を登録する (core/ADR-0010・0011)。
    ///
    /// 従来 View 系の登録と同名で、factory の戻り値の型だけが違う。
    /// ホスティングは器の内部で行うため、利用者は SwiftUI の View をそのまま返せばよい。
    /// 登録・show・結果・レイアウトの挙動は従来 View 系と同一である。
    public func register<ViewModel: DialogViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> Content
    ) {
        register(
            DialogViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel だけを受け取る View factory を登録する (core/ADR-0018)。
    ///
    /// 結果報告口は中身の中から `viewModel.notifier` で取り出す。
    /// 報告口を factory 引数で受け取る形も低水準の登録として残る。
    public func register<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) {
        register(
            DialogViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel だけを受け取る SwiftUI の中身の factory を登録する (core/ADR-0018)。
    public func register<ViewModel: DialogViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) {
        register(
            DialogViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel 型に対する ViewModel factory を登録する (core/ADR-0021)。
    ///
    /// 型指定 show (`show(ViewModel.self)`) はこの factory で ViewModel を作る。
    /// 同じ型・同じスロットへの再登録は後勝ちで置き換え、View factory のスロットは保持される。
    /// factory は show のたびに呼ばれ、UI スレッド (MainActor) で実行される。
    public func register<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        viewModel factory: @escaping @MainActor @Sendable () -> ViewModel
    ) {
        register(
            DialogViewModelFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// 型消去された View factory を登録する (ObjC 互換面からの登録経路)。
    func register(_ factory: DialogViewFactory, forKey key: DialogViewModelKey) {
        lock.lock()
        defer { lock.unlock() }
        entries[key, default: DialogRegistryEntry()].viewFactory = factory
    }

    /// 型消去された ViewModel factory を登録する。
    func register(_ factory: DialogViewModelFactory, forKey key: DialogViewModelKey) {
        lock.lock()
        defer { lock.unlock() }
        entries[key, default: DialogRegistryEntry()].viewModelFactory = factory
    }

    /// キーに対応するエントリを返す。どちらのスロットも未登録なら nil。
    /// 返すのは呼び出し時点のスナップショットで、以後の再登録には影響されない。
    func entry(forKey key: DialogViewModelKey) -> DialogRegistryEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    /// キーに対応する View factory を返す。未登録なら nil。
    func factory(forKey key: DialogViewModelKey) -> DialogViewFactory? {
        entry(forKey: key)?.viewFactory
    }
}
#endif
