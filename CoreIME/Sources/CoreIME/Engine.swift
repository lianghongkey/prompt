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

                guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
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
                let hash = text.deterministicHash
                logger.debug("Engine.suggest: text='\(text)' count=\(text.count) hash=\(hash)")
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

                // Try the best segmentation (first one, which is longest with fewest tokens)
                guard let bestScheme = segmentation.first else {
                        // Segmentation failed entirely: fall back to prefix shortcut lookup
                        return pinyinShortcutInternal(text: text, limit: 100)
                }

                // Build spaced pinyin from segmentation
                let spacedPinyin = bestScheme.map(\.origin).joined(separator: " ")

                // Also calculate the combined input text (without spaces) for Candidate
                let combinedInput = bestScheme.map(\.text).joined()

                // Query database with spaced pinyin (original match)
                var allCandidates = pinyinMatchInternal(text: spacedPinyin, input: combinedInput)

                // Apply fuzzy pinyin if enabled
                if FuzzyPinyinSettings.isAnyEnabled {
                        let pinyinArray = bestScheme.map(\.origin)
                        let expandedArrays = FuzzyPinyinExpander.expandArray(pinyinArray)

                        // Query with all fuzzy variants
                        for expandedArray in expandedArrays {
                                let expandedSpacedPinyin = expandedArray.joined(separator: " ")
                                let fuzzyCandidates = pinyinMatchInternal(text: expandedSpacedPinyin, input: combinedInput)
                                allCandidates.append(contentsOf: fuzzyCandidates)
                        }

                        // Remove duplicates (keep first occurrence which has higher priority)
                        var seen = Set<Int>()
                        var uniqueCandidates: [Candidate] = []
                        for candidate in allCandidates {
                                if !seen.contains(candidate.order) {
                                        seen.insert(candidate.order)
                                        uniqueCandidates.append(candidate)
                                }
                        }
                        allCandidates = uniqueCandidates
                }

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
                        // Last resort: shortcut lookup on the first token
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
                var candidates: [Candidate] = []
                let code: Int = text.deterministicHash
                logger.debug("pinyinMatchInternal: text='\(text)' code=\(code)")
                let command: String = "SELECT rowid, word, pinyin FROM pinyintable WHERE ping = \(code) ORDER BY rowid LIMIT 100;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else {
                        logger.error("pinyinMatchInternal: SQL prepare failed")
                        return candidates
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(statement, 0))
                        let word: String = String(cString: sqlite3_column_text(statement, 1))
                        let pinyin: String = String(cString: sqlite3_column_text(statement, 2))
                        // Use input as mark to display user's actual input, not the standard pinyin
                        let candidate = Candidate(text: word, romanization: pinyin, input: input, mark: input, order: rowID)
                        candidates.append(candidate)
                }
                logger.debug("pinyinMatchInternal: found \(candidates.count) results")
                return candidates
        }

        private static func pinyinShortcutInternal(text: String, limit: Int) -> [Candidate] {
                var candidates: [Candidate] = []
                // Use first character's code as shortcut
                guard let firstChar = text.first else { return candidates }
                guard let code: Int = firstChar.intercode else { return candidates }
                let command: String = "SELECT rowid, word, pinyin FROM pinyintable WHERE shortcut = \(code) ORDER BY rowid LIMIT \(limit);"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return candidates }
                while sqlite3_step(statement) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(statement, 0))
                        let word: String = String(cString: sqlite3_column_text(statement, 1))
                        let pinyin: String = String(cString: sqlite3_column_text(statement, 2))
                        // Filter to only show results that match the input prefix
                        guard pinyin.hasPrefix(text) else { continue }
                        let candidate = Candidate(text: word, romanization: pinyin, input: text, mark: text, order: rowID)
                        candidates.append(candidate)
                }
                return candidates
        }
}
