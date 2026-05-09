public enum CandidateType: Int, Sendable {

        case mandarin

        /// Plain text. Examples: iPad, macOS
        case text

        /// Note that `Candidate.text.count == 1` not always true
        case emoji

        /// Note that `Candidate.text.count == 1` not always true
        case symbol

        /// macOS Keyboard composed text. Mainly for PunctuationKey.
        case compose
}

public struct Candidate: Hashable, Comparable, Sendable {

        /// Candidate Type
        public let type: CandidateType

        /// Candidate text for display.
        public let text: String

        /// Candidate text for UserLexicon.
        public let lexiconText: String

        /// Pinyin
        public let romanization: String

        /// User input
        public let input: String

        /// Formatted user input for pre-edit display
        public let mark: String

        /// Rank. Smaller is preferred.
        public let order: Int

        /// Whether this candidate is from fuzzy pinyin matching
        public let isFuzzyMatch: Bool

        /// Cached syllable count of this candidate's own pinyin (from `romanization`).
        /// Used for sorting: a candidate whose `text.count` equals its own syllable
        /// count is treated as a "natural" reading and sorted by raw frequency rank;
        /// mismatched ones (e.g. 1-char from a partial-input tail-drop in a multi-syl
        /// query) are demoted. Deliberately NOT the input's max syllable count: that
        /// would unfairly demote a 2-char candidate from an alternative segmentation
        /// (e.g. 图案 from `tu+an` when best scheme is `[tuan]`).
        let syllableCount: Int

        /// Lexicon detail information
        public let notation: Notation?

        /// For Compound Translations
        public let subNotations: [Notation]

        /// Primary Initializer
        /// - Parameters:
        ///   - type: Candidate type.
        ///   - text: Candidate text for display.
        ///   - lexiconText: Candidate text for UserLexicon.
        ///   - romanization: Pinyin.
        ///   - input: User input for this Candidate.
        ///   - mark: Formatted user input for pre-edit display.
        ///   - order: Rank. Smaller is preferred.
        ///   - isFuzzyMatch: Whether this candidate is from fuzzy pinyin matching.
        ///   - notation: Lexicon detail information.
        ///   - subNotations: For Compound Translations.
        public init(type: CandidateType = .mandarin, text: String, lexiconText: String? = nil, romanization: String, input: String, mark: String? = nil, order: Int = 0, isFuzzyMatch: Bool = false, notation: Notation? = nil, subNotations: [Notation] = []) {
                self.type = type
                self.text = text
                self.lexiconText = lexiconText ?? text
                self.romanization = romanization
                self.input = input
                self.mark = mark ?? input
                self.order = order
                self.isFuzzyMatch = isFuzzyMatch
                self.syllableCount = romanization.split(separator: " ", omittingEmptySubsequences: true).count
                self.notation = notation
                self.subNotations = subNotations
        }

        /// Create a Candidate with an emoji or a symbol
        /// - Parameters:
        ///   - symbol: Emoji/Symbol text
        ///   - mandarin: Mandarin word for this Emoji/Symbol
        ///   - romanization: Romanization (Pinyin) of Mandarin word
        ///   - input: User input for this Candidate
        ///   - isEmoji: Emoji or symbol
        init(symbol: String, mandarin: String, romanization: String, input: String, isEmoji: Bool) {
                self.type = isEmoji ? .emoji : .symbol
                self.text = symbol
                self.lexiconText = mandarin
                self.romanization = romanization
                self.input = input
                self.mark = input
                self.order = 0
                self.isFuzzyMatch = false
                self.syllableCount = romanization.split(separator: " ", omittingEmptySubsequences: true).count
                self.notation = nil
                self.subNotations = []
        }

        /// Create a Candidate for keyboard compose
        /// - Parameters:
        ///   - text: Symbol text for this key compose
        ///   - comment: Name comment of this key symbol
        ///   - secondaryComment: Unicode code point
        ///   - input: User input for this Candidate
        public init(text: String, comment: String?, secondaryComment: String?, input: String) {
                self.type = .compose
                self.text = text
                self.lexiconText = comment ?? ""
                self.romanization = secondaryComment ?? ""
                self.input = input
                self.mark = input
                self.order = 0
                self.isFuzzyMatch = false
                self.syllableCount = romanization.split(separator: " ", omittingEmptySubsequences: true).count
                self.notation = nil
                self.subNotations = []
        }

        /// type == .mandarin
        public var isMandarin: Bool {
                return self.type == .mandarin
        }

        /// type != .mandarin
        public var isNotMandarin: Bool {
                return self.type != .mandarin
        }

        /// Concatenated by multiple lexicons
        public var isCompound: Bool {
                return subNotations.isNotEmpty
        }

        public var isUserLexicon: Bool {
                return order < 0
        }

        // Equatable
        public static func ==(lhs: Candidate, rhs: Candidate) -> Bool {
                guard lhs.type == rhs.type else { return false }
                if lhs.isMandarin && rhs.isMandarin {
                        return lhs.text == rhs.text && lhs.romanization == rhs.romanization
                } else {
                        return lhs.text == rhs.text
                }
        }

        // Hashable
        public func hash(into hasher: inout Hasher) {
                switch type {
                case .mandarin:
                        hasher.combine(text)
                        hasher.combine(romanization)
                case .text:
                        hasher.combine(text)
                case .emoji:
                        hasher.combine(text)
                case .symbol:
                        hasher.combine(text)
                case .compose:
                        hasher.combine(text)
                }
        }

        public static func < (lhs: Candidate, rhs: Candidate) -> Bool {
                let lhsIsUser = lhs.order < 0
                let rhsIsUser = rhs.order < 0
                if lhsIsUser != rhsIsUser {
                        return lhsIsUser
                }
                if lhsIsUser && rhsIsUser {
                        return lhs.order < rhs.order
                }

                // Demote candidates whose char count doesn't match their own pinyin
                // syllable count (rare; happens for compound/symbol candidates with
                // unusual romanization). Most mandarin DB entries are 1-char-per-syllable
                // so this is a no-op for the common case, leaving frequency (rowID) as
                // the primary tiebreaker among full-input matches.
                let lhsMatchesSyllables = lhs.text.count == lhs.syllableCount
                let rhsMatchesSyllables = rhs.text.count == rhs.syllableCount
                if lhsMatchesSyllables != rhsMatchesSyllables {
                        return lhsMatchesSyllables
                }

                return lhs.order < rhs.order
        }

        public static func +(lhs: Candidate, rhs: Candidate) -> Candidate? {
                guard lhs.isMandarin && rhs.isMandarin else { return nil }
                let newText: String = lhs.text + rhs.text
                let newLexiconText: String = lhs.lexiconText + rhs.lexiconText
                let newRomanization: String = lhs.romanization + " " + rhs.romanization
                let newInput: String = lhs.input + rhs.input
                let newMark: String = lhs.mark + rhs.mark
                let step: Int = 1_000_000
                let newOrder: Int = (lhs.order + step) + (rhs.order + step)
                let newIsFuzzyMatch: Bool = lhs.isFuzzyMatch || rhs.isFuzzyMatch
                let newSubNotations: [Notation] = {
                        var items: [Notation] = []
                        if let lhsNotation = lhs.notation {
                                items.append(lhsNotation)
                        } else {
                                items.append(contentsOf: lhs.subNotations)
                        }
                        if let rhsNotation = rhs.notation {
                                items.append(rhsNotation)
                        } else {
                                items.append(contentsOf: rhs.subNotations)
                        }
                        return items.uniqued()
                }()
                return Candidate(text: newText, lexiconText: newLexiconText, romanization: newRomanization, input: newInput, mark: newMark, order: newOrder, isFuzzyMatch: newIsFuzzyMatch, subNotations: newSubNotations)
        }
}

extension Array where Element == Candidate {

        /// Place candidates whose `input` covers the entire user text at the top,
        /// then fall through to `Candidate.<` for everything else.
        public func sortedWithFullMatchFirst(fullInputLength: Int) -> [Candidate] {
                return sorted(by: { lhs, rhs in
                        let lhsFull = lhs.input.count == fullInputLength
                        let rhsFull = rhs.input.count == fullInputLength
                        if lhsFull != rhsFull { return lhsFull }
                        return lhs < rhs
                })
        }

        /// Returns a new Candidate by concatenating this Candidate sequence.
        /// - Returns: Single, concatenated Candidate.
        public func joined() -> Candidate? {
                let isAllMandarin: Bool = !(contains(where: \.isNotMandarin))
                guard isAllMandarin else { return nil }
                let text: String = map(\.text).joined()
                let lexiconText: String = map(\.lexiconText).joined()
                let romanization: String = map(\.romanization).joined(separator: " ")
                let input: String = map(\.input).joined()
                let mark: String = map(\.mark).joined()
                let step: Int = 1_000_000
                let order: Int = map(\.order).reduce(0, { $0 + $1 + step })
                let isFuzzyMatch: Bool = contains(where: \.isFuzzyMatch)
                let subNotations: [Notation] = compactMap(\.notation)
                return Candidate(text: text, lexiconText: lexiconText, romanization: romanization, input: input, mark: mark, order: order, isFuzzyMatch: isFuzzyMatch, subNotations: subNotations)
        }
}


#if DEBUG
extension Candidate {
        public static let example: Candidate = Candidate(text: "举例", lexiconText: "举例", romanization: "ju3 li4", input: "juli")
}
#endif
