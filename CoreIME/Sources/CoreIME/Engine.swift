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

                // Alternative all-full segmentations (different token count from
                // bestQuality). E.g. "tuan" → best is [tuan] (count=1) but the user
                // may have intended [tu, an] for 图案. Probe these via ping only — no
                // shortcut/prefix fallback, since prefix-matching segmentations the
                // user didn't intend would just produce noise.
                for scheme in segmentation where scheme.isAllFull {
                        guard SchemeQuality(scheme: scheme) != bestQuality else { continue }
                        runScheme(scheme,
                                  fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                  isFallback: false,
                                  pingOnly: true,
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
        ///
        /// `pingOnly`: when true, skip the shortcut+prefix fallback even if ping
        /// returned no rows. Used for non-best alternative segmentations (e.g. when
        /// best is `[tuan]` and we additionally probe `[tu, an]` for 图案) — those
        /// should only contribute exact full-pinyin hits, never prefix noise from
        /// segmentations the user didn't intend.
        private static func runScheme(_ scheme: SegmentScheme,
                                      fuzzyEnabled: Bool,
                                      isFallback: Bool,
                                      pingOnly: Bool = false,
                                      seenOrders: inout Set<Int>,
                                      queriedHashes: inout Set<Int>,
                                      out: inout [Candidate]) {
                let combinedInput = scheme.map(\.text).joined()
                // Schemes from typo-corrected input (e.g. liagne → liange) are
                // semantically a near-miss, not a true exact match. Mark every
                // candidate they produce as fuzzy so it sorts below candidates from
                // schemes the user actually typed.
                let schemeIsTypoCorrected = scheme.isTypoCorrected

                if scheme.isAllFull {
                        // Fast path: exact `ping` lookup using B-tree index.
                        // Track whether any DB ping query returned rows (regardless of dedup
                        // against `out`) — a hit means exact full-pinyin matches exist and
                        // we must NOT fall through to the prefix-matching shortcut path,
                        // even if the matches were already added by an earlier scheme.
                        var pingProducedAny = false
                        let spacedPinyin = scheme.map(\.origin).joined(separator: " ")
                        let hash = spacedPinyin.deterministicHash
                        if queriedHashes.insert(hash).inserted {
                                let candidates = pinyinMatchInternal(text: spacedPinyin, input: combinedInput, isFuzzyMatch: schemeIsTypoCorrected, maxSyllableCount: scheme.count)
                                if !candidates.isEmpty { pingProducedAny = true }
                                appendUnique(candidates, into: &out, seen: &seenOrders)
                        }
                        if fuzzyEnabled {
                                let pinyinArray = scheme.map(\.origin)
                                let expandedArrays = FuzzyPinyinExpander.expandArray(pinyinArray)
                                for expandedArray in expandedArrays {
                                        let expanded = expandedArray.joined(separator: " ")
                                        let h = expanded.deterministicHash
                                        guard queriedHashes.insert(h).inserted else { continue }
                                        let isFuzzy = expanded != spacedPinyin || schemeIsTypoCorrected
                                        let candidates = pinyinMatchInternal(text: expanded, input: combinedInput, isFuzzyMatch: isFuzzy, maxSyllableCount: scheme.count)
                                        if !candidates.isEmpty { pingProducedAny = true }
                                        appendUnique(candidates, into: &out, seen: &seenOrders)
                                }
                        }
                        // If ping found exact matches, we're done — exact full-pinyin
                        // typing should not get noisy prefix extensions. If ping returned
                        // nothing (e.g. user typed "zenmeyan" intending 怎么样), fall
                        // through to the shortcut+prefix path so prefix matches surface.
                        if pingProducedAny { return }
                        if pingOnly { return }
                } else if pingOnly {
                        return
                }

                // Hybrid (or all-abbrev, or fallback for empty ping) path: query by
                // shortcut intercode, filter in Swift via per-token prefix match.
                guard let shortcutCode = schemeShortcutCode(scheme) else { return }
                guard queriedHashes.insert(shortcutCode).inserted else { return }
                let candidates = shortcutSchemeQuery(scheme: scheme,
                                                     shortcutCode: shortcutCode,
                                                     input: combinedInput,
                                                     fuzzyEnabled: fuzzyEnabled,
                                                     isFallback: isFallback,
                                                     forceFuzzyMatch: schemeIsTypoCorrected)
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
        /// each scheme token matches the corresponding space-separated pinyin
        /// syllable per `tokenMatches`. `forceFuzzyMatch` tags every produced
        /// Candidate `isFuzzyMatch = true` regardless of per-token fuzzy use —
        /// caller passes `true` when the scheme came from typo correction so
        /// those near-miss matches sort below true exact-typed candidates.
        private static func shortcutSchemeQuery(scheme: SegmentScheme,
                                                shortcutCode: Int,
                                                input: String,
                                                fuzzyEnabled: Bool,
                                                isFallback: Bool,
                                                forceFuzzyMatch: Bool = false) -> [Candidate] {
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
                        var anyFuzzy = forceFuzzyMatch
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
        /// The two kinds match by different rules:
        ///
        /// - `.abbrev`: prefix match. The 1- or 2-letter initial must be a prefix
        ///   of the stored syllable (e.g. token `"z"` matches `"zen"`, `"zhong"`).
        ///   Prefix is the whole point of an abbrev token.
        ///
        /// - `.full`: equality match against `token.origin` (the canonical syllable),
        ///   modulo fuzzy-pinyin equivalence. Prefix is **forbidden** here: `"ne"`
        ///   is a complete syllable and must not silently extend to `"neng"`; they
        ///   are different syllables.
        ///
        /// Rationale: allowing prefix on `.full` produced compound noise. With
        /// `on/ong` fuzzy, `gonne` segments as `[gon→gong, ne]`; ping `"gong ne"`
        /// finds nothing, then prefix-match used to extend `"ne" → "neng"` via
        /// the shortcut path, surfacing 功能 (gong neng) — every token gets
        /// "brain-expanded" and the candidate list fills with noise.
        ///
        /// Trade-off: cases like `zmyan → 怎么样` (yan/yang near-miss) and
        /// `zenmeyan → 怎么样` no longer work via implicit prefix; they require
        /// the user to enable the corresponding fuzzy rule (`an/ang`). That is
        /// the right place for "near miss" semantics — explicit and toggleable —
        /// instead of an always-on hidden behavior. Pure-abbrev shortcuts like
        /// `zmy → 怎么样` and full-pinyin scheme-alternative cases like
        /// `nhao → 你好`, `wsmyao → 为什么要` are unaffected.
        ///
        /// Returns (matched, usedFuzzy).
        private static func tokenMatches(token: SegmentToken,
                                         syllable: String,
                                         fuzzyEnabled: Bool) -> (Bool, Bool) {
                switch token.kind {
                case .abbrev:
                        let needle = token.text
                        if syllable.hasPrefix(needle) { return (true, false) }
                        if !fuzzyEnabled { return (false, false) }
                        for v in FuzzyPinyinExpander.expand(syllable) where v.hasPrefix(needle) {
                                return (true, true)
                        }
                        return (false, false)
                case .full:
                        if syllable == token.origin { return (true, false) }
                        if !fuzzyEnabled { return (false, false) }
                        // Equality under fuzzy: either side's expansion contains the other.
                        // Covers in↔ing, an↔ang, etc., where the user's typed canonical
                        // syllable and the DB-stored canonical syllable are fuzzy peers.
                        for v in FuzzyPinyinExpander.expand(token.origin) where v == syllable {
                                return (true, true)
                        }
                        for v in FuzzyPinyinExpander.expand(syllable) where v == token.origin {
                                return (true, true)
                        }
                        return (false, false)
                }
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

        /// `maxSyllableCount`: cap on `word.count` for returned rows. When nil,
        /// derives it from the input's best segmentation. Callers that probe a
        /// specific scheme should pass `scheme.count` directly so 2-char rows
        /// (e.g. 图案 from `[tu, an]`) aren't filtered out by a best-scheme cap of 1.
        private static func pinyinMatchInternal(text: String, input: String, isFuzzyMatch: Bool = false, maxSyllableCount: Int? = nil) -> [Candidate] {
                let code: Int = text.deterministicHash
                guard let stmt = pingStatement else { return [] }
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(code))
                sqlite3_bind_int64(stmt, 2, 100)

                let cap: Int = maxSyllableCount ?? PinyinSegmentor.maxSyllableCount(for: input)

                var candidates: [Candidate] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(stmt, 0))
                        guard let wordPtr = sqlite3_column_text(stmt, 1) else { continue }
                        guard let pinyinPtr = sqlite3_column_text(stmt, 2) else { continue }
                        let word: String = String(cString: wordPtr)
                        let pinyin: String = String(cString: pinyinPtr)

                        guard word.count <= cap else { continue }

                        let candidate = Candidate(text: word, romanization: pinyin, input: input, mark: input, order: rowID, isFuzzyMatch: isFuzzyMatch)
                        candidates.append(candidate)
                }
                return candidates
        }
}
