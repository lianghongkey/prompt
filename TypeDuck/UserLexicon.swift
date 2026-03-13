import Foundation
import SQLite3
import CoreIME
import os.log

@MainActor
struct UserLexicon: Sendable {

        private static let logger = Logger(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "UserLexicon")

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


        // MARK: - Handle Candidate

        static func handle(_ candidate: Candidate?) {
                guard let candidate else { return }
                let word: String = candidate.lexiconText
                // Use mark (user's actual input) instead of romanization (standard pinyin)
                // This ensures we can match the same input next time
                let userInput: String = candidate.mark.replacingOccurrences(of: " ", with: "")
                let romanization: String = userInput.isEmpty ? candidate.romanization : userInput
                let id: Int = (word + romanization).deterministicHash

                let pingValue = romanization.removedSpacesTones()
                let pingHash = pingValue.deterministicHash

                logger.debug("UserLexicon.handle: word=\(word), mark=\(candidate.mark), romanization=\(candidate.romanization), using=\(romanization), pingHash=\(pingHash)")

                if let frequency = find(by: id) {
                        // Aggressive frequency boost: double the frequency each time, with a minimum increment of 1000
                        // This ensures that after 2 selections, the word will have very high priority
                        let newFrequency = max(frequency * 2, frequency + 1000)
                        logger.debug("UserLexicon.handle: updating frequency from \(frequency) to \(newFrequency)")
                        update(id: id, frequency: newFrequency)
                } else {
                        // Start with a high initial frequency (1000) so first selection already has good priority
                        let entry = LexiconEntry(id: id, frequency: 1000, word: word, romanization: romanization, shortcut: romanization.shortcut, ping: romanization.ping)
                        logger.debug("UserLexicon.handle: inserting new entry with frequency 1000")
                        insert(entry: entry)
                }
        }
        private static func find(by id: Int) -> Int64? {
                let command: String = "SELECT frequency FROM userlexicontable WHERE id = ? LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return nil }
                guard sqlite3_bind_int64(statement, 1, Int64(id)) == SQLITE_OK else { return nil }
                guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
                let frequency: Int64 = sqlite3_column_int64(statement, 0)
                return frequency
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

                        return allCandidates
                }()

                logger.debug("UserLexicon.suggest: total searches=\(searches.count)")
                logger.debug("UserLexicon.suggest: returning \(matches.count + shortcuts.count + searches.count) candidates")

                return matches + shortcuts + searches
        }

        private static func query(text: String, input: String, mark: String? = nil, isShortcut: Bool, isFuzzyMatch: Bool = false) -> [Candidate] {
                var candidates: [Candidate] = []
                let code: Int = isShortcut ? text.replacingOccurrences(of: "y", with: "j").deterministicHash : text.deterministicHash
                let column: String = isShortcut ? "shortcut" : "ping"
                let command: String = "SELECT word, romanization FROM userlexicontable WHERE \(column) = ? ORDER BY frequency DESC LIMIT 5;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return candidates }
                guard sqlite3_bind_int64(statement, 1, Int64(code)) == SQLITE_OK else { return candidates }
                while sqlite3_step(statement) == SQLITE_ROW {
                        guard let wordPtr = sqlite3_column_text(statement, 0) else { continue }
                        guard let romanizationPtr = sqlite3_column_text(statement, 1) else { continue }
                        let word: String = String(cString: wordPtr)
                        let romanization: String = String(cString: romanizationPtr)
                        let mark: String = mark ?? romanization.removedTones().removedSpaces()
                        let candidate: Candidate = Candidate(text: word, romanization: romanization, input: input, mark: mark, order: -1, isFuzzyMatch: isFuzzyMatch)
                        candidates.append(candidate)
                }
                return candidates
        }


        // MARK: - Delete & Clear

        /// Delete one lexicon entry
        static func removeItem(candidate: Candidate) {
                let id: Int = (candidate.lexiconText + candidate.romanization).deterministicHash
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
