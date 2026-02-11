import Foundation
import SQLite3

extension String {
    var deterministicHash: Int {
        var hashValue: UInt32 = 0
        for character in self.utf8 {
                hashValue = (hashValue &* 31 &+ UInt32(character)) & 0xFFFFFFFF
        }
        return Int(hashValue) > 0 ? Int(hashValue) : 1
    }
}

let dbPath = "/Users/colin/develop/TypeDuck-Mac/CoreIME/Sources/CoreIME/Resources/imedb.sqlite3"
var db: OpaquePointer?

if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
    let tests = ["ren", "wo", "zhong", "ni"]

    for test in tests {
        let hash = test.deterministicHash
        print("\n=== Test: \(test) ===")
        print("Hash: \(hash)")

        let query = "SELECT rowid, word, pinyin FROM pinyintable WHERE ping = \(hash) LIMIT 10;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
                let rowID = sqlite3_column_int64(statement, 0)
                let word = String(cString: sqlite3_column_text(statement, 1))
                let pinyin = String(cString: sqlite3_column_text(statement, 2))
                print("  [\(rowID)] \(word) - \(pinyin)")
            }
            print("  Total: \(count) results")
        }
        sqlite3_finalize(statement)
    }

    sqlite3_close(db)
} else {
    print("Failed to open database")
}
