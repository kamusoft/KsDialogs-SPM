/// ObjC 境界から受け取った値やクロージャを、並行性検査を跨いで運ぶための輸送箱。
/// 中身のスレッド安全性は受け渡し元の責務であり、この箱は保証しない。
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
