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
                guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return nil }
                return db
        }()

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
                sqlite3_prepare_v2(database, "SELECT word, romanization FROM userlexicontable WHERE ping = ? ORDER BY frequency DESC LIMIT 5;", -1, &stmt, nil)
                return stmt
        }()

        private static let shortcutQueryStatement: OpaquePointer? = {
                var stmt: OpaquePointer? = nil
                sqlite3_prepare_v2(database, "SELECT word, romanization FROM userlexicontable WHERE shortcut = ? ORDER BY frequency DESC LIMIT 5;", -1, &stmt, nil)
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

                logger.debug("UserLexicon.handle: word=\(word), romanization=\(romanization), pingForm=\(pingForm)")

                if let frequency = find(by: id) {
                        guard frequency > 0 else {
                                logger.warning("UserLexicon.handle: frequency \(frequency) is abnormal, resetting to 1000")
                                update(id: id, frequency: 1000)
                                return
                        }
                        // Additive boost: each selection adds a fixed amount.
                        // This avoids the exponential doubling problem where a popular word
                        // repeatedly triggers normalization, halving all other entries.
                        let boost: Int64 = 1000
                        let newFrequency: Int64 = frequency + boost

                        // When any entry would overflow the threshold, halve ALL entries so
                        // relative order is preserved and there is room to keep growing.
                        let threshold: Int64 = 1_000_000_000
                        if newFrequency > threshold {
                                normalizeFrequencies()
                                // Entry was already halved by normalizeFrequencies.
                                // Give it the boost on top of its halved value.
                                let halved = frequency / 2
                                update(id: id, frequency: halved + boost)
                        } else {
                                update(id: id, frequency: newFrequency)
                        }
                        logger.debug("UserLexicon.handle: updated frequency from \(frequency) to \(newFrequency)")
                } else {
                        // Start with a high initial frequency (1000) so first selection already has good priority
                        let entry = LexiconEntry(id: id, frequency: 1000, word: word, romanization: romanization, shortcut: romanization.shortcut, ping: romanization.ping)
                        logger.debug("UserLexicon.handle: inserting new entry with frequency 1000")
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

        static func suggest(text: String, segmentation: Segmentation) -> [Candidate] {
                logger.debug("UserLexicon.suggest: text=\(text), segmentation.count=\(segmentation.count)")

                let matches = query(text: text, input: text, isShortcut: false, isFuzzyMatch: false)
                logger.debug("UserLexicon.suggest: direct matches=\(matches.count)")

                let shortcuts = query(text: text, input: text, mark: text.spaceSeparated(), isShortcut: true, isFuzzyMatch: false)
                logger.debug("UserLexicon.suggest: shortcuts=\(shortcuts.count)")

                let searches: [Candidate] = {
                        let textCount = text.count
                        let schemes = segmentation.filter({ $0.length == textCount })
                        guard schemes.isNotEmpty else { return [] }

                        var allCandidates: [Candidate] = []
                        var seen = Set<String>() // Track word+romanization to avoid duplicates

                        for scheme in schemes {
                                let pingText = scheme.map(\.origin).joined()
                                logger.debug("UserLexicon.suggest: scheme origins=\(scheme.map(\.origin)), pingText=\(pingText), pingHash=\(pingText.deterministicHash)")

                                let matched = query(text: pingText, input: text, isShortcut: false, isFuzzyMatch: false)
                                logger.debug("UserLexicon.suggest: matched \(matched.count) candidates for pingText=\(pingText)")

                                let text2mark = scheme.map(\.text).joined()
                                let syllables = scheme.map(\.origin).joined()

                                for candidate in matched {
                                        logger.debug("UserLexicon.suggest: checking candidate '\(candidate.text)', mark=\(candidate.mark), syllables=\(syllables), match=\(candidate.mark == syllables)")
                                        if candidate.mark == syllables {
                                                let key = candidate.text + candidate.romanization
                                                if seen.insert(key).inserted {
                                                        allCandidates.append(Candidate(text: candidate.text, romanization: candidate.romanization, input: candidate.input, mark: text2mark, order: -1, isFuzzyMatch: false))
                                                }
                                        }
                                }

                                // Also try fuzzy pinyin matching if enabled
                                if FuzzyPinyinSettings.isAnyEnabled {
                                        let expandedArrays = FuzzyPinyinExpander.expandArray(scheme.map(\.origin))
                                        logger.debug("UserLexicon.suggest: fuzzy expanded to \(expandedArrays.count) variants")
                                        for expandedArray in expandedArrays {
                                                let expandedPingText = expandedArray.joined()
                                                let isFuzzy = expandedPingText != pingText
                                                let fuzzyMatched = query(text: expandedPingText, input: text, isShortcut: false, isFuzzyMatch: isFuzzy)
                                                logger.debug("UserLexicon.suggest: fuzzy matched \(fuzzyMatched.count) for \(expandedPingText)")
                                                for candidate in fuzzyMatched {
                                                        let key = candidate.text + candidate.romanization
                                                        if seen.insert(key).inserted {
                                                                allCandidates.append(Candidate(text: candidate.text, romanization: candidate.romanization, input: candidate.input, mark: text2mark, order: -1, isFuzzyMatch: isFuzzy))
                                                        }
                                                }
                                        }
                                }
                        }

                        // Also try shorter prefix schemes from user lexicon (drop trailing syllables)
                        if let bestScheme = schemes.first, bestScheme.count > 2 {
                                var queriedPings = Set<Int>()
                                for scheme in schemes {
                                        queriedPings.insert(scheme.map(\.origin).joined().deterministicHash)
                                }
                                var fallbackScheme = bestScheme
                                while fallbackScheme.count > 1 {
                                        fallbackScheme = Array(fallbackScheme.dropLast())
                                        guard fallbackScheme.count >= 2 else { break }
                                        let pingText = fallbackScheme.map(\.origin).joined()
                                        let fallbackInput = fallbackScheme.map(\.text).joined()
                                        let text2mark = fallbackInput
                                        let syllables = pingText

                                        let pingHash = pingText.deterministicHash
                                        if queriedPings.insert(pingHash).inserted {
                                                let matched = query(text: pingText, input: fallbackInput, isShortcut: false, isFuzzyMatch: false)
                                                for candidate in matched {
                                                        if candidate.mark == syllables {
                                                                let key = candidate.text + candidate.romanization
                                                                if seen.insert(key).inserted {
                                                                        allCandidates.append(Candidate(text: candidate.text, romanization: candidate.romanization, input: fallbackInput, mark: text2mark, order: -1, isFuzzyMatch: false))
                                                                }
                                                        }
                                                }
                                        }

                                        if FuzzyPinyinSettings.isAnyEnabled {
                                                let expandedArrays = FuzzyPinyinExpander.expandArray(fallbackScheme.map(\.origin))
                                                for expandedArray in expandedArrays {
                                                        let expandedPingText = expandedArray.joined()
                                                        let expandedHash = expandedPingText.deterministicHash
                                                        guard queriedPings.insert(expandedHash).inserted else { continue }
                                                        let isFuzzy = expandedPingText != pingText
                                                        let fuzzyMatched = query(text: expandedPingText, input: fallbackInput, isShortcut: false, isFuzzyMatch: isFuzzy)
                                                        for candidate in fuzzyMatched {
                                                                let key = candidate.text + candidate.romanization
                                                                if seen.insert(key).inserted {
                                                                        allCandidates.append(Candidate(text: candidate.text, romanization: candidate.romanization, input: fallbackInput, mark: text2mark, order: -1, isFuzzyMatch: isFuzzy))
                                                                }
                                                        }
                                                }
                                        }
                                }
                        }

                        return allCandidates
                }()

                logger.debug("UserLexicon.suggest: total searches=\(searches.count)")

                // Deduplicate across matches, shortcuts, and searches
                // For user lexicon, deduplicate by text only (ignore romanization variations)
                // This prevents showing multiple entries like "不是 (bushi)", "不是 (bu shi)", "不是 (busi)"
                var seen = Set<String>()
                var allResults: [Candidate] = []
                for candidate in matches + shortcuts + searches {
                        let key = candidate.text  // Only use text for deduplication
                        if seen.insert(key).inserted {
                                allResults.append(candidate)
                        }
                }

                logger.debug("UserLexicon.suggest: returning \(allResults.count) candidates (before: \(matches.count + shortcuts.count + searches.count))")

                return allResults
        }

        private static func query(text: String, input: String, mark: String? = nil, isShortcut: Bool, isFuzzyMatch: Bool = false) -> [Candidate] {
                var candidates: [Candidate] = []
                let code: Int = isShortcut ? text.replacingOccurrences(of: "y", with: "j").deterministicHash : text.deterministicHash
                guard let stmt = isShortcut ? shortcutQueryStatement : pingQueryStatement else { return candidates }
                sqlite3_reset(stmt)
                guard sqlite3_bind_int64(stmt, 1, Int64(code)) == SQLITE_OK else { return candidates }

                // Calculate max syllable count from input
                let maxSyllableCount = PinyinSegmentor.maxSyllableCount(for: input)

                while sqlite3_step(stmt) == SQLITE_ROW {
                        guard let wordPtr = sqlite3_column_text(stmt, 0) else { continue }
                        guard let romanizationPtr = sqlite3_column_text(stmt, 1) else { continue }
                        let word: String = String(cString: wordPtr)
                        let romanization: String = String(cString: romanizationPtr)

                        // Filter: word character count must not exceed syllable count
                        guard word.count <= maxSyllableCount else { continue }

                        let mark: String = mark ?? romanization.removedTones().removedSpaces()
                        let candidate: Candidate = Candidate(text: word, romanization: romanization, input: input, mark: mark, order: -1, isFuzzyMatch: isFuzzyMatch)
                        candidates.append(candidate)
                }
                return candidates
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
