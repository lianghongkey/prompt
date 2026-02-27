import Foundation
import SQLite3
import os.log

public struct Engine {

        private static let logger = Logger(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Engine")

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
                        // Single character input - try pinyin match and shortcut
                        let pinyinMatches = pinyinMatchInternal(text: text, input: text)
                        return pinyinMatches.isEmpty ? pinyinShortcutInternal(text: text, limit: 100) : pinyinMatches
                default:
                        // Multi-character input - use segmentation to build spaced pinyin
                        return pinyinSuggestMulti(text: text, segmentation: segmentation)
                }
        }

        private static func pinyinSuggestMulti(text: String, segmentation: Segmentation) -> [Candidate] {
                // Use segmentation to build spaced pinyin for database query
                // For example: "ganshenme" -> ["gan", "shen", "me"] -> "gan shen me"

                // Apply fuzzy pinyin correction if enabled and segmentation failed
                if FuzzyPinyinSettings.isAnyEnabled && segmentation.isEmpty {
                        // Try to correct the input using fuzzy pinyin mappings
                        let correctedInputs = generateCorrectedInputs(text)
                        for correctedInput in correctedInputs {
                                let correctedSegmentation = PinyinSegmentor.segment(text: correctedInput)
                                if !correctedSegmentation.isEmpty {
                                        return pinyinSuggestMulti(text: text, segmentation: correctedSegmentation)
                                }
                        }
                }

                guard let bestScheme = segmentation.first else {
                        return pinyinShortcutInternal(text: text, limit: 100)
                }

                // Try all schemes with the same max length (different segmentations may yield different candidates)
                let maxLength = bestScheme.length
                let topSchemes = segmentation.filter({ $0.length == maxLength })

                var allCandidates: [Candidate] = []
                var seen = Set<Int>()

                for scheme in topSchemes {
                        let spacedPinyin = scheme.map(\.origin).joined(separator: " ")
                        let combinedInput = scheme.map(\.text).joined()

                        // Query database with spaced pinyin
                        let directCandidates = pinyinMatchInternal(text: spacedPinyin, input: combinedInput)
                        for candidate in directCandidates {
                                if seen.insert(candidate.order).inserted {
                                        allCandidates.append(candidate)
                                }
                        }

                        // Apply fuzzy pinyin if enabled
                        if FuzzyPinyinSettings.isAnyEnabled {
                                let pinyinArray = scheme.map(\.origin)
                                let expandedArrays = FuzzyPinyinExpander.expandArray(pinyinArray)
                                for expandedArray in expandedArrays {
                                        let expandedSpacedPinyin = expandedArray.joined(separator: " ")
                                        let fuzzyCandidates = pinyinMatchInternal(text: expandedSpacedPinyin, input: combinedInput)
                                        for candidate in fuzzyCandidates {
                                                if seen.insert(candidate.order).inserted {
                                                        allCandidates.append(candidate)
                                                }
                                        }
                                }
                        }
                }

                // Sort all candidates by rowid (lower = more common) so fuzzy matches
                // with high frequency rank properly alongside direct matches
                allCandidates.sort(by: { $0.order < $1.order })

                // If no exact match, fall back progressively by dropping the last token
                if allCandidates.isEmpty {
                        var scheme = bestScheme
                        while scheme.count > 1 {
                                scheme = Array(scheme.dropLast())
                                let fallbackPinyin = scheme.map(\.origin).joined(separator: " ")
                                let fallbackInput = scheme.map(\.text).joined()
                                let fallbackCandidates = pinyinMatchInternal(text: fallbackPinyin, input: fallbackInput)
                                if fallbackCandidates.isNotEmpty {
                                        return fallbackCandidates
                                }
                        }
                        let standardPinyin = bestScheme.map(\.origin).joined()
                        return pinyinShortcutInternal(text: standardPinyin, limit: 100)
                }

                return allCandidates
        }

        /// Generate corrected inputs by applying fuzzy pinyin mappings (both directions)
        /// For example: "don" -> ["dong"] when on/ong is enabled
        private static func generateCorrectedInputs(_ text: String) -> Set<String> {
                var results = Set<String>()
                let mappings = FuzzyPinyinSettings.allMappings

                // Generate all possible corrections
                for mapping in mappings {
                        // Handle initial mappings (bidirectional: z <-> zh)
                        for (initial, alternatives) in mapping.initials {
                                for alternative in alternatives {
                                        // Replace initial with alternative
                                        if text.contains(initial) {
                                                let corrected = text.replacingOccurrences(of: initial, with: alternative)
                                                results.insert(corrected)
                                        }
                                        // Replace alternative with initial
                                        if text.contains(alternative) {
                                                let corrected = text.replacingOccurrences(of: alternative, with: initial)
                                                results.insert(corrected)
                                        }
                                }
                        }

                        // Handle final mappings (bidirectional: on <-> ong)
                        for (final, alternatives) in mapping.finals {
                                for alternative in alternatives {
                                        // Replace final with alternative
                                        if text.contains(final) {
                                                let corrected = text.replacingOccurrences(of: final, with: alternative)
                                                results.insert(corrected)
                                        }
                                        // Replace alternative with final
                                        if text.contains(alternative) {
                                                let corrected = text.replacingOccurrences(of: alternative, with: final)
                                                results.insert(corrected)
                                        }
                                }
                        }
                }

                // Remove the original input
                results.remove(text)
                return results
        }

        private static func pinyinMatchInternal(text: String, input: String) -> [Candidate] {
                let code: Int = text.deterministicHash
                return queryPinyinTable(whereClause: "ping = \(code)", input: input)
        }

        private static func pinyinShortcutInternal(text: String, limit: Int) -> [Candidate] {
                guard let firstChar = text.first else { return [] }
                guard let code: Int = firstChar.intercode else { return [] }
                return queryPinyinTable(whereClause: "shortcut = \(code)", input: text, limit: limit, filter: { $0.hasPrefix(text) })
        }

        private static func queryPinyinTable(whereClause: String, input: String, limit: Int = 100, filter: ((String) -> Bool)? = nil) -> [Candidate] {
                var candidates: [Candidate] = []
                let command: String = "SELECT rowid, word, pinyin FROM pinyintable WHERE \(whereClause) ORDER BY rowid LIMIT \(limit);"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return candidates }
                while sqlite3_step(statement) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(statement, 0))
                        guard let wordPtr = sqlite3_column_text(statement, 1) else { continue }
                        guard let pinyinPtr = sqlite3_column_text(statement, 2) else { continue }
                        let word: String = String(cString: wordPtr)
                        let pinyin: String = String(cString: pinyinPtr)
                        if let filter = filter, !filter(pinyin) { continue }
                        let candidate = Candidate(text: word, romanization: pinyin, input: input, mark: input, order: rowID)
                        candidates.append(candidate)
                }
                return candidates
        }
}
