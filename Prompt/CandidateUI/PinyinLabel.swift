import SwiftUI

/// Display Mandarin text and Pinyin romanization
struct PinyinLabel: View {

        /// Mandarin text
        let text: String

        /// Pinyin
        let romanization: String

        let shouldDisplayRomanization: Bool

        var body: some View {
                if shouldDisplayRomanization {
                        VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: romanization).font(.romanization)
                                Text(verbatim: text).font(.candidate).tracking(16)
                        }
                } else {
                        Text(verbatim: text).font(.candidate)
                }
        }
}

#Preview {
        PinyinLabel(text: "示例", romanization: "shi4 li4", shouldDisplayRomanization: true)
}
