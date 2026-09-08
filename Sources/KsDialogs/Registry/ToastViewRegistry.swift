#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

/// カスタム Toast の ViewModel 型をキーに View factory と ViewModel factory を引くレジストリ。
///
/// Dialog のレジストリ (`DialogViewRegistry`) とも Loading のレジストリ (`LoadingViewRegistry`) とも
/// 独立しており、同じ ViewModel 型をそれぞれへ別々の View で登録できる。
/// 片方の再登録は他方に影響しない。登録・解決は任意のスレッドから行える。
public final class ToastViewRegistry: @unchecked Sendable {
    /// 全入口が共有する既定のレジストリ。
    public static let shared = ToastViewRegistry()

    private let lock = NSLock()
    private var entries: [DialogViewModelKey: ToastRegistryEntry] = [:]

    public init() {}

    /// ViewModel 型に対する従来 View 系の factory を登録する。
    /// 同じ型・同じスロットへの再登録は後勝ちで置き換え、ViewModel factory のスロットは保持される。
    /// factory は表示のたびに呼ばれ、View を毎回新規に生成する (core/ADR-0005)。
    ///
    /// factory が失敗を投げた表示は、受理後の失敗として警告を残してその1枚だけを破棄する
    /// (show は既に戻っているため呼び出し元へは返せない)。他の表示には影響しない。
    public func register<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) {
        register(
            ToastViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel 型に対する SwiftUI の中身の factory を登録する (core/ADR-0010・0011)。
    ///
    /// 従来 View 系の登録と同名で、factory の戻り値の型だけが違う。
    /// 登録・表示・レイアウトの挙動は従来 View 系と同一である。
    public func register<ViewModel: ToastViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) {
        register(
            ToastViewFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// ViewModel 型に対する ViewModel factory を登録する。
    ///
    /// 型指定の表示 (`show(ViewModel.self)`) はこの factory で ViewModel を作る。
    /// 同じ型・同じスロットへの再登録は後勝ちで置き換え、View factory のスロットは保持される。
    /// factory は表示のたびに呼ばれ、UI スレッドで実行される。
    public func register<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        viewModel factory: @escaping @MainActor @Sendable () -> ViewModel
    ) {
        register(
            ToastViewModelFactory.make(viewModelType, factory: factory),
            forKey: DialogViewModelKey(viewModelType)
        )
    }

    /// 型消去された View factory を登録する。
    func register(_ factory: ToastViewFactory, forKey key: DialogViewModelKey) {
        lock.lock()
        defer { lock.unlock() }
        entries[key, default: ToastRegistryEntry()].viewFactory = factory
    }

    /// 型消去された ViewModel factory を登録する。
    func register(_ factory: ToastViewModelFactory, forKey key: DialogViewModelKey) {
        lock.lock()
        defer { lock.unlock() }
        entries[key, default: ToastRegistryEntry()].viewModelFactory = factory
    }

    /// キーに対応するエントリを返す。どちらのスロットも未登録なら nil。
    /// 返すのは呼び出し時点のスナップショットで、以後の再登録には影響されない。
    func entry(forKey key: DialogViewModelKey) -> ToastRegistryEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    /// キーに対応する View factory を返す。未登録なら nil。
    /// 返すのは呼び出し時点のスナップショットで、以後の再登録には影響されない。
    func factory(forKey key: DialogViewModelKey) -> ToastViewFactory? {
        entry(forKey: key)?.viewFactory
    }
}
#endif
