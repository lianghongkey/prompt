import Foundation
import SQLite3

// MARK: - Shared Types

/// A single piece of a segmentation. Either:
/// - `.full`: `text` is a complete syllable; `origin` is its canonical form (used for DB queries).
/// - `.abbrev`: `text` is a 1- or 2-letter initial (`b/p/m/.../w` or `zh/ch/sh`);
///   `origin == text`. Stands for "any syllable starting with these letters".
public struct SegmentToken: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
                case full
                case abbrev
        }

        public let text: String
        public let origin: String
        public let kind: Kind

        public init(text: String, origin: String, kind: Kind) {
                self.text = text
                self.origin = origin
                self.kind = kind
        }

        public var isFull: Bool { kind == .full }
        public var isAbbrev: Bool { kind == .abbrev }
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

        /// Number of `.abbrev` tokens.
        public var abbrevCount: Int {
                return self.reduce(0, { $0 + ($1.isAbbrev ? 1 : 0) })
        }

        /// True iff every token is `.full` (eligible for the fast `ping` index).
        public var isAllFull: Bool {
                return !self.contains(where: \.isAbbrev)
        }
}

extension Segmentation {
        /// Best scheme's text-character count
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

        /// Cache for `pinyinsyllabletable` lookups (~400 entries, never changes).
        nonisolated(unsafe) private static var syllableCache: [Int: String] = [:]

        /// Cache for `segment(text:)` results, keyed by raw input.
        nonisolated(unsafe) private static var schemeCache: [String: Segmentation] = [:]

        /// Hard cap on cache size (FIFO eviction). Segmentation results are small;
        /// 256 entries is plenty for normal typing patterns.
        private static let schemeCacheLimit = 256

        /// Valid pinyin initials (声母) - single letter
        public static let singleLetterInitials: Set<Character> = [
                "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                "j", "q", "x", "r", "z", "c", "s", "y", "w"
        ]

        /// Two-letter retroflex initials.
        public static let twoLetterInitials: Set<String> = ["zh", "ch", "sh"]

        /// All strings legal as `.abbrev` token `text`.
        public static let validAbbrevs: Set<String> = {
                var s = Set<String>()
                for c in singleLetterInitials { s.insert(String(c)) }
                for ab in twoLetterInitials { s.insert(ab) }
                return s
        }()

        /// Vowels that can start zero-initial syllables (零声母)
        public static let zeroInitialVowels: Set<Character> = ["a", "o", "e"]

        // MARK: - Public API

        /// Segment `text` into all valid hybrid schemes.
        ///
        /// A scheme covers the entire input. Each token is either:
        /// - a complete syllable from `pinyinsyllabletable`, or
        /// - a 1- or 2-letter initial (`b/p/.../w`, `zh/ch/sh`) standing for "any
        ///   syllable starting with these letters".
        ///
        /// Schemes are sorted with the most-preferred first:
        /// 1. fewer tokens (more grouped → less ambiguity);
        /// 2. fewer `.abbrev` tokens (more concrete information);
        /// 3. lexical tiebreaker (full tokens earlier in the scheme).
        public static func segment(text: String) -> Segmentation {
                guard !text.isEmpty else { return [] }
                if let cached = schemeCache[text] { return cached }

                let chars = Array(text)
                var memo: [Int: [SegmentScheme]] = [:]
                let raw = build(chars: chars, start: 0, memo: &memo)

                let sorted = raw.sorted(by: schemeIsBetter(_:_:))
                cacheScheme(text: text, segmentation: sorted)
                return sorted
        }

        /// Number of tokens in the best (first) scheme. Equals 0 when input is empty
        /// or cannot be segmented at all.
        public static func maxSyllableCount(for text: String) -> Int {
                guard !text.isEmpty else { return 0 }
                return segment(text: text).first?.count ?? 0
        }

        /// Reset all caches. Call after settings that affect segmentation change.
        public static func resetCaches() {
                schemeCache.removeAll(keepingCapacity: true)
                syllableCache.removeAll(keepingCapacity: true)
        }

        // MARK: - Recursive builder

        /// Returns every full-coverage scheme starting at `start`. A scheme of length
        /// 0 is the trivial "we covered everything" base case.
        private static func build(chars: [Character], start: Int, memo: inout [Int: [SegmentScheme]]) -> [SegmentScheme] {
                if start == chars.count { return [[]] }
                if let cached = memo[start] { return cached }

                var results: [SegmentScheme] = []
                let remaining = chars.count - start
                let maxLen = min(6, remaining)

                // Try syllable matches first, longest-first; then 2-letter abbrev (zh/ch/sh);
                // then 1-letter abbrev. The order does not affect correctness — only the
                // rate at which the schemeIsBetter sort settles on the winner.
                for len in (1...maxLen).reversed() {
                        let sub = String(chars[start ..< (start + len)])
                        // Full syllable?
                        if let canonical = matchSyllable(sub) {
                                let token = SegmentToken(text: sub, origin: canonical, kind: .full)
                                let tails = build(chars: chars, start: start + len, memo: &memo)
                                for tail in tails {
                                        results.append([token] + tail)
                                }
                        }
                        // Abbrev (only at len 1 or 2)?
                        if len <= 2, validAbbrevs.contains(sub) {
                                // Skip if we just matched it as a full syllable (e.g., `a/e/o` are
                                // never abbrevs because they're complete zero-initial syllables).
                                if matchSyllable(sub) == nil {
                                        let token = SegmentToken(text: sub, origin: sub, kind: .abbrev)
                                        let tails = build(chars: chars, start: start + len, memo: &memo)
                                        for tail in tails {
                                                results.append([token] + tail)
                                        }
                                }
                        }

                        // Hard cap to keep pathological inputs from exploding.
                        if results.count > 200 { break }
                }

                memo[start] = results
                return results
        }

        // MARK: - Scheme ranking

        /// Returns true iff `lhs` should sort before `rhs`.
        private static func schemeIsBetter(_ lhs: SegmentScheme, _ rhs: SegmentScheme) -> Bool {
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                let lAb = lhs.abbrevCount
                let rAb = rhs.abbrevCount
                if lAb != rAb { return lAb < rAb }
                // Lexicographic by token kinds: full < abbrev at the leftmost differing position.
                for (a, b) in zip(lhs, rhs) {
                        if a.isAbbrev != b.isAbbrev {
                                return !a.isAbbrev
                        }
                }
                return false
        }

        // MARK: - Syllable lookup

        /// Look up `sub` in `pinyinsyllabletable`. Returns the canonical syllable
        /// (e.g. `lue → lve`) or nil if not a syllable.
        private static func matchSyllable<T: StringProtocol>(_ text: T) -> String? {
                // Try direct match first.
                if let canonical = matchDirect(text) {
                        return canonical
                }
                // Then fuzzy expansion if enabled.
                if FuzzyPinyinSettings.isAnyEnabled {
                        let str = String(text)
                        for variant in FuzzyPinyinExpander.expand(str) where variant != str {
                                if let canonical = matchDirect(variant) {
                                        return canonical
                                }
                        }
                }
                return nil
        }

        private static func matchDirect<T: StringProtocol>(_ text: T) -> String? {
                guard let code: Int = text.charcode else { return nil }
                if let cached = syllableCache[code] {
                        return cached.isEmpty ? nil : cached
                }
                let command: String = "SELECT syllable FROM pinyinsyllabletable WHERE code = ? LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(Engine.database, command, -1, &statement, nil) == SQLITE_OK else { return nil }
                guard sqlite3_bind_int64(statement, 1, Int64(code)) == SQLITE_OK else { return nil }
                guard sqlite3_step(statement) == SQLITE_ROW else {
                        // Cache the negative result with empty string (so repeat lookups are O(1)).
                        syllableCache[code] = ""
                        return nil
                }
                guard let syllablePtr = sqlite3_column_text(statement, 0) else { return nil }
                let canonical = String(cString: syllablePtr)
                syllableCache[code] = canonical
                return canonical
        }

        // MARK: - Cache management

        private static func cacheScheme(text: String, segmentation: Segmentation) {
                if schemeCache.count >= schemeCacheLimit {
                        // Cheap eviction: drop a single arbitrary entry. Cache is small and
                        // temporal locality is high, so this is fine.
                        if let key = schemeCache.keys.first {
                                schemeCache.removeValue(forKey: key)
                        }
                }
                schemeCache[text] = segmentation
        }
}
