import Foundation

/// 模糊音扩展器
public struct FuzzyPinyinExpander {

        /// 扩展拼音，生成所有可能的模糊音组合
        /// - Parameter pinyin: 原始拼音
        /// - Returns: 所有可能的拼音组合（包括原始拼音）
        public static func expand(_ pinyin: String) -> [String] {
                guard FuzzyPinyinSettings.isAnyEnabled else {
                        return [pinyin]
                }

                var results = Set<String>()
                results.insert(pinyin)

                // 分割拼音为声母和韵母
                let components = splitPinyin(pinyin)
                guard components.isValid else {
                        // 如果不是有效的拼音结构，直接返回原拼音
                        return [pinyin]
                }

                let initial = components.initial
                let final = components.final

                let mappings = FuzzyPinyinSettings.allMappings

                // 收集所有可能的声母变体（包括原始声母）
                var initialVariants = Set<String>()
                initialVariants.insert(initial)

                // 收集所有可能的韵母变体（包括原始韵母）
                var finalVariants = Set<String>()
                finalVariants.insert(final)

                // 尝试所有声母替换
                for mapping in mappings {
                        for (mappingInitial, alternatives) in mapping.initials {
                                if initial == mappingInitial {
                                        // 找到匹配的声母，添加所有替代声母
                                        for alternative in alternatives {
                                                initialVariants.insert(alternative)
                                        }
                                }
                        }

                        // 尝试所有韵母替换
                        for (mappingFinal, alternatives) in mapping.finals {
                                if final == mappingFinal {
                                        // 找到匹配的韵母，添加所有替代韵母
                                        for alternative in alternatives {
                                                finalVariants.insert(alternative)
                                        }
                                }
                        }
                }

                // 生成所有可能的声母-韵母组合
                for initialVariant in initialVariants {
                        for finalVariant in finalVariants {
                                // 组合声母和韵母
                                let combined = initialVariant + finalVariant
                                // 只有当组合不是原始拼音时才添加
                                if combined != pinyin {
                                        results.insert(combined)
                                }
                        }
                }

                return Array(results).sorted()
        }

        /// 扩展拼音数组，生成所有可能的组合
        /// - Parameter pinyins: 拼音数组
        /// - Returns: 所有可能的拼音数组组合
        public static func expandArray(_ pinyins: [String]) -> [[String]] {
                guard FuzzyPinyinSettings.isAnyEnabled else {
                        return [pinyins]
                }

                var result: [[String]] = [pinyins]

                for (index, pinyin) in pinyins.enumerated() {
                        let expanded = expand(pinyin)
                        guard expanded.count > 1 else { continue }

                        var newResult: [[String]] = []
                        for existing in result {
                                for variant in expanded {
                                        var newArray = existing
                                        newArray[index] = variant
                                        newResult.append(newArray)
                                }
                        }
                        result = newResult
                }

                return result
        }
}
