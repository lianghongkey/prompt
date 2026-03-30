import SwiftUI
import CoreIME

struct NotationView: View {

        init(notation: Notation, comments: [Comment]) {
                self.notation = notation
                self.primaryLanguageComment = comments.first(where: \.language.isPrimaryCommentLanguage )
                self.moreLanguagesComments = comments.filter({ $0.language.isTranslation && !$0.language.isPrimaryCommentLanguage })
        }

        private let notation: Notation
        private let primaryLanguageComment: Comment?
        private let moreLanguagesComments: [Comment]

        var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(verbatim: notation.word)
                                        .font(.largeTitle)
                                Text(verbatim: notation.pinyin)
                                        .font(.title2)
                                        .foregroundStyle(Color.secondary)
                                if let primaryLanguageComment {
                                        Text(verbatim: primaryLanguageComment.text)
                                                .font(primaryLanguageComment.language.font)
                                }
                        }
                        .fixedSize()
                        if !moreLanguagesComments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                        Text(verbatim: "More Languages")
                                            .font(.title3.bold())
                                        if #available(macOS 13.0, *) {
                                                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                                                        ForEach(0..<moreLanguagesComments.count, id: \.self) { index in
                                                                                let comment = moreLanguagesComments[index]
                                                                                GridRow {
                                                                                        Text(verbatim: comment.language.name)
                                                                                                .font(.headline)
                                                                                                .foregroundStyle(Color.secondary)
                                                                                                .gridColumnAlignment(.trailing)
                                                                                        Text(verbatim: comment.text)
                                                                                                .font(comment.language.font)
                                                                                }
                                                                                .padding(comment.language.padding)
                                                                        }
                                                        }
                                                        .fixedSize()
                                        } else {
                                                VStack(alignment: .leading, spacing: 8) {
                                                        ForEach(0..<moreLanguagesComments.count, id: \.self) { index in
                                                                                let comment = moreLanguagesComments[index]
                                                                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                                                                        Text(verbatim: comment.language.name)
                                                                                                .lineLimit(1)
                                                                                                .minimumScaleFactor(0.5)
                                                                                                .font(.headline)
                                                                                                .foregroundStyle(Color.secondary)
                                                                                                .frame(width: 80, alignment: .trailing)
                                                                                        Text(verbatim: comment.text)
                                                                                                .font(comment.language.font)
                                                                                }
                                                                                .padding(comment.language.padding)
                                                                        }
                                                        }
                                                        .fixedSize()
                                                }
                                }
                        }
                }
        }
}

#if DEBUG
#Preview {
        NotationView(notation: .example, comments: [])
}
#endif
