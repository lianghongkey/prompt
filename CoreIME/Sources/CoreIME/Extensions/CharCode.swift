extension StringProtocol {
        var charcode: Int? {
                guard self.count < 19 else { return nil }
                let codes: [Int] = self.compactMap(\.intercode)
                guard codes.count == self.count else { return nil }
                let code: Int = codes.combined()
                return code
        }
}

extension RandomAccessCollection where Element == Int {
        func combined() -> Int {
                guard self.count < 19 else { return 0 }
                return reduce(0, { $0 * 100 + $1 })
        }
}

extension Character {
        var intercode: Int? {
                guard let ascii = self.asciiValue else { return nil }
                switch ascii {
                case 97...122: // a-z
                        return Int(ascii) - 97 + 20
                default:
                        return nil
                }
        }
}
