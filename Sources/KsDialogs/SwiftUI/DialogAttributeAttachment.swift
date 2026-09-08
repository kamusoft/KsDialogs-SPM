#if canImport(UIKit)
import SwiftUI

/// SwiftUI の中身に添付されたメタ属性の組。
/// 属性ごとに独立して書き込まれるため、片方だけの添付がもう片方を消すことはない。
struct DialogAttributeAttachment: Equatable, Sendable {
    var options: DialogOptions?
    var placement: DialogPlacement?
    var transition: DialogTransition?

    /// 演出は関数を持つため値としては比べられない。同じ組が届いたかどうかは印で見分ける。
    static func == (lhs: DialogAttributeAttachment, rhs: DialogAttributeAttachment) -> Bool {
        lhs.options == rhs.options
            && lhs.placement == rhs.placement
            && lhs.transition?.identity == rhs.transition?.identity
    }
}

/// 添付値を中身の階層からホストへ運ぶ preference。
///
/// 添付は `View` の階層を子から親へ遡って合流するため、入れ子で同じ属性を重ねると
/// 外側 (より上位の View) の値が内側の値を上書きする (core/ADR-0015)。
struct DialogAttributeAttachmentKey: PreferenceKey {
    static let defaultValue = DialogAttributeAttachment()

    /// 同じ階層に複数の添付が並んだ場合は、あとから合流した値を採る。
    /// 値のない面はそのまま残すので、別々の属性を別々の位置に添付できる。
    static func reduce(
        value: inout DialogAttributeAttachment,
        nextValue: () -> DialogAttributeAttachment
    ) {
        let next = nextValue()
        if next.options != nil {
            value.options = next.options
        }
        if next.placement != nil {
            value.placement = next.placement
        }
        if next.transition != nil {
            value.transition = next.transition
        }
    }
}

/// ダイアログの中身になる SwiftUI View にメタ属性を添付する面 (core/ADR-0015)。
///
/// 中身の body ルートに付けると、その中身をダイアログとして表示する器が
/// 初回のネイティブレイアウトパス完了時点の値を実効値として採用する。
/// 付けなかった面は契約の既定値を意味し、表示中に添付値を変えても表示は追随しない。
public extension View {
    /// この中身をダイアログとして表示するときの静的メタ属性。
    func ksDialogOptions(_ options: DialogOptions) -> some View {
        transformPreference(DialogAttributeAttachmentKey.self) { attachment in
            attachment.options = options
        }
    }

    /// この中身をダイアログとして表示するときの動的メタ属性 (置き場所)。
    /// show の引数で placement を渡した場合は、そちらがこの値を置換する。
    func ksDialogPlacement(_ placement: DialogPlacement) -> some View {
        transformPreference(DialogAttributeAttachmentKey.self) { attachment in
            attachment.placement = placement
        }
    }

    /// この中身をダイアログとして表示するときの出入りの演出 (core/ADR-0017)。
    /// フックには SwiftUI の中身を包むホスト View が渡る。
    func ksDialogTransition(_ transition: DialogTransition) -> some View {
        transformPreference(DialogAttributeAttachmentKey.self) { attachment in
            attachment.transition = transition
        }
    }
}
#endif
