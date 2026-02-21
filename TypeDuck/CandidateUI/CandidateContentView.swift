import SwiftUI
import CoreIME

struct CandidateContentView: View {

        let candidate: DisplayCandidate
        let hasNotationDisplayButton: Bool

        var body: some View {
                let annotationComments = candidate.comments.filter(\.language.isAnnotation)
                let enabledTranslations = candidate.comments.filter(\.language.isEnabledCommentLanguage)
                let latinComments = enabledTranslations.filter(\.language.isLatin)
                let devanagariComments = enabledTranslations.filter(\.language.isDevanagari)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                        PinyinLabel(text: candidate.candidate.text, romanization: candidate.candidate.romanization, shouldDisplayRomanization: false)
                        if annotationComments.isNotEmpty {
                                ForEach(0..<annotationComments.count, id: \.self) { index in
                                        let comment = annotationComments[index]
                                        Text(verbatim: comment.text).font(comment.language.font)
                                }
                        }
                        if latinComments.isNotEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                        ForEach(0..<latinComments.count, id: \.self) { index in
                                                let comment = latinComments[index]
                                                Text(verbatim: comment.text).font(comment.language.font)
                                        }
                                }
                        }
                        if devanagariComments.isNotEmpty {
                                VStack(alignment: .leading, spacing: -6) {
                                        ForEach(0..<devanagariComments.count, id: \.self) { index in
                                                let comment = devanagariComments[index]
                                                Text(verbatim: comment.text).font(comment.language.font)
                                        }
                                }
                        }
                        if let comment = enabledTranslations.first(where: \.language.isRTL) {
                                Text(verbatim: comment.text).font(comment.language.font)
                        }
                }
        }
}

#Preview {
        CandidateContentView(candidate: DisplayCandidate(candidate: .example, candidateIndex: 3), hasNotationDisplayButton: true)
}
