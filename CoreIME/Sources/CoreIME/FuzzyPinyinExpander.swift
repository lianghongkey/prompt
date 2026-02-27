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
                        guard result.count < 20 else { break }
                }

                return result
        }
}
