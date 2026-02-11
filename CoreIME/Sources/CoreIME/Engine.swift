import Foundation
import SQLite3
import os.log

extension FileManager {
        func appendFile(_ data: Data, toPath path: String) {
                if FileManager.default.fileExists(atPath: path) {
                        if let handle = FileHandle(forWritingAtPath: path) {
                                defer { handle.closeFile() }
                                handle.write(data)
                        }
                } else {
                        FileManager.default.createFile(atPath: path, contents: data)
                }
        }
}

public struct Engine {

        public static func prepare() {
                let debugLog = "/tmp/typeduck_debug.log"
                if let msg = "Engine.prepare() called\n".data(using: .utf8) {
                        FileManager.default.appendFile(msg, toPath: debugLog)
                }
                let command: String = "SELECT rowid FROM pinyintable WHERE shortcut = 20 LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(statement) == SQLITE_ROW else { return }
                if let msg = "Engine.prepare() succeeded\n".data(using: .utf8) {
                        FileManager.default.appendFile(msg, toPath: debugLog)
                }
        }
        nonisolated(unsafe) static let database: OpaquePointer? = {
                // Force write to a file to verify execution
                let testPath = "/tmp/typeduck_init.txt"
                FileManager.default.createFile(atPath: testPath, contents: "INIT_START\n".data(using: .utf8))

                var db: OpaquePointer? = nil
                guard let path: String = Bundle.module.path(forResource: "imedb", ofType: "sqlite3") else {
                        FileManager.default.createFile(atPath: "/tmp/typeduck_error.txt", contents: "BUNDLE_PATH_FAILED\n".data(using: .utf8))
                        return nil
                }
                FileManager.default.createFile(atPath: testPath, contents: "PATH=\(path)\n".data(using: .utf8))

                var storageDatabase: OpaquePointer? = nil
                defer { sqlite3_close_v2(storageDatabase) }
                guard sqlite3_open_v2(path, &storageDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                        FileManager.default.createFile(atPath: "/tmp/typeduck_error.txt", contents: "STORAGE_OPEN_FAILED\n".data(using: .utf8))
                        return nil
                }

                guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
                        FileManager.default.createFile(atPath: "/tmp/typeduck_error.txt", contents: "MEMORY_OPEN_FAILED\n".data(using: .utf8))
                        return nil
                }

                let backup = sqlite3_backup_init(db, "main", storageDatabase, "main")
                guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else {
                        FileManager.default.createFile(atPath: "/tmp/typeduck_error.txt", contents: "BACKUP_STEP_FAILED\n".data(using: .utf8))
                        return nil
                }

                guard sqlite3_backup_finish(backup) == SQLITE_OK else {
                        FileManager.default.createFile(atPath: "/tmp/typeduck_error.txt", contents: "BACKUP_FINISH_FAILED\n".data(using: .utf8))
                        return nil
                }

                FileManager.default.createFile(atPath: "/tmp/typeduck_success.txt", contents: "SUCCESS\n".data(using: .utf8))
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
                let debugLog = "/tmp/typeduck_debug.log"
                let hash = text.deterministicHash
                if let msg = "Engine.suggest: text='\(text)' count=\(text.count) hash=\(hash)\n".data(using: .utf8) {
                        FileManager.default.appendFile(msg, toPath: debugLog)
                }
                switch text.count {
                case 0:
                        return []
                case 1:
                        // Single character input - try pinyin match and shortcut
                        let pinyinMatches = pinyinMatchInternal(text: text, input: text)
                        return pinyinMatches.isEmpty ? pinyinShortcutInternal(text: text, limit: 100) : pinyinMatches
                default:
                        // Multi-character input - try direct pinyin match first
                        return pinyinSuggestMulti(text: text)
                }
        }

        private static func pinyinSuggestMulti(text: String) -> [Candidate] {
                // Try exact match first (for multi-character pinyin like "wo", "men", "zhong", "guo")
                let exactMatches = pinyinMatchInternal(text: text, input: text)

                // If no exact match, try prefix matches
                if exactMatches.isEmpty {
                        return pinyinShortcutInternal(text: text, limit: 100)
                }

                return exactMatches
        }

        private static func pinyinMatchInternal(text: String, input: String) -> [Candidate] {
                let debugLog = "/tmp/typeduck_debug.log"
                var candidates: [Candidate] = []
                let code: Int = text.deterministicHash
                if let msg = "pinyinMatchInternal: text='\(text)' code=\(code)\n".data(using: .utf8) {
                        FileManager.default.appendFile(msg, toPath: debugLog)
                }
                let command: String = "SELECT rowid, word, pinyin FROM pinyintable WHERE ping = \(code) LIMIT 100;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else {
                        if let msg = "pinyinMatchInternal: SQL prepare failed\n".data(using: .utf8) {
                                FileManager.default.appendFile(msg, toPath: debugLog)
                        }
                        return candidates
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                        let rowID: Int = Int(sqlite3_column_int64(statement, 0))
                        let word: String = String(cString: sqlite3_column_text(statement, 1))
                        let pinyin: String = String(cString: sqlite3_column_text(statement, 2))
                        let candidate = Candidate(text: word, romanization: pinyin, input: input, mark: pinyin, order: rowID)
                        candidates.append(candidate)
                }
                if let msg = "pinyinMatchInternal: found \(candidates.count) results\n".data(using: .utf8) {
                        FileManager.default.appendFile(msg, toPath: debugLog)
                }
                return candidates
        }

        private static func pinyinShortcutInternal(text: String, limit: Int) -> [Candidate] {
                var candidates: [Candidate] = []
                // Use first character's code as shortcut
                guard let firstChar = text.first else { return candidates }
                guard let code: Int = firstChar.intercode else { return candidates }
                let command: String = "SELECT rowid, word, pinyin FROM pinyintable WHERE shortcut = \(code) LIMIT \(limit);"
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
