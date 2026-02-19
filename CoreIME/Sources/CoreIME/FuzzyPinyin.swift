import Foundation

// MARK: - Pinyin Components

/// 拼音声母列表（按长度降序排列，确保匹配时优先匹配长的）
/// 包括：所有标准声母 + 零声母标记
public let PinyinInitials: [String] = [
        "zh", "ch", "sh",  // 翘舌音
        "b", "p", "m", "f",
        "d", "t", "n", "l",
        "g", "k", "h",
        "j", "q", "x",
        "z", "c", "s",
        "r", "w", "y"
]

/// 拼音韵母列表（按长度降序排列，确保匹配时优先匹配长的）
public let PinyinFinals: [String] = [
        "uang", "iang", "iong", "ong",  // 三字母韵母
        "ang", "eng", "ing", "ian", "uan", "uai", "uei", "iao",
        "a", "o", "e", "i", "u", "v", "ai", "ei", "ao", "ou",
        "an", "en", "in", "ia", "ie", "ua", "uo", "ue", "ui", "iu",
        "ion", "on"  // 用于 on-ong 模糊音支持（ion 是 iong 的变体，on 是 ong 的变体）
]

/// 拼音分割结果
public struct PinyinComponents {
        public let initial: String      // 声母（可能为空）
        public let final: String        // 韵母
        public let isValid: Bool        // 是否是有效的拼音结构
}

/// 将拼音分割为声母和韵母
/// - Parameter pinyin: 拼音字符串
/// - Returns: PinyinComponents 包含声母、韵母和有效性标志
public func splitPinyin(_ pinyin: String) -> PinyinComponents {
        guard !pinyin.isEmpty else {
                return PinyinComponents(initial: "", final: "", isValid: false)
        }

        // 尝试匹配声母（优先匹配长的声母如 zh, ch, sh）
        var matchedInitial = ""
        var remaining = pinyin

        for initial in PinyinInitials {
                if pinyin.hasPrefix(initial) {
                        matchedInitial = initial
                        remaining = String(pinyin.dropFirst(initial.count))
                        break
                }
        }

        // 剩余部分作为韵母
        let final = remaining

        // 验证：如果剩余部分为空或不是有效的韵母模式，则整个拼音无效
        // 韵母至少应该包含一个元音字母
        let hasVowel = final.contains { "aeiovuy".contains($0) }
        let isValid = !final.isEmpty && hasVowel

        return PinyinComponents(initial: matchedInitial, final: final, isValid: isValid)
}

// MARK: - Fuzzy Pinyin Types
public enum FuzzyPinyinType: String, CaseIterable, Identifiable, Sendable {
        case zh_z = "zh-z"
        case ch_c = "ch-c"
        case sh_s = "sh-s"
        case n_l = "n-l"
        case f_h = "f-h"
        case l_r = "l-r"
        case en_eng = "en-eng"
        case in_ing = "in-ing"
        case on_ong = "on-ong"
        case an_ang = "an-ang"
        case ian_iang = "ian-iang"
        case uan_uang = "uan-uang"

        public var id: String { rawValue }

        /// 显示名称
        public var displayName: String {
                switch self {
                case .zh_z: return "zh/z"
                case .ch_c: return "ch/c"
                case .sh_s: return "sh/s"
                case .n_l: return "n/l"
                case .f_h: return "f/h"
                case .l_r: return "l/r"
                case .en_eng: return "en/eng"
                case .in_ing: return "in/ing"
                case .on_ong: return "on/ong"
                case .an_ang: return "an/ang"
                case .ian_iang: return "ian/iang"
                case .uan_uang: return "uan/uang"
                }
        }

        /// 描述
        public var description: String {
                switch self {
                case .zh_z: return "平卷舌不分 (zh/z)"
                case .ch_c: return "平卷舌不分 (ch/c)"
                case .sh_s: return "平卷舌不分 (sh/s)"
                case .n_l: return "鼻音不分 (n/l)"
                case .f_h: return "唇齿音不分 (f/h)"
                case .l_r: return "边音不分 (l/r)"
                case .en_eng: return "前后鼻音不分 (en/eng)"
                case .in_ing: return "前后鼻音不分 (in/ing)"
                case .on_ong: return "前后鼻音不分 (on/ong)"
                case .an_ang: return "前后鼻音不分 (an/ang)"
                case .ian_iang: return "前后鼻音不分 (ian/iang)"
                case .uan_uang: return "前后鼻音不分 (uan/uang)"
                }
        }

        /// 获取该类型对应的拼音映射
        public var mappings: FuzzyPinyinMapping {
                switch self {
                case .zh_z: return FuzzyPinyinMapping(initials: ["zh": ["z"], "z": ["zh"]])
                case .ch_c: return FuzzyPinyinMapping(initials: ["ch": ["c"], "c": ["ch"]])
                case .sh_s: return FuzzyPinyinMapping(initials: ["sh": ["s"], "s": ["sh"]])
                case .n_l: return FuzzyPinyinMapping(initials: ["n": ["l"], "l": ["n"]])
                case .f_h: return FuzzyPinyinMapping(initials: ["f": ["h"], "h": ["f"]])
                case .l_r: return FuzzyPinyinMapping(initials: ["l": ["r"], "r": ["l"]])
                case .en_eng: return FuzzyPinyinMapping(finals: ["en": ["eng"], "eng": ["en"]])
                case .in_ing: return FuzzyPinyinMapping(finals: ["in": ["ing"], "ing": ["in"]])
                case .on_ong: return FuzzyPinyinMapping(finals: ["on": ["ong"]])
                case .an_ang: return FuzzyPinyinMapping(finals: ["an": ["ang"], "ang": ["an"]])
                case .ian_iang: return FuzzyPinyinMapping(finals: ["ian": ["iang"], "iang": ["ian"]])
                case .uan_uang: return FuzzyPinyinMapping(finals: ["uan": ["uang"], "uang": ["uan"]])
                }
        }
}

/// 模糊音映射
public struct FuzzyPinyinMapping {
        /// 声母映射
        public let initials: [String: [String]]
        /// 韵母映射
        public let finals: [String: [String]]

        public init(initials: [String: [String]] = [:], finals: [String: [String]] = [:]) {
                self.initials = initials
                self.finals = finals
        }
}

/// 模糊音配置管理
public struct FuzzyPinyinSettings {

        /// 默认启用的模糊音类型
        public static let defaultEnabledTypes: Set<FuzzyPinyinType> = []

        /// 当前启用的模糊音类型
        nonisolated(unsafe) private(set) public static var enabledTypes: Set<FuzzyPinyinType> = {
                guard let savedData = UserDefaults.standard.data(forKey: "FuzzyPinyinEnabledTypes"),
                      let savedTypes = try? JSONDecoder().decode([String].self, from: savedData) else {
                        return defaultEnabledTypes
                }
                let types = Set(savedTypes.compactMap { FuzzyPinyinType(rawValue: $0) })
                return types
        }()

        /// 更新模糊音类型启用状态
        public static func setType(_ type: FuzzyPinyinType, enabled: Bool) {
                if enabled {
                        enabledTypes.insert(type)
                } else {
                        enabledTypes.remove(type)
                }
                saveTypes()
        }

        /// 检查某个类型是否启用
        public static func isTypeEnabled(_ type: FuzzyPinyinType) -> Bool {
                return enabledTypes.contains(type)
        }

        /// 保存配置
        private static func saveTypes() {
                let rawValues = Array(enabledTypes.map(\.rawValue))
                if let data = try? JSONEncoder().encode(rawValues) {
                        UserDefaults.standard.set(data, forKey: "FuzzyPinyinEnabledTypes")
                }
        }

        /// 是否启用了任何模糊音
        public static var isAnyEnabled: Bool {
                return !enabledTypes.isEmpty
        }

        /// 获取所有启用的映射
        public static var allMappings: [FuzzyPinyinMapping] {
                return enabledTypes.map(\.mappings)
        }
}
