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
    let testCases = ["ren", "zhong", "wo", "ni"]

    for test in testCases {
        print("\n=== Testing: \(test) ===")
        let hash = test.deterministicHash
        print("deterministicHash: \(hash)")

        let query = "SELECT rowid, word, pinyin FROM pinyintable WHERE ping = \(hash) LIMIT 5;"
        print("Query: \(query)")

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
                let rowID = Int(sqlite3_column_int64(statement, 0))
                let word = String(cString: sqlite3_column_text(statement, 1))
                let pinyin = String(cString: sqlite3_column_text(statement, 2))
                print("  Result \(count): [\(rowID)] \(word) - \(pinyin)")
            }
            if count == 0 {
                print("  No results found!")
            }
        } else {
            print("  Query failed!")
        }
        sqlite3_finalize(statement)
    }

    sqlite3_close(db)
} else {
    print("Failed to open database")
}
