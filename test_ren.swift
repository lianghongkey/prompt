import Foundation

extension String {
    var deterministicHash: Int {
        var hashValue: UInt32 = 0
        for character in self.utf8 {
                hashValue = (hashValue &* 31 &+ UInt32(character)) & 0xFFFFFFFF
        }
        return Int(hashValue) > 0 ? Int(hashValue) : 1
    }
}

// Test ren
let ren = "ren"
print("Testing: \(ren)")
print("  deterministicHash: \(ren.deterministicHash)")

// Test character by character
var hash: UInt32 = 0
for char in "ren".utf8 {
    print("  char: \(char) ('\(Character(UnicodeScalar(char)))')")
    hash = (hash &* 31 &+ UInt32(char)) & 0xFFFFFFFF
    print("  hash after: \(hash)")
}

// Also test with Python-style algorithm
var hashPy: Int = 0
for char in "ren" {
    let ascii = char.asciiValue!
    hashPy = (hashPy &* 31 &+ Int(ascii)) & 0xFFFFFFFF
}
print("  Python style hash: \(hashPy)")
