import Foundation
import SQLite3

// MARK: - Shared Types

public struct SegmentToken: Hashable, Sendable {
        /// Token
        public let text: String
        /// Regular Pinyin Syllable
        public let origin: String
}

public typealias SegmentScheme = Array<SegmentToken>
public typealias Segmentation = Array<SegmentScheme>

extension SegmentScheme {
        /// All token text character count
        public var length: Int {
                var count = 0
                for token in self {
                        count += token.text.count
                }
                return count
        }
}

extension Segmentation {
        /// Longest scheme token text character count
        public var maxSchemeLength: Int {
                return self.first?.length ?? 0
        }
        /// All token count
        public var subelementCount: Int {
                return self.map(\.count).summation
        }
}

// MARK: - PinyinSegmentor

public struct PinyinSegmentor {

        public static func segment(text: String) -> Segmentation {
                switch text.count {
                case 0:
                        return []
                case 1:
                        switch text {
                        case "a", "o", "e":
                                return [[SegmentToken(text: text, origin: text)]]
                        default:
                                return []
                        }
                default:
                        return split(text)
                }
        }

        private static func split(_ text: String) -> Segmentation {
                let leadingTokens: [SegmentToken] = splitLeading(text)
                guard leadingTokens.isNotEmpty else { return [] }
                let textCount = text.count
                var segmentation: Segmentation = leadingTokens.map({ [$0] })
                var previousSubelementCount = segmentation.subelementCount
                var shouldContinue: Bool = true
                while shouldContinue {
                        for scheme in segmentation {
                                let schemeLength = scheme.length
                                guard schemeLength < textCount else { continue }
                                let tailText = String(text.dropFirst(schemeLength))
                                let tailTokens = splitLeading(tailText)
                                guard tailTokens.isNotEmpty else { continue }
                                let newSegmentation: Segmentation = tailTokens.map({ scheme + [$0] })
                                segmentation += newSegmentation
                        }
                        segmentation = segmentation.uniqued()
                        let currentSubelementCount = segmentation.subelementCount
                        if currentSubelementCount != previousSubelementCount {
                                previousSubelementCount = currentSubelementCount
                        } else {
                                shouldContinue = false
                        }
                }
                let sequences: Segmentation = segmentation.sorted(by: {
                        let lhsLength: Int = $0.length
                        let rhsLength: Int = $1.length
                        if lhsLength == rhsLength {
                                return $0.count < $1.count
                        } else {
                                return lhsLength > rhsLength
                        }
                })
                return sequences
        }

        private static func splitLeading(_ text: String) -> [SegmentToken] {
                let maxLength: Int = min(text.count, 6)
                guard maxLength > 0 else { return [] }
                let tokens = (1...maxLength).reversed().compactMap({ match(text.prefix($0)) })
                return tokens
        }

        private static func match<T: StringProtocol>(_ text: T) -> SegmentToken? {
                // 先尝试直接匹配
                if let token = matchDirect(text) {
                        return token
                }

                // 如果启用了模糊音，尝试模糊匹配
                if FuzzyPinyinSettings.isAnyEnabled {
                        return matchWithFuzzy(text)
                }

                return nil
        }

        /// 直接匹配数据库中的音节
        private static func matchDirect<T: StringProtocol>(_ text: T) -> SegmentToken? {
                guard let code: Int = text.charcode else { return nil }
                let command: String = "SELECT syllable FROM pinyinsyllabletable WHERE code = \(code) LIMIT 1;"
                var statement: OpaquePointer? = nil
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(Engine.database, command, -1, &statement, nil) == SQLITE_OK else { return nil }
                guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
                let syllable: String = String(cString: sqlite3_column_text(statement, 0))
                return SegmentToken(text: syllable, origin: syllable)
        }

        /// 使用模糊音匹配
        private static func matchWithFuzzy<T: StringProtocol>(_ text: T) -> SegmentToken? {
                let textString = String(text)

                // 尝试使用模糊音扩展
                let expanded = FuzzyPinyinExpander.expand(textString)

                // 对每个扩展的拼音尝试匹配
                for variant in expanded {
                        if let token = matchDirect(variant) {
                                // 找到匹配：
                                // - text: 使用原始输入（保持正确的字符长度）
                                // - origin: 使用匹配到的标准音节（用于后续数据库查询）
                                return SegmentToken(text: textString, origin: token.origin)
                        }
                }

                return nil
        }
}
