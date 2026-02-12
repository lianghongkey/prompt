import Foundation

struct Pinyin {
        static func generate() -> [String] {
                guard let url = Bundle.module.url(forResource: "pinyin", withExtension: "txt") else { return [] }
                guard let sourceContent = try? String(contentsOf: url, encoding: .utf8) else { return [] }
                let sourceLines = sourceContent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: .controlCharacters)
                        .components(separatedBy: .newlines)
                        .filter({ !($0.isEmpty) })
                        .uniqued()
                let entries = sourceLines.compactMap { line -> String? in
                        let parts = line.split(separator: "\t").map({ $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .controlCharacters) })
                        // Support both 2-column format (word\tpinyin) and 4-column format (word\tpinyin\tshortcut\tping)
                        guard parts.count >= 2 else { return nil }
                        let word = parts[0]
                        let pinyin = parts[1]

                        // If already has 4 columns with valid shortcut and ping, use them directly
                        if parts.count == 4, let shortcut = Int(parts[2]), let ping = Int(parts[3]) {
                                return "\(word)\t\(pinyin)\t\(shortcut)\t\(ping)"
                        }

                        // Otherwise, calculate shortcut and ping from pinyin
                        let ping = pinyin.deterministicHash
                        let anchors = pinyin.split(separator: " ").compactMap(\.first)
                        let anchorsText = String(anchors)
                        guard let shortcut = anchorsText.charcode else { return nil }
                        return "\(word)\t\(pinyin)\t\(shortcut)\t\(ping)"
                }
                return entries.uniqued()
        }
}
