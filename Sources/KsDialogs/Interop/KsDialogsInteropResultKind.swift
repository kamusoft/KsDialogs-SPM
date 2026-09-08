#if canImport(UIKit)

/// 互換面が運ぶ結果の判別。
/// ジェネリクスも associated value も ObjC 表現に出せないため、判別と値を分けて運ぶ。
@objc(KSDInteropDialogResultKind)
public enum KsDialogsInteropResultKind: Int, Sendable {
    case completed = 0
    case cancelled = 1
    case error = 2
}
#endif
