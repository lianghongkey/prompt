import Foundation
import SQLite3

// MARK: - Shared Types

public struct SegmentToken: Hashable, Sendable {
        /// Token
        public let text: String
        /// Regular Pinyin Syllable
        public let origin: String
}

public typealias SegmentScheme = Array<SegmentToken>
public typealias Segmentation = Array<SegmentScheme>

extension SegmentScheme {
        /// All token text character count
        public var length: Int {
                var count = 0
                for token in self {
                        count += token.text.count
                }
                return count
        }
}

extension Segmentation {
        /// Longest scheme token text character count
        public var maxSchemeLength: Int {
                return self.first?.length ?? 0
        }
        /// All token count
        public var subelementCount: Int {
                return self.map(\.count).summation
        }
}

// MARK: - PinyinSegmentor

public struct PinyinSegmentor {

        /// Cache for pinyinsyllabletable lookups (~400 entries, never changes)
        nonisolated(unsafe) private static var syllableCache: [Int: String] = [:]

        /// Valid pinyin initials (声母) - single letter
        private static let singleLetterInitials: Set<Character> = [
                "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                "j", "q", "x", "r", "z", "c", "s", "y", "w"
        ]

        /// Vowels that can start zero-initial syllables (零声母)
        private static let zeroInitialVowels: Set<Character> = ["a", "o", "e"]

        /// Calculate the maximum number of syllables that the input could represent.
        /// This counts both complete syllables and potential syllable prefixes.
        ///
        /// Examples:
        /// - "l" → 1 (one syllable prefix)
        /// - "li" → 1 (one complete syllable)
        /// - "lh" → 2 (two syllable prefixes: l + h)
        /// - "lian" → 1 (one complete syllable)
        /// - "lianh" → 2 (lian + h)
        /// - "liangho" → 2 (liang + ho)
        /// - "nihao" → 2 (ni + hao)
        public static func maxSyllableCount(for text: String) -> Int {
                guard !text.isEmpty else { return 0 }

                // Find the best partial segmentation (covers as many characters as possible)
                let (coveredLength, syllableCount) = findBestPartialSegmentation(text)

                if coveredLength == text.count {
                        // Complete coverage
                        return syllableCount
                }

                if coveredLength > 0 {
                        // Partial coverage: segmented syllables + remaining potential syllables
                        let remaining = String(text.dropFirst(coveredLength))
                        return syllableCount + countPotentialSyllables(remaining)
                }

                // No segmentation possible, count potential syllables
                return countPotentialSyllables(text)
        }

        /// Find the best partial segmentation that covers the most characters.
        /// Returns (covered character count, syllable count)
        private static func findBestPartialSegmentation(_ text: String) -> (Int, Int) {
                guard !text.isEmpty else { return (0, 0) }

                var bestCoverage = 0
                var bestSyllableCount = 0

                // Use iterative approach with a work queue to avoid deep recursion
                // State: (startIndex, syllableCount)
                var visited = Set<Int>()
                var queue: [(Int, Int)] = [(0, 0)]

                while !queue.isEmpty {
                        let (startIndex, syllableCount) = queue.removeFirst()

                        // Update best if this is better coverage
                        if startIndex > bestCoverage || (startIndex == bestCoverage && syllableCount < bestSyllableCount) {
                                bestCoverage = startIndex
                                bestSyllableCount = syllableCount
                        }

                        if startIndex >= text.count { continue }
                        if visited.contains(startIndex) { continue }
                        visited.insert(startIndex)

                        // Try matching syllables of different lengths (longest first for efficiency)
                        let remaining = String(text.dropFirst(startIndex))
                        let maxLen = min(6, remaining.count)

                        for len in (1...maxLen).reversed() {
                            let prefix = String(remaining.prefix(len))
                            if matchDirect(prefix) != nil {
                                queue.append((startIndex + len, syllableCount + 1))
                            }
                        }
                }

                return (bestCoverage, bestSyllableCount)
        }

        /// Count potential syllables in text that couldn't be segmented into complete syllables.
        /// Each valid pinyin initial (声母) counts as a potential syllable.
        /// Zero-initial vowels (a, o, e) only count as new syllables at the very start of the text.
        private static func countPotentialSyllables(_ text: String) -> Int {
                guard !text.isEmpty else { return 0 }

                var count = 0
                var i = text.startIndex
                var isAtStart = true  // Track if we're at the start of the text

                while i < text.endIndex {
                        let char = text[i]

                        // Check for two-letter initials (zh, ch, sh)
                        let nextIndex = text.index(after: i)
                        if nextIndex < text.endIndex {
                                let twoChars = String(text[i...nextIndex])
                                if twoChars == "zh" || twoChars == "ch" || twoChars == "sh" {
                                        count += 1
                                        isAtStart = false
                                        i = text.index(after: nextIndex)
                                        // Skip all following non-initial characters (they're part of this syllable)
                                        while i < text.endIndex && !singleLetterInitials.contains(text[i]) {
                                                // But stop if we hit a zero-initial vowel that's clearly a new syllable
                                                // This happens when we see patterns like "zha" where 'a' follows the syllable
                                                i = text.index(after: i)
                                        }
                                        continue
                                }
                        }

                        // Check for single-letter initial
                        if singleLetterInitials.contains(char) {
                                count += 1
                                isAtStart = false
                                i = text.index(after: i)
                                // Skip all following non-initial characters (they're part of this syllable)
                                while i < text.endIndex && !singleLetterInitials.contains(text[i]) {
                                        i = text.index(after: i)
                                }
                        } else if zeroInitialVowels.contains(char) && isAtStart {
                                // Zero-initial syllable (a, o, e) - only at the very start
                                count += 1
                                isAtStart = false
                                i = text.index(after: i)
                                // Skip following non-initial characters
                                while i < text.endIndex && !singleLetterInitials.contains(text[i]) {
                                        i = text.index(after: i)
                                }
                        } else {
                                // Other characters, skip
                                isAtStart = false
                                i = text.index(after: i)
                        }
                }

                return count == 0 ? 1 : count  // At least 1 if text is not empty
        }

        public static func segment(text: String) -> Segmentation {
                switch text.count {
                case 0:
                        return []
                case 1:
                        switch text {
                        case "a", "o", "e":
                                return [[SegmentToken(text: text, origin: text)]]
                        default:
                                return []
                        }
                default:
                        return split(text)
                }
        }

        private static func split(_ text: String) -> Segmentation {
                let leadingTokens: [SegmentToken] = splitLeading(text)
                guard leadingTokens.isNotEmpty else { return [] }
                let textCount = text.count
                var schemeSet: Set<SegmentScheme> = Set(leadingTokens.map({ [$0] }))
                var previousCount = 0
                var shouldContinue: Bool = true
                while shouldContinue {
                        var newSchemes: [SegmentScheme] = []
                        for scheme in schemeSet {
                                let schemeLength = scheme.length
                                guard schemeLength < textCount else { continue }
                                let tailText = String(text.dropFirst(schemeLength))
                                let tailTokens = splitLeading(tailText)
                                guard tailTokens.isNotEmpty else { continue }
                                for token in tailTokens {
                                        let newScheme = scheme + [token]
                                        newSchemes.append(newScheme)
                                }
                        }
                        for scheme in newSchemes {
                                schemeSet.insert(scheme)
                        }
                        guard schemeSet.count < 50 else { break }
                        let currentCount = schemeSet.count
                        if currentCount != previousCount {
                                previousCount = currentCount
                        } else {
                                shouldContinue = false
                        }
                }
                let sequences: Segmentation = schemeSet.sorted(by: {
                        let lhsLength: Int = $0.length
                        let rhsLength: Int = $1.length
                        if lhsLength == rhsLength {
                                return $0.count < $1.count
                        } else {
                                return lhsLength > rhsLength
                        }
                })
                return sequences
        }

        private static func splitLeading(_ text: String) -> [SegmentToken] {
                let maxLength: Int = min(text.count, 6)
                guard maxLength > 0 else { return [] }
                let tokens = (1...maxLength).reversed().compactMap({ match(text.prefix($0)) })
                return tokens
        }

        private static func match<T: StringProtocol>(_ text: T) -> SegmentToken? {
                // 先尝试直接匹配
                if let token = matchDirect(text) {
                        return token
                }

                // 如果启用了模糊音，尝试模糊匹配
                if FuzzyPinyinSettings.isAnyEnabled {
                        return matchWithFuzzy(text)
                }

                return nil
        }

        /// 直接匹配数据库中的音节（带缓存）
        private static func matchDirect<T: StringProtocol>(_ text: T) -> SegmentToken? {
                guard let code: Int = text.charcode else { return nil }
                if let cached = syllableCache[code] {
                        return SegmentToken(text: cached, origin: cached)
                }
                let command: String = "SELECT syllable FROM pinyinsyllabletable WHERE code = ? LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(Engine.database, command, -1, &statement, nil) == SQLITE_OK else { return nil }
                guard sqlite3_bind_int64(statement, 1, Int64(code)) == SQLITE_OK else { return nil }
                guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
                guard let syllablePtr = sqlite3_column_text(statement, 0) else { return nil }
                let syllable: String = String(cString: syllablePtr)
                syllableCache[code] = syllable
                return SegmentToken(text: syllable, origin: syllable)
        }

        /// 使用模糊音匹配
        private static func matchWithFuzzy<T: StringProtocol>(_ text: T) -> SegmentToken? {
                let textString = String(text)

                // 尝试使用模糊音扩展
                let expanded = FuzzyPinyinExpander.expand(textString)

                // 对每个扩展的拼音尝试匹配
                for variant in expanded {
                        if let token = matchDirect(variant) {
                                // 找到匹配：
                                // - text: 使用原始输入（保持正确的字符长度）
                                // - origin: 使用匹配到的标准音节（用于后续数据库查询）
                                return SegmentToken(text: textString, origin: token.origin)
                        }
                }

                return nil
        }
}
