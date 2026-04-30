import Foundation
import SQLite3
import os.log

public struct Engine {

        private static let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Engine")

        public static func prepare() {
                logger.debug("Engine.prepare() called")
                let command: String = "SELECT rowid FROM pinyintable WHERE shortcut = 20 LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(statement) == SQLITE_ROW else { return }
                logger.debug("Engine.prepare() succeeded")
        }

        nonisolated(unsafe) static let database: OpaquePointer? = {
                var db: OpaquePointer? = nil
                guard let path: String = Bundle.module.path(forResource: "imedb", ofType: "sqlite3") else {
                        logger.error("Failed to find database bundle path")
                        return nil
                }

                var storageDatabase: OpaquePointer? = nil
                defer { sqlite3_close_v2(storageDatabase) }
                guard sqlite3_open_v2(path, &storageDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                        logger.error("Failed to open storage database")
                        return nil
                }

                guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                        logger.error("Failed to open memory database")
                        return nil
                }

                let backup = sqlite3_backup_init(db, "main", storageDatabase, "main")
                defer {
                        if let backup = backup {
                                sqlite3_backup_finish(backup)
                        }
                }

                guard let backup = backup else {
                        logger.error("Failed to initialize backup")
                        return nil
                }

                guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else {
                        logger.error("Failed to backup database")
                        return nil
                }

                logger.info("Database initialized successfully")
                return db
        }()

        // MARK: - Prepared Statements

        nonisolated(unsafe) static let pingStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT rowid, word, pinyin FROM pinyintable WHERE ping = ? LIMIT ?;", -1, &stmt, nil)
                return stmt
        }()

        nonisolated(unsafe) static let shortcutStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT rowid, word, pinyin FROM pinyintable WHERE shortcut = ? ORDER BY rowid LIMIT ?;", -1, &stmt, nil)
                return stmt
        }()


        // MARK: - Suggestion

        /// Suggestion - Uses Pinyin table for Mandarin input
        /// - Parameters:
        ///   - text: User input text.
        ///   - segmentation: Segmentation of user input text.
        ///   - needsSymbols: Needs Emoji/Symbol Candidates.
        ///   - asap: Should be fast, shouldn't go deep.
        /// - Returns: Candidates
        public static func suggest(text: String, segmentation: Segmentation, needsSymbols: Bool, asap: Bool = false) -> [Candidate] {
                switch text.count {
                case 0:
                        return []
                case 1:
                        // Single character input - try ping (full syllable like a/o/e) then shortcut.
                        let pinyinMatches = pinyinMatchInternal(text: text, input: text)
                        if !pinyinMatches.isEmpty { return pinyinMatches }
                        // Fall through to scheme-based query so single-letter abbrevs work.
                        return pinyinSuggestMulti(text: text, segmentation: segmentation)
                default:
                        return pinyinSuggestMulti(text: text, segmentation: segmentation)
                }
        }

        // MARK: - Multi-character / hybrid suggestion

        private static func pinyinSuggestMulti(text: String, segmentation: Segmentation) -> [Candidate] {
                guard let bestScheme = segmentation.first else {
                        // Segmentation truly empty (input has non-letter chars). Final fallback.
                        return shortcutQueryFallback(text: text)
                }

                // Pick all top-quality schemes (same token count and abbrev count as bestScheme).
                let bestQuality = SchemeQuality(scheme: bestScheme)
                let topSchemes = segmentation.filter { SchemeQuality(scheme: $0) == bestQuality }

                var allCandidates: [Candidate] = []
                var seenOrders = Set<Int>()
                var queriedHashes = Set<Int>()

                for scheme in topSchemes {
                        runScheme(scheme,
                                  fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                  isFallback: false,
                                  seenOrders: &seenOrders,
                                  queriedHashes: &queriedHashes,
                                  out: &allCandidates)
                }

                // Tail-drop fallback: drop trailing tokens to surface shorter prefix matches
                // (single-character candidates needed for word creation).
                for topScheme in topSchemes {
                        var fallbackScheme = topScheme
                        while fallbackScheme.count > 1 {
                                fallbackScheme = Array(fallbackScheme.dropLast())
                                runScheme(fallbackScheme,
                                          fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                          isFallback: true,
                                          seenOrders: &seenOrders,
                                          queriedHashes: &queriedHashes,
                                          out: &allCandidates)
                        }
                }

                allCandidates = allCandidates.sortedWithFullMatchFirst(fullInputLength: text.count)
                return allCandidates
        }

        /// Quality tuple used to select top schemes. Smaller is better.
        private struct SchemeQuality: Hashable {
                let count: Int
                let abbrevCount: Int
                init(scheme: SegmentScheme) {
                        self.count = scheme.count
                        self.abbrevCount = scheme.abbrevCount
                }
        }

        /// Dispatch a single scheme to the right query path (ping vs shortcut+filter),
        /// applying fuzzy expansion when enabled.
        private static func runScheme(_ scheme: SegmentScheme,
                                      fuzzyEnabled: Bool,
                                      isFallback: Bool,
                                      seenOrders: inout Set<Int>,
                                      queriedHashes: inout Set<Int>,
                                      out: inout [Candidate]) {
                let combinedInput = scheme.map(\.text).joined()

                let beforePingCount = out.count

                if scheme.isAllFull {
                        // Fast path: exact `ping` lookup using B-tree index.
                        let spacedPinyin = scheme.map(\.origin).joined(separator: " ")
                        let hash = spacedPinyin.deterministicHash
                        if queriedHashes.insert(hash).inserted {
                                let candidates = pinyinMatchInternal(text: spacedPinyin, input: combinedInput, isFuzzyMatch: false)
                                appendUnique(candidates, into: &out, seen: &seenOrders)
                        }
                        if fuzzyEnabled {
                                let pinyinArray = scheme.map(\.origin)
                                let expandedArrays = FuzzyPinyinExpander.expandArray(pinyinArray)
                                for expandedArray in expandedArrays {
                                        let expanded = expandedArray.joined(separator: " ")
                                        let h = expanded.deterministicHash
                                        guard queriedHashes.insert(h).inserted else { continue }
                                        let isFuzzy = expanded != spacedPinyin
                                        let candidates = pinyinMatchInternal(text: expanded, input: combinedInput, isFuzzyMatch: isFuzzy)
                                        appendUnique(candidates, into: &out, seen: &seenOrders)
                                }
                        }
                        // If ping found exact matches, we're done — exact full-pinyin
                        // typing should not get noisy prefix extensions. If ping returned
                        // nothing (e.g. user typed "zenmeyan" intending 怎么样), fall
                        // through to the shortcut+prefix path so prefix matches surface.
                        if out.count > beforePingCount { return }
                }

                // Hybrid (or all-abbrev, or fallback for empty ping) path: query by
                // shortcut intercode, filter in Swift via per-token prefix match.
                guard let shortcutCode = schemeShortcutCode(scheme) else { return }
                guard queriedHashes.insert(shortcutCode).inserted else { return }
                let candidates = shortcutSchemeQuery(scheme: scheme,
                                                     shortcutCode: shortcutCode,
                                                     input: combinedInput,
                                                     fuzzyEnabled: fuzzyEnabled,
                                                     isFallback: isFallback)
                appendUnique(candidates, into: &out, seen: &seenOrders)
        }

        private static func appendUnique(_ candidates: [Candidate],
                                         into out: inout [Candidate],
                                         seen: inout Set<Int>) {
                for c in candidates {
                        if seen.insert(c.order).inserted {
                                out.append(c)
                        }
                }
        }

        // MARK: - Shortcut scheme query (hybrid path)

        /// Compute the shortcut intercode from a scheme by taking the first character
        /// of each token. Returns nil if any token is empty or non-ASCII.
        private static func schemeShortcutCode(_ scheme: SegmentScheme) -> Int? {
                let firstChars: [Character] = scheme.compactMap { $0.text.first }
                guard firstChars.count == scheme.count else { return nil }
                let codes: [Int] = firstChars.compactMap(\.intercode)
                guard codes.count == firstChars.count else { return nil }
                let combined = codes.combined()
                return combined > 0 ? combined : nil
        }

        /// Query `pinyintable WHERE shortcut = ?`, then in-Swift filter so that
        /// each scheme token's `text` is a (possibly fuzzy) prefix of the corresponding
        /// space-separated pinyin syllable in the row.
        private static func shortcutSchemeQuery(scheme: SegmentScheme,
                                                shortcutCode: Int,
                                                input: String,
                                                fuzzyEnabled: Bool,
                                                isFallback: Bool) -> [Candidate] {
                guard let stmt = shortcutStatement else { return [] }
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(shortcutCode))
                // Higher LIMIT than legacy (200) so per-position filter still has enough
                // candidates to pick the most frequent matches from. Wider scheme.count
                // shortcuts can have thousands of entries; cap at 1000 indexed rows.
                sqlite3_bind_int64(stmt, 2, 1000)

                let schemeSyllableCount = scheme.count
                var results: [Candidate] = []

                while sqlite3_step(stmt) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(stmt, 0))
                        guard let wordPtr = sqlite3_column_text(stmt, 1) else { continue }
                        guard let pinyinPtr = sqlite3_column_text(stmt, 2) else { continue }
                        let word: String = String(cString: wordPtr)
                        let pinyin: String = String(cString: pinyinPtr)

                        // Word's character count must equal scheme.count (one syllable per character).
                        // Compound / multi-syllable-per-char entries are rare; the equality check
                        // matches the convention used by the rest of the suggest pipeline.
                        guard word.count == schemeSyllableCount else { continue }

                        let parts = pinyin.split(separator: " ")
                        guard parts.count == schemeSyllableCount else { continue }

                        var matched = true
                        var anyFuzzy = false
                        for (token, syl) in zip(scheme, parts) {
                                let syllable = String(syl)
                                let (ok, fuzzy) = tokenMatches(token: token, syllable: syllable, fuzzyEnabled: fuzzyEnabled)
                                if !ok { matched = false; break }
                                if fuzzy { anyFuzzy = true }
                        }
                        guard matched else { continue }

                        let candidate = Candidate(text: word,
                                                  romanization: pinyin,
                                                  input: input,
                                                  mark: input,
                                                  order: rowID,
                                                  isFuzzyMatch: anyFuzzy)
                        results.append(candidate)

                        // Cap output so a popular shortcut (e.g. wsm) does not flood the list.
                        if results.count >= 200 { break }
                }

                _ = isFallback // currently unused; reserved for future tuning of fallback weight
                return results
        }

        /// Match one scheme token against one space-separated pinyin syllable.
        /// Both `.full` and `.abbrev` tokens use **prefix match**: the token's text
        /// (which equals `origin` for full, equals the initial(s) for abbrev) must be
        /// a prefix of the stored syllable, or a fuzzy variant of it.
        ///
        /// Why prefix for `.full` too: a user-typed full syllable like "yan" should
        /// match canonical "yang" (since "yan" is a prefix of "yang"). This is
        /// what makes "zmyan" match 怎么样 (zen me **yang**). Exact-only matching is
        /// reserved for the `ping` fast path in `runScheme`, which the all-full
        /// branch tries first to keep frequent full-pinyin input clean.
        ///
        /// Returns (matched, usedFuzzy).
        private static func tokenMatches(token: SegmentToken,
                                         syllable: String,
                                         fuzzyEnabled: Bool) -> (Bool, Bool) {
                let needle = token.text
                if syllable.hasPrefix(needle) { return (true, false) }
                if !fuzzyEnabled { return (false, false) }
                for v in FuzzyPinyinExpander.expand(syllable) where v.hasPrefix(needle) {
                        return (true, true)
                }
                if token.kind == .full {
                        // Also try fuzzy variants of the canonical token form. "yan" has
                        // no fuzzy variants but a token like "in" has "ing", so the user
                        // typing "in" can match a stored "ing"-syllable.
                        for v in FuzzyPinyinExpander.expand(token.origin) where syllable.hasPrefix(v) {
                                return (true, true)
                        }
                }
                return (false, false)
        }

        // MARK: - Shortcut fallback for non-letter / unparseable input

        /// Last-resort fallback when segmentation is empty (e.g. input contains
        /// characters with no `intercode`). Walks the raw text and treats every
        /// valid initial as a 1-letter abbrev token.
        private static func shortcutQueryFallback(text: String) -> [Candidate] {
                var fakeScheme: SegmentScheme = []
                for ch in text {
                        guard ch.intercode != nil else { continue }
                        let s = String(ch)
                        if PinyinSegmentor.validAbbrevs.contains(s) {
                                fakeScheme.append(SegmentToken(text: s, origin: s, kind: .abbrev))
                        } else if PinyinSegmentor.zeroInitialVowels.contains(ch) {
                                fakeScheme.append(SegmentToken(text: s, origin: s, kind: .full))
                        }
                }
                guard !fakeScheme.isEmpty,
                      let code = schemeShortcutCode(fakeScheme) else { return [] }
                return shortcutSchemeQuery(scheme: fakeScheme,
                                           shortcutCode: code,
                                           input: text,
                                           fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                           isFallback: true)
        }

        // MARK: - Ping path (full pinyin exact match)

        private static func pinyinMatchInternal(text: String, input: String, isFuzzyMatch: Bool = false) -> [Candidate] {
                let code: Int = text.deterministicHash
                guard let stmt = pingStatement else { return [] }
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(code))
                sqlite3_bind_int64(stmt, 2, 100)

                let maxSyllableCount = PinyinSegmentor.maxSyllableCount(for: input)

                var candidates: [Candidate] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(stmt, 0))
                        guard let wordPtr = sqlite3_column_text(stmt, 1) else { continue }
                        guard let pinyinPtr = sqlite3_column_text(stmt, 2) else { continue }
                        let word: String = String(cString: wordPtr)
                        let pinyin: String = String(cString: pinyinPtr)

                        guard word.count <= maxSyllableCount else { continue }

                        let candidate = Candidate(text: word, romanization: pinyin, input: input, mark: input, order: rowID, isFuzzyMatch: isFuzzyMatch)
                        candidates.append(candidate)
                }
                return candidates
        }
}
