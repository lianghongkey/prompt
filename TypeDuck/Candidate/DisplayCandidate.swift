import Foundation
import CoreIME

struct DisplayCandidate: Hashable {

        let candidate: Candidate
        let candidateIndex: Int
        let comments: [Comment]

        init(candidate: Candidate, candidateIndex: Int) {
                self.candidate = candidate
                self.candidateIndex = candidateIndex
                self.comments = {
                        switch candidate.type {
                        case .mandarin:
                                return candidate.notation?.comments ?? []
                        case .text:
                                return []
                        case .emoji, .symbol:
                                var comments: [Comment] = []
                                let mandarinText = candidate.lexiconText
                                if mandarinText.isNotEmpty {
                                        let mandarinComment = Comment(language: .Mandarin, text: "〔\(mandarinText)〕")
                                        comments.append(mandarinComment)
                                }
                                return comments
                        case .compose:
                                var comments: [Comment] = []
                                let mandarinText = candidate.lexiconText
                                if mandarinText.isNotEmpty {
                                        let mandarinComment = Comment(language: .Mandarin, text: "〔\(mandarinText)〕")
                                        comments.append(mandarinComment)
                                }
                                let unicodeCodePoint = candidate.romanization
                                if unicodeCodePoint.isNotEmpty {
                                        let unicodeComment =  Comment(language: .Unicode, text: unicodeCodePoint)
                                        comments.append(unicodeComment)
                                }
                                return comments
                        }
                }()
        }
}

extension Notation {
        var comments: [Comment] {
                return Language.allCases.compactMap({ language -> Comment? in
                        switch language {
                        case .Mandarin:
                                return nil
                        case .English:
                                guard english.isValid else { return nil }
                                return Comment(language: language, text: english)
                        case .Hindi:
                                guard hindi.isValid else { return nil }
                                return Comment(language: language, text: hindi)
                        case .Indonesian:
                                guard indonesian.isValid else { return nil }
                                return Comment(language: language, text: indonesian)
                        case .Nepali:
                                guard nepali.isValid else { return nil }
                                return Comment(language: language, text: nepali)
                        case .Urdu:
                                guard urdu.isValid else { return nil }
                                return Comment(language: language, text: urdu)
                        case .Unicode:
                                return nil
                        }
                })
        }
}
