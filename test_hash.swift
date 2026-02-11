import Foundation

extension StringProtocol {
    var charcode: Int? {
        guard self.count < 10 else { return nil }
        let codes: [Int] = self.compactMap { $0.intercode }
        guard codes.count == self.count else { return nil }
        let code: Int = codes.reduce(0) { $0 * 100 + $1 }
        return code
    }

    var deterministicHash: Int {
        var hashValue: UInt32 = 0
        for character in self.utf8 {
                hashValue = (hashValue &* 31 &+ UInt32(character)) & 0xFFFFFFFF
        }
        return Int(hashValue) > 0 ? Int(hashValue) : 1
    }
}

extension Character {
    var intercode: Int? {
        switch self {
        case "a": return 20
        case "b": return 21
        case "c": return 22
        case "d": return 23
        case "e": return 24
        case "f": return 25
        case "g": return 26
        case "h": return 27
        case "i": return 28
        case "j": return 29
        case "k": return 30
        case "l": return 31
        case "m": return 32
        case "n": return 33
        case "o": return 34
        case "p": return 35
        case "q": return 36
        case "r": return 37
        case "s": return 38
        case "t": return 39
        case "u": return 40
        case "v": return 41
        case "w": return 42
        case "x": return 43
        case "y": return 44
        case "z": return 45
        default: return nil
        }
    }
}

// Test zhong
let zhong = "zhong"
print("Testing: \(zhong)")
print("  hash: \(zhong.hash)")
print("  deterministicHash: \(zhong.deterministicHash)")
print("  charcode: \(zhong.charcode ?? 0)")

// Test ren
let ren = "ren"
print("\nTesting: \(ren)")
print("  hash: \(ren.hash)")
print("  deterministicHash: \(ren.deterministicHash)")
print("  charcode: \(ren.charcode ?? 0)")

// Test wo
let wo = "wo"
print("\nTesting: \(wo)")
print("  deterministicHash: \(wo.deterministicHash)")
print("  charcode: \(wo.charcode ?? 0)")

// Test database values
print("\nDatabase values:")
print("  zhong should have ping=115878010, shortcut=45")
print("  wo should have ping=3800, shortcut=42")
