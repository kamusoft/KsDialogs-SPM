#if canImport(UIKit)
/// アプリが前面を離れた合図を受け取る口。合図は UI スレッドで届く。
///
/// 購読1件は、提示先の出現の合図と同じ `DialogHostAppearanceRegistration` で表す。
typealias DialogForegroundDepartureHandler = @MainActor () -> Void
#endif
