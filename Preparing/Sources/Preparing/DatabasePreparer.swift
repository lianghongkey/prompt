import Foundation
import SQLite3

struct DatabasePreparer {

        nonisolated(unsafe) private static let database: OpaquePointer? = {
                var db: OpaquePointer? = nil
                guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return nil }
                return db
        }()

        static func prepare() {
                // guard sqlite3_open_v2(":memory:", &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return }
                createT2STable()
                createPinyinTable()
                createSymbolTable()
                createEmojiSkinMappingTable()
                // Note: Removed createSyllableTable() - no longer needed for Mandarin-only input
                createPinyinSyllableTable()
                createOtherIndies()
                backupInMemoryDatabase()
        }

        private static func backupInMemoryDatabase() {
                let path = "../CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"
                if FileManager.default.fileExists(atPath: path) {
                        try? FileManager.default.removeItem(atPath: path)
                }
                var destination: OpaquePointer? = nil
                defer { sqlite3_close_v2(destination) }
                guard sqlite3_open_v2(path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return }
                let backup = sqlite3_backup_init(destination, "main", database, "main")
                guard sqlite3_backup_step(backup, -1) == SQLITE_DONE else { return }
                guard sqlite3_backup_finish(backup) == SQLITE_OK else { return }
        }

        private static func createT2STable() {
                let createTable: String = "CREATE TABLE t2stable(traditional INTEGER NOT NULL PRIMARY KEY, simplified TEXT NOT NULL);"
                var createStatement: OpaquePointer? = nil
                guard sqlite3_prepare_v2(database, createTable, -1, &createStatement, nil) == SQLITE_OK else { sqlite3_finalize(createStatement); return }
                guard sqlite3_step(createStatement) == SQLITE_DONE else { sqlite3_finalize(createStatement); return }
                sqlite3_finalize(createStatement)

                let insert: String = "INSERT INTO t2stable (traditional, simplified) VALUES (?, ?);"
                var insertStatement: OpaquePointer? = nil
                defer { sqlite3_finalize(insertStatement) }
                guard sqlite3_prepare_v2(database, insert, -1, &insertStatement, nil) == SQLITE_OK else { return }

                let entries = Hant2Hans.generate()
                for entry in entries {
                        sqlite3_reset(insertStatement)
                        sqlite3_bind_int(insertStatement, 1, Int32(entry.traditional))
                        sqlite3_bind_text(insertStatement, 2, entry.simplified, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        guard sqlite3_step(insertStatement) == SQLITE_DONE else { continue }
                }
        }

        private static func createPinyinTable() {
                let createTable: String = "CREATE TABLE pinyintable(word TEXT NOT NULL, pinyin TEXT NOT NULL, shortcut INTEGER NOT NULL, ping INTEGER NOT NULL);"
                var createStatement: OpaquePointer? = nil
                guard sqlite3_prepare_v2(database, createTable, -1, &createStatement, nil) == SQLITE_OK else { sqlite3_finalize(createStatement); return }
                guard sqlite3_step(createStatement) == SQLITE_DONE else { sqlite3_finalize(createStatement); return }
                sqlite3_finalize(createStatement)
                // Read directly from pinyin.txt to avoid Pinyin.generate() processing issues
                guard let url = Bundle.module.url(forResource: "pinyin", withExtension: "txt") else { return }
                guard let sourceContent = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sourceLines = sourceContent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: .controlCharacters)
                        .components(separatedBy: .newlines)
                        .filter({ !($0.isEmpty) })

                print("Processing \(sourceLines.count) lines from pinyin.txt")

                // Use transaction for better performance
                sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)

                let insert: String = "INSERT INTO pinyintable (word, pinyin, shortcut, ping) VALUES (?, ?, ?, ?);"
                var insertStatement: OpaquePointer? = nil
                defer { sqlite3_finalize(insertStatement) }
                guard sqlite3_prepare_v2(database, insert, -1, &insertStatement, nil) == SQLITE_OK else {
                        sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                        return
                }

                var insertedCount = 0
                for line in sourceLines {
                        let parts = line.split(separator: "\t").map({ String($0).trimmingCharacters(in: .whitespaces) })
                        guard parts.count == 4 else { continue }
                        let word = parts[0]
                        let pinyin = parts[1]
                        guard let shortcut = Int(parts[2]), let ping = Int(parts[3]) else { continue }

                        sqlite3_reset(insertStatement)
                        sqlite3_bind_text(insertStatement, 1, word, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        sqlite3_bind_text(insertStatement, 2, pinyin, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        sqlite3_bind_int64(insertStatement, 3, Int64(shortcut))
                        sqlite3_bind_int64(insertStatement, 4, Int64(ping))

                        guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                                print("Failed to insert line: \(line)")
                                continue
                        }

                        insertedCount += 1
                        if insertedCount % 100000 == 0 {
                                print("Inserted \(insertedCount) records...")
                        }
                }

                sqlite3_exec(database, "COMMIT", nil, nil, nil)
                print("Total inserted: \(insertedCount) records")
        }

        private static func createSymbolTable() {
                let createTable: String = "CREATE TABLE symboltable(category INTEGER NOT NULL PRIMARY KEY, codepoint TEXT NOT NULL, romanization TEXT NOT NULL, shortcut INTEGER NOT NULL, ping INTEGER NOT NULL);"
                var createStatement: OpaquePointer? = nil
                guard sqlite3_prepare_v2(database, createTable, -1, &createStatement, nil) == SQLITE_OK else { sqlite3_finalize(createStatement); return }
                guard sqlite3_step(createStatement) == SQLITE_DONE else { sqlite3_finalize(createStatement); return }
                sqlite3_finalize(createStatement)
                guard let url = Bundle.module.url(forResource: "symbol", withExtension: "txt") else { return }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sourceLines: [String] = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                let entries = sourceLines.compactMap { sourceLine -> String? in
                        let parts = sourceLine.split(separator: "\t")
                        guard parts.count == 4 else { return nil }
                        let category = parts[0]
                        let codepoint = parts[1]
                        let romanization = parts[2]
                        let anchors = romanization.split(separator: " ").compactMap(\.first)
                        let shortcut = String(anchors).charcode ?? 47
                        let ping = romanization.filter(\.isLetter).hash
                        return "(\(category), '\(codepoint)', '\(romanization)', \(shortcut), \(ping))"
                }
                let values: String = entries.compactMap({ $0 }).joined(separator: ", ")
                let insert: String = "INSERT INTO symboltable (category, codepoint, romanization, shortcut, ping) VALUES \(values);"
                var insertStatement: OpaquePointer? = nil
                defer { sqlite3_finalize(insertStatement) }
                guard sqlite3_prepare_v2(database, insert, -1, &insertStatement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(insertStatement) == SQLITE_DONE else { return }
        }

        private static func createEmojiSkinMappingTable() {
                let createTable: String = "CREATE TABLE emojiskinmapping(source TEXT NOT NULL, target TEXT NOT NULL);"
                var createStatement: OpaquePointer? = nil
                guard sqlite3_prepare_v2(database, createTable, -1, &createStatement, nil) == SQLITE_OK else { sqlite3_finalize(createStatement); return }
                guard sqlite3_step(createStatement) == SQLITE_DONE else { sqlite3_finalize(createStatement); return }
                sqlite3_finalize(createStatement)
                guard let url = Bundle.module.url(forResource: "skin-tone-mapping", withExtension: "txt") else { return }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sourceLines: [String] = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                let entries = sourceLines.compactMap { line -> String? in
                        let parts = line.split(separator: "\t")
                        guard parts.count == 2 else { return nil }
                        let source = parts[0]
                        let target = parts[1]
                        return "('\(source)', '\(target)')"
                }
                let values: String = entries.compactMap({ $0 }).joined(separator: ", ")
                let insert: String = "INSERT INTO emojiskinmapping (source, target) VALUES \(values);"
                var insertStatement: OpaquePointer? = nil
                defer { sqlite3_finalize(insertStatement) }
                guard sqlite3_prepare_v2(database, insert, -1, &insertStatement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(insertStatement) == SQLITE_DONE else { return }
        }

        // Note: createSyllableTable() removed - Cantonese support no longer needed

        private static func createPinyinSyllableTable() {
                let createTable: String = "CREATE TABLE pinyinsyllabletable(code INTEGER NOT NULL PRIMARY KEY, syllable TEXT NOT NULL);"
                var createStatement: OpaquePointer? = nil
                guard sqlite3_prepare_v2(database, createTable, -1, &createStatement, nil) == SQLITE_OK else { sqlite3_finalize(createStatement); return }
                guard sqlite3_step(createStatement) == SQLITE_DONE else { sqlite3_finalize(createStatement); return }
                sqlite3_finalize(createStatement)
                guard let url = Bundle.module.url(forResource: "pinyin-syllable", withExtension: "txt") else { return }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sourceLines: [String] = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                let entries = sourceLines.compactMap { syllable -> String? in
                        let trimmed = syllable.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .controlCharacters)
                        guard !trimmed.isEmpty else { return nil }
                        guard let code = trimmed.charcode else { return nil }
                        return "(\(code), '\(trimmed)')"
                }
                let values: String = entries.compactMap({ $0 }).joined(separator: ", ")
                let insertValues: String = "INSERT INTO pinyinsyllabletable (code, syllable) VALUES \(values);"
                var insertStatement: OpaquePointer? = nil
                defer { sqlite3_finalize(insertStatement) }
                guard sqlite3_prepare_v2(database, insertValues, -1, &insertStatement, nil) == SQLITE_OK else { return }
                guard sqlite3_step(insertStatement) == SQLITE_DONE else { return }
        }

        private static func createOtherIndies() {
                let commands: [String] = [
                        "CREATE INDEX pinyinshortcutindex ON pinyintable(shortcut);",
                        "CREATE INDEX pinyinpingindex ON pinyintable(ping);",
                        "CREATE INDEX symbolshortcutindex ON symboltable(shortcut);",
                        "CREATE INDEX symbolpingindex ON symboltable(ping);",
                        "CREATE INDEX syllabletenkeyindex ON syllabletable(tenkey);"
                ]
                for command in commands {
                        var statement: OpaquePointer? = nil
                        defer { sqlite3_finalize(statement) }
                        guard sqlite3_prepare_v2(database, command, -1, &statement, nil) == SQLITE_OK else { return }
                        guard sqlite3_step(statement) == SQLITE_DONE else { return }
                }
        }
}
