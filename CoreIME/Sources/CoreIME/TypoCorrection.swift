import Foundation

// MARK: - Typo Correction Types

/// 顺序纠错类型 — 类似模糊音，但用于自动修正常见的字母顺序输入错误。
/// 与模糊音的区别：模糊音处理发音变体，本模块只处理键入顺序错误（例如把 "ng" 误打成 "gn"）。
public enum TypoCorrectionType: String, CaseIterable, Identifiable, Sendable {
        // rawValue 保留 "ng-gn" 以兼容已经持久化的用户设置。
        case ng_gn = "ng-gn"
        case na_an = "na-an"
        case ne_en = "ne-en"
        case me_em = "me-em"
        case ie_ei = "ie-ei"

        public var id: String { rawValue }

        public var displayName: String {
                switch self {
                case .ng_gn: return "gn → ng"
                case .na_an: return "na → an"
                case .ne_en: return "ne → en"
                case .me_em: return "em → me"
                case .ie_ei: return "ie → ei"
                }
        }

        public var description: String {
                switch self {
                case .ng_gn: return "顺序纠错 (gn → ng)"
                case .na_an: return "顺序纠错 (na → an)"
                case .ne_en: return "顺序纠错 (ne → en)"
                case .me_em: return "顺序纠错 (em → me)"
                case .ie_ei: return "顺序纠错 (ie → ei)"
                }
        }

        /// 用于音节匹配的子串替换列表 (pattern → replacement)。单向：仅把
        /// pattern 替换成 replacement，不做反向替换。
        fileprivate var substitutions: [(pattern: String, replacement: String)] {
                switch self {
                case .ng_gn: return [("gn", "ng")]
                case .na_an: return [("na", "an")]
                case .ne_en: return [("ne", "en")]
                case .me_em: return [("em", "me")]
                case .ie_ei: return [("ie", "ei")]
                }
        }
}

// MARK: - Settings

/// 顺序纠错配置管理
public struct TypoCorrectionSettings {

        private static let storageKey = "TypoCorrectionEnabledTypes"

        /// 默认启用的类型（默认全部关闭，由用户主动开启）
        public static let defaultEnabledTypes: Set<TypoCorrectionType> = []

        /// 当前启用的类型
        nonisolated(unsafe) private(set) public static var enabledTypes: Set<TypoCorrectionType> = {
                guard let savedData = UserDefaults.standard.data(forKey: storageKey),
                      let savedTypes = try? JSONDecoder().decode([String].self, from: savedData) else {
                        return defaultEnabledTypes
                }
                return Set(savedTypes.compactMap { TypoCorrectionType(rawValue: $0) })
        }()

        /// 缓存的子串替换列表（按启用类型聚合，避免每次匹配都重建）
        nonisolated(unsafe) private static var _cachedSubstitutions: [(pattern: String, replacement: String)] = buildSubstitutions()

        /// 当前启用类型对应的所有子串替换。第一次匹配命中即返回。
        public static var substitutions: [(pattern: String, replacement: String)] { _cachedSubstitutions }

        /// 是否启用了任何类型
        public static var isAnyEnabled: Bool { !enabledTypes.isEmpty }

        public static func isTypeEnabled(_ type: TypoCorrectionType) -> Bool {
                return enabledTypes.contains(type)
        }

        public static func setType(_ type: TypoCorrectionType, enabled: Bool) {
                if enabled {
                        enabledTypes.insert(type)
                } else {
                        enabledTypes.remove(type)
                }
                _cachedSubstitutions = buildSubstitutions()
                save()
                PinyinSegmentor.resetCaches()
        }

        private static func buildSubstitutions() -> [(pattern: String, replacement: String)] {
                var subs: [(pattern: String, replacement: String)] = []
                for type in enabledTypes {
                        subs.append(contentsOf: type.substitutions)
                }
                return subs
        }

        private static func save() {
                let rawValues = Array(enabledTypes.map(\.rawValue))
                if let data = try? JSONEncoder().encode(rawValues) {
                        UserDefaults.standard.set(data, forKey: storageKey)
                }
        }
}

// MARK: - Expander

/// 一条纠错变体：纠错后的文本 + 发生替换的字符位置范围。
/// 由于当前所有规则都是等长替换，这些位置在原始文本和纠错后文本中相同。
public struct TypoCorrectionVariant: Sendable, Hashable {
        public let text: String
        /// 发生替换的字符位置范围列表（在 `text` 字符数组中的索引）。
        public let substitutionRanges: [Range<Int>]
}

public struct TypoCorrectionExpander {

        /// 对整段输入应用每一条启用的规则，产出去重后的纠错变体。
        /// 当前所有规则都是等长替换（如 gn → ng），不会改变字符位置坐标系。
        public static func variants(for text: String) -> [TypoCorrectionVariant] {
                guard TypoCorrectionSettings.isAnyEnabled else { return [] }
                let chars = Array(text)
                var results: [TypoCorrectionVariant] = []
                var seen = Set<String>()

                for (pattern, replacement) in TypoCorrectionSettings.substitutions {
                        let patternChars = Array(pattern)
                        let replacementChars = Array(replacement)
                        // Only length-preserving substitutions are supported here.
                        guard !patternChars.isEmpty, patternChars.count == replacementChars.count else { continue }

                        // Apply every non-overlapping occurrence of `pattern`.
                        var correctedChars = chars
                        var ranges: [Range<Int>] = []
                        var i = 0
                        while i + patternChars.count <= correctedChars.count {
                                var match = true
                                for k in 0 ..< patternChars.count {
                                        if correctedChars[i + k] != patternChars[k] { match = false; break }
                                }
                                if match {
                                        for k in 0 ..< replacementChars.count {
                                                correctedChars[i + k] = replacementChars[k]
                                        }
                                        ranges.append(i ..< (i + patternChars.count))
                                        i += patternChars.count
                                } else {
                                        i += 1
                                }
                        }
                        guard !ranges.isEmpty else { continue }
                        let corrected = String(correctedChars)
                        if corrected == text { continue }
                        if seen.insert(corrected).inserted {
                                results.append(TypoCorrectionVariant(text: corrected, substitutionRanges: ranges))
                        }
                }
                return results
        }
}
