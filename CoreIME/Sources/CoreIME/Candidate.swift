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

        /// Cached syllable count of input, used for sorting
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
                self.syllableCount = PinyinSegmentor.maxSyllableCount(for: input)
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
                self.syllableCount = PinyinSegmentor.maxSyllableCount(for: input)
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
                self.syllableCount = PinyinSegmentor.maxSyllableCount(for: input)
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

        // Comparable
        public static func < (lhs: Candidate, rhs: Candidate) -> Bool {
                // 1. Input length first (longer input = more complete match of what user typed)
                // This ensures "这里面" (input="zhelimian") beats "这里" (input="zheli")
                // regardless of whether either is from user lexicon or engine.
                guard lhs.input.count == rhs.input.count else { return lhs.input.count > rhs.input.count }

                // 2. User lexicon (order < 0) before system lexicon, within same input length
                let lhsIsUser = lhs.order < 0
                let rhsIsUser = rhs.order < 0
                if lhsIsUser != rhsIsUser {
                        return lhsIsUser  // user lexicon comes before system lexicon
                }

                // 3. Within user lexicon, sort by frequency (order = -frequency, so more negative = higher frequency)
                if lhsIsUser && rhsIsUser {
                        return lhs.order < rhs.order  // higher frequency (more negative) comes first
                }

                // 4. Prioritize candidates whose character count matches the estimated syllable count
                // For input "liangh" (2 syllables), prefer 2-character words over 1-character words
                let lhsMatchesSyllables = lhs.text.count == lhs.syllableCount
                let rhsMatchesSyllables = rhs.text.count == rhs.syllableCount
                if lhsMatchesSyllables != rhsMatchesSyllables {
                        return lhsMatchesSyllables  // matching syllable count comes first
                }

                // 5. Then by text length (shorter text = more common, but only within same syllable-match group)
                guard lhs.text.count == rhs.text.count else { return lhs.text.count < rhs.text.count }

                // 6. Then by database order (rowid, lower = more common)
                // This ensures zi and zhi candidates are interleaved by frequency
                guard lhs.order == rhs.order else { return lhs.order < rhs.order }

                return false
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
