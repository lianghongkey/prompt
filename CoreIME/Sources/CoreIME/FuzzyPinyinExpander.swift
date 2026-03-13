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

                // 分割拼音为声母和韵母
                let components = splitPinyin(pinyin)
                guard components.isValid else {
                        return [pinyin]
                }

                let initial = components.initial
                let final_ = components.final

                // 用查找表直接获取变体
                var initialVariants = Set<String>()
                initialVariants.insert(initial)
                if let alternatives = FuzzyPinyinSettings.initialLookup[initial] {
                        initialVariants.formUnion(alternatives)
                }

                var finalVariants = Set<String>()
                finalVariants.insert(final_)
                if let alternatives = FuzzyPinyinSettings.finalLookup[final_] {
                        finalVariants.formUnion(alternatives)
                }

                // 如果没有任何变体，直接返回
                guard initialVariants.count > 1 || finalVariants.count > 1 else {
                        return [pinyin]
                }

                var results: [String] = [pinyin]
                for initialVariant in initialVariants {
                        for finalVariant in finalVariants {
                                let combined = initialVariant + finalVariant
                                if combined != pinyin {
                                        results.append(combined)
                                }
                        }
                }

                return results
        }

        /// 扩展拼音数组，生成所有可能的组合
        /// - Parameter pinyins: 拼音数组
        /// - Returns: 所有可能的拼音数组组合（原始拼音组合始终排在第一位）
        public static func expandArray(_ pinyins: [String]) -> [[String]] {
                guard FuzzyPinyinSettings.isAnyEnabled else {
                        return [pinyins]
                }

                // 使用两个数组：一个存放原始拼音组合，一个存放模糊音变体
                var exactMatches: [[String]] = [pinyins]
                var fuzzyMatches: [[String]] = []

                for (index, pinyin) in pinyins.enumerated() {
                        let expanded = expand(pinyin)
                        guard expanded.count > 1 else { continue }

                        var newExactMatches: [[String]] = []
                        var newFuzzyMatches: [[String]] = []

                        // 处理精确匹配
                        for existing in exactMatches {
                                for variant in expanded {
                                        var newArray = existing
                                        newArray[index] = variant
                                        if variant == pinyin {
                                                // 保持原始拼音
                                                newExactMatches.append(newArray)
                                        } else {
                                                // 模糊音变体
                                                newFuzzyMatches.append(newArray)
                                        }
                                }
                        }

                        // 处理已有的模糊匹配
                        for existing in fuzzyMatches {
                                for variant in expanded {
                                        var newArray = existing
                                        newArray[index] = variant
                                        newFuzzyMatches.append(newArray)
                                }
                        }

                        exactMatches = newExactMatches
                        fuzzyMatches = newFuzzyMatches

                        guard (exactMatches.count + fuzzyMatches.count) < 20 else { break }
                }

                // 精确匹配在前，模糊匹配在后
                return exactMatches + fuzzyMatches
        }
}
