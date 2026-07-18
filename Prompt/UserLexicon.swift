import Foundation
import SQLite3
import CoreIME
import os.log

@MainActor
struct UserLexicon: Sendable {

        private static let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "UserLexicon")

        private static let database: OpaquePointer? = {
                var db: OpaquePointer? = nil
                let path: String? = {
                        let fileName: String = "userlexicon.sqlite3"
                        if #available(macOS 13.0, *) {
                                return URL.libraryDirectory.appending(path: fileName, directoryHint: .notDirectory).path()
                        } else {
                                guard let libraryDirectoryUrl: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
                                return libraryDirectoryUrl.appendingPathComponent(fileName, isDirectory: false).path
                        }
                }()
                guard let path else { return nil }
                migrateLegacyLexiconIfNeeded(containerPath: path)
                guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return nil }
                return db
        }()

        /// One-time migration of the pre-sandbox user lexicon.
        ///
        /// Under App Sandbox, `URL.libraryDirectory` redirects to the container
        /// (`~/Library/Containers/…/Data/Library/`), so the old database at the *real*
        /// `~/Library/userlexicon.sqlite3` becomes invisible. On the first sandboxed
        /// launch (container DB absent) we copy the legacy file — plus its `-wal`/`-shm`
        /// sidecars — into the container. Reading the real home is permitted by the
        /// `temporary-exception.files.home-relative-path.read-only` entitlement, and
        /// `NSHomeDirectoryForUser(NSUserName())` returns the real home even inside a
        /// sandbox.
        ///
        /// No-op when not sandboxed (legacy path == container path), when the container
        /// DB already exists, or when there is no legacy file to migrate.
        private static func migrateLegacyLexiconIfNeeded(containerPath: String) {
                let fm = FileManager.default
                guard !fm.fileExists(atPath: containerPath) else { return }
                let realHome: String = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
                let legacyPath: String = (realHome as NSString)
                        .appendingPathComponent("Library/userlexicon.sqlite3")
                guard legacyPath != containerPath, fm.fileExists(atPath: legacyPath) else { return }
                let containerDir = (containerPath as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: containerDir, withIntermediateDirectories: true)
                for suffix in ["", "-wal", "-shm"] {
                        let src = legacyPath + suffix
                        let dst = containerPath + suffix
                        guard fm.fileExists(atPath: src), !fm.fileExists(atPath: dst) else { continue }
                        do {
                                try fm.copyItem(atPath: src, toPath: dst)
                        } catch {
                                logger.error("Legacy lexicon migration failed for \(src, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                }
                logger.info("Migrated legacy user lexicon into sandbox container.")
        }

        static func prepare() {
                let command: String = "CREATE TABLE IF NOT EXISTS userlexicontable(id INTEGER NOT NULL PRIMARY KEY, frequency INTEGER NOT NULL, word TEXT NOT NULL, romanization TEXT NOT NULL, shortcut INTEGER NOT NULL, ping INTEGER NOT NULL);"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }

        // MARK: - Prepared Statements

        private static let pingQueryStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT word, romanization, frequency FROM userlexicontable WHERE ping = ? ORDER BY frequency DESC LIMIT 20;", -1, &stmt, nil)
                return stmt
        }()

        /// Higher LIMIT than legacy (5) so per-token prefix filter still finds the
        /// most-frequent matches after Swift-side narrowing.
        private static let shortcutQueryStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT word, romanization, frequency FROM userlexicontable WHERE shortcut = ? ORDER BY frequency DESC LIMIT 100;", -1, &stmt, nil)
                return stmt
        }()

        private static let findStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT frequency FROM userlexicontable WHERE id = ? LIMIT 1;", -1, &stmt, nil)
                return stmt
        }()


        // MARK: - Handle Candidate

        static func handle(_ candidate: Candidate?) {
                guard let candidate else { return }
                let word: String = candidate.lexiconText
                let romanization: String = candidate.romanization
                // Use the ping form (no spaces/tones) as the stable id key,
                // so re-selections always find the same entry regardless of how
                // mark vs romanization differ (e.g. word-creation stores "mei zhi dao"
                // but subsequent selections compute mark as "meizhidao").
                let pingForm: String = romanization.removedSpacesTones()
                let id: Int = (word + pingForm).deterministicHash

                let ping: Int = romanization.ping
                logger.debug("UserLexicon.handle: word=\(word), romanization=\(romanization), pingForm=\(pingForm), ping=\(ping)")

                // Decay competing candidates (same pinyin, different word) by 10%
                // so that long-term frequency reflects actual usage proportions
                // and new words can gradually overtake stale ones.
                decaySiblings(ping: ping, excludingId: id)

                let boost: Int64 = 1000
                if let frequency = find(by: id) {
                        guard frequency > 0 else {
                                logger.warning("UserLexicon.handle: frequency \(frequency) is abnormal, resetting to 1000")
                                update(id: id, frequency: 1000)
                                return
                        }
                        let newFrequency: Int64 = frequency + boost

                        // When any entry would overflow the threshold, halve ALL entries so
                        // relative order is preserved and there is room to keep growing.
                        let threshold: Int64 = 1_000_000_000
                        if newFrequency > threshold {
                                normalizeFrequencies()
                                let halved = frequency / 2
                                update(id: id, frequency: halved + boost)
                        } else {
                                update(id: id, frequency: newFrequency)
                        }
                        logger.debug("UserLexicon.handle: updated frequency from \(frequency) to \(newFrequency)")
                } else {
                        let entry = LexiconEntry(id: id, frequency: boost, word: word, romanization: romanization, shortcut: romanization.shortcut, ping: ping)
                        logger.debug("UserLexicon.handle: inserting new entry with frequency \(boost)")
                        insert(entry: entry)
                }
        }
        private static func find(by id: Int) -> Int64? {
                logger.debug("UserLexicon.find: id=\(id), findStatement=\(findStatement != nil)")
                guard let stmt = findStatement else {
                        logger.debug("UserLexicon.find: findStatement is nil")
                        return nil
                }
                logger.debug("UserLexicon.find: calling sqlite3_reset")
                sqlite3_reset(stmt)
                logger.debug("UserLexicon.find: calling sqlite3_bind_int64")
                guard sqlite3_bind_int64(stmt, 1, Int64(id)) == SQLITE_OK else {
                        logger.debug("UserLexicon.find: sqlite3_bind_int64 failed")
                        return nil
                }
                logger.debug("UserLexicon.find: calling sqlite3_step")
                let stepResult = sqlite3_step(stmt)
                logger.debug("UserLexicon.find: sqlite3_step returned \(stepResult)")
                guard stepResult == SQLITE_ROW else {
                        logger.debug("UserLexicon.find: no row found")
                        return nil
                }
                logger.debug("UserLexicon.find: calling sqlite3_column_int64")
                let frequency = sqlite3_column_int64(stmt, 0)
                logger.debug("UserLexicon.find: frequency=\(frequency), calling sqlite3_reset")
                sqlite3_reset(stmt)  // Release cursor before any subsequent write
                logger.debug("UserLexicon.find: returning frequency=\(frequency)")
                return frequency
        }
        private static func decaySiblings(ping: Int, excludingId id: Int) {
                let command: String = "UPDATE userlexicontable SET frequency = MAX(frequency * 9 / 10, 1) WHERE ping = ? AND id != ?;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                sqlite3_bind_int64(statement, 1, Int64(ping))
                sqlite3_bind_int64(statement, 2, Int64(id))
                sqlite3_step(statement)
        }
        private static func normalizeFrequencies() {
                let command: String = "UPDATE userlexicontable SET frequency = MAX(frequency / 2, 1);"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                sqlite3_step(statement)
                logger.debug("UserLexicon.normalizeFrequencies: all frequencies halved")
        }
        private static func update(id: Int, frequency: Int64) {
                let command: String = "UPDATE userlexicontable SET frequency = ? WHERE id = ?;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                sqlite3_bind_int64(statement, 1, frequency)
                sqlite3_bind_int64(statement, 2, Int64(id))
                guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }
        private static func insert(entry: LexiconEntry) {
                let command: String = "INSERT INTO userlexicontable (id, frequency, word, romanization, shortcut, ping) VALUES (?, ?, ?, ?, ?, ?);"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                sqlite3_bind_int64(statement, 1, Int64(entry.id))
                sqlite3_bind_int64(statement, 2, entry.frequency)
                sqlite3_bind_text(statement, 3, entry.word, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(statement, 4, entry.romanization, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int64(statement, 5, Int64(entry.shortcut))
                sqlite3_bind_int64(statement, 6, Int64(entry.ping))
                guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }


        // MARK: - Suggestion

        /// Suggest user-lexicon candidates for `text`. Mirrors Engine's hybrid model:
        /// every top-quality scheme is queried (full → ping index, hybrid → shortcut
        /// index + per-token prefix filter), then tail-drop fallback runs to surface
        /// shorter prefix matches.
        static func suggest(text: String, segmentation: Segmentation) -> [Candidate] {
                logger.debug("UserLexicon.suggest: text=\(text), segmentation.count=\(segmentation.count)")

                // Direct ping lookup against the raw input (no spaces). Catches the case
                // where romanization in the DB was stored without spaces between syllables.
                let directPingMatches = pingQuery(pingText: text, input: text, mark: nil, isFuzzy: false)

                guard let bestScheme = segmentation.first else {
                        return dedupByText(directPingMatches)
                }

                let bestQuality = SchemeQuality(scheme: bestScheme)
                // Include all all-full schemes regardless of token count: they only run
                // the ping path (no shortcut prefix-extension), so alternative segmentations
                // like "tuan" → [tu, an] add 图案 as exact matches without prefix noise.
                // Hybrid (with-abbrev) schemes are still gated to bestQuality.
                let topSchemes = segmentation.filter { scheme in
                        if scheme.isAllFull { return true }
                        return SchemeQuality(scheme: scheme) == bestQuality
                }

                var allCandidates: [Candidate] = directPingMatches
                var seenKeys = Set<String>()
                for c in directPingMatches {
                        seenKeys.insert(c.text + c.romanization)
                }

                for scheme in topSchemes {
                        runScheme(scheme,
                                  fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                  seenKeys: &seenKeys,
                                  out: &allCandidates)
                }

                // Tail-drop fallback: drop trailing tokens to surface shorter prefix matches.
                for topScheme in topSchemes {
                        var fallback = topScheme
                        while fallback.count > 1 {
                                fallback = Array(fallback.dropLast())
                                guard fallback.count >= 2 else { break }
                                runScheme(fallback,
                                          fuzzyEnabled: FuzzyPinyinSettings.isAnyEnabled,
                                          seenKeys: &seenKeys,
                                          out: &allCandidates)
                        }
                }

                logger.debug("UserLexicon.suggest: total candidates=\(allCandidates.count)")
                return dedupByText(allCandidates)
        }

        private struct SchemeQuality: Hashable {
                let count: Int
                let abbrevCount: Int
                init(scheme: SegmentScheme) {
                        self.count = scheme.count
                        self.abbrevCount = scheme.abbrevCount
                }
        }

        private static func runScheme(_ scheme: SegmentScheme,
                                      fuzzyEnabled: Bool,
                                      seenKeys: inout Set<String>,
                                      out: inout [Candidate]) {
                let combinedInput = scheme.map(\.text).joined()
                let mark = combinedInput
                // Schemes from typo-corrected input are near-misses; tag every
                // candidate fuzzy so they sort below true exact-typed matches.
                let schemeIsTypoCorrected = scheme.isTypoCorrected

                if scheme.isAllFull {
                        let pingText = scheme.map(\.origin).joined()
                        let matched = pingQuery(pingText: pingText, input: combinedInput, mark: mark, isFuzzy: schemeIsTypoCorrected, maxSyllableCount: scheme.count)
                        appendUnique(matched, into: &out, seen: &seenKeys)

                        if fuzzyEnabled {
                                let expandedArrays = FuzzyPinyinExpander.expandArray(scheme.map(\.origin))
                                for expanded in expandedArrays {
                                        let expandedPing = expanded.joined()
                                        guard expandedPing != pingText else { continue }
                                        let fuzzyMatched = pingQuery(pingText: expandedPing,
                                                                     input: combinedInput,
                                                                     mark: mark,
                                                                     isFuzzy: true,
                                                                     maxSyllableCount: scheme.count)
                                        appendUnique(fuzzyMatched, into: &out, seen: &seenKeys)
                                }
                        }
                        // All-full schemes never fall through to the shortcut+prefix path.
                        // Whether or not ping found rows, prefix-extending the user's full
                        // syllables to longer ones from user lex (e.g. zhe→zheng surfacing
                        // 整块 for input "zhekuai", or xi→xing surfacing 形成 for "xiche")
                        // is noise: when the user types complete pinyin, they want the
                        // exact entry from user lex (which the ping path covers), not a
                        // longer-syllable variant that just happens to share initials.
                        // Engine still surfaces shorter-typing partials like
                        // "zenmeyan"→怎么样 via its own shortcut+prefix fallback against
                        // the system dictionary; user lex doesn't need to duplicate it.
                        return
                }

                // Hybrid path (any scheme containing .abbrev tokens): query by shortcut
                // intercode, filter via per-position prefix match. Prefix matching is
                // the whole point of abbrev tokens, so it stays.
                let shortcutMatched = shortcutSchemeQuery(scheme: scheme,
                                                          input: combinedInput,
                                                          mark: mark,
                                                          fuzzyEnabled: fuzzyEnabled,
                                                          forceFuzzyMatch: schemeIsTypoCorrected)
                appendUnique(shortcutMatched, into: &out, seen: &seenKeys)
        }

        private static func appendUnique(_ candidates: [Candidate],
                                         into out: inout [Candidate],
                                         seen: inout Set<String>) {
                for c in candidates {
                        let key = c.text + c.romanization
                        if seen.insert(key).inserted {
                                out.append(c)
                        }
                }
        }

        /// Final dedup before returning: keep only the first entry per word text. This
        /// prevents the candidate list from showing the same word twice with slightly
        /// different romanizations (e.g. "不是 (bushi)" and "不是 (bu shi)").
        private static func dedupByText(_ candidates: [Candidate]) -> [Candidate] {
                var seen = Set<String>()
                var out: [Candidate] = []
                for c in candidates {
                        if seen.insert(c.text).inserted {
                                out.append(c)
                        }
                }
                return out
        }

        // MARK: - Ping (full pinyin) query

        /// `maxSyllableCount`: cap on `word.count` for returned rows. When nil, derives
        /// from input's best segmentation. Callers probing a specific scheme should pass
        /// `scheme.count` so 2-char rows aren't filtered out by a single-token best cap.
        private static func pingQuery(pingText: String, input: String, mark: String?, isFuzzy: Bool, maxSyllableCount: Int? = nil) -> [Candidate] {
                guard let stmt = pingQueryStatement else { return [] }
                let code: Int = pingText.deterministicHash
                sqlite3_reset(stmt)
                guard sqlite3_bind_int64(stmt, 1, Int64(code)) == SQLITE_OK else { return [] }

                let cap: Int = maxSyllableCount ?? PinyinSegmentor.maxSyllableCount(for: input)
                var candidates: [Candidate] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let wordPtr = sqlite3_column_text(stmt, 0) else { continue }
                        guard let romanizationPtr = sqlite3_column_text(stmt, 1) else { continue }
                        let word: String = String(cString: wordPtr)
                        let romanization: String = String(cString: romanizationPtr)
                        let frequency: Int = Int(sqlite3_column_int64(stmt, 2))

                        guard word.count <= cap else { continue }

                        let resolvedMark = mark ?? romanization.removedTones().removedSpaces()
                        let candidate = Candidate(text: word,
                                                  romanization: romanization,
                                                  input: input,
                                                  mark: resolvedMark,
                                                  order: -frequency,
                                                  isFuzzyMatch: isFuzzy)
                        candidates.append(candidate)
                }
                return candidates
        }

        // MARK: - Shortcut (hybrid) query

        /// Compute shortcut intercode by taking the first character of each token. Mirrors
        /// `String.shortcut` (used at insert time) so lookup hash matches storage hash.
        private static func schemeShortcutCode(_ scheme: SegmentScheme) -> Int? {
                let firstChars: [Character] = scheme.compactMap { $0.text.first }
                guard firstChars.count == scheme.count else { return nil }
                let str = String(firstChars)
                return str.deterministicHash
        }

        private static func shortcutSchemeQuery(scheme: SegmentScheme,
                                                input: String,
                                                mark: String,
                                                fuzzyEnabled: Bool,
                                                forceFuzzyMatch: Bool = false) -> [Candidate] {
                guard let code = schemeShortcutCode(scheme) else { return [] }
                guard let stmt = shortcutQueryStatement else { return [] }
                sqlite3_reset(stmt)
                guard sqlite3_bind_int64(stmt, 1, Int64(code)) == SQLITE_OK else { return [] }

                let schemeSyllableCount = scheme.count
                var candidates: [Candidate] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let wordPtr = sqlite3_column_text(stmt, 0) else { continue }
                        guard let romanizationPtr = sqlite3_column_text(stmt, 1) else { continue }
                        let word: String = String(cString: wordPtr)
                        let romanization: String = String(cString: romanizationPtr)
                        let frequency: Int = Int(sqlite3_column_int64(stmt, 2))

                        guard word.count == schemeSyllableCount else { continue }

                        let parts = romanization.split(separator: " ")
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
                                                  romanization: romanization,
                                                  input: input,
                                                  mark: mark,
                                                  order: -frequency,
                                                  isFuzzyMatch: anyFuzzy)
                        candidates.append(candidate)
                }
                return candidates
        }

        /// See Engine.tokenMatches — same semantics. `.abbrev` uses prefix,
        /// `.full` uses equality (modulo fuzzy). Prefix on `.full` is forbidden:
        /// `"ne"` must not silently extend to `"neng"`.
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
                        for v in FuzzyPinyinExpander.expand(token.origin) where v == syllable {
                                return (true, true)
                        }
                        for v in FuzzyPinyinExpander.expand(syllable) where v == token.origin {
                                return (true, true)
                        }
                        return (false, false)
                }
        }


        // MARK: - Delete & Clear

        /// Delete one lexicon entry
        static func removeItem(candidate: Candidate) {
                let id: Int = (candidate.lexiconText + candidate.romanization.removedSpacesTones()).deterministicHash
                let command: String = "DELETE FROM userlexicontable WHERE id = ?;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                guard sqlite3_bind_int64(statement, 1, Int64(id)) == SQLITE_OK else { return }
                guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }

        /// Clear User Lexicon
        static func deleteAll() {
                let command = "DELETE FROM userlexicontable;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(statement) == SQLITE_DONE else { return }
        }
}

private struct LexiconEntry {

        /// (Candidate.lexiconText + Candidate.romanization).hash
        let id: Int

        let frequency: Int64

        /// Candidate.lexiconText
        let word: String

        /// Romanization (Pinyin for Mandarin)
        let romanization: String

        /// romanization.initials.hash
        let shortcut: Int

        /// romanization.withoutTonesAndSpaces.hash
        let ping: Int
}
