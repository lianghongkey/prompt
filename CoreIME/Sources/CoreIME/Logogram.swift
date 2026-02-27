/// 字符集標準
public enum Logogram: Int {

        /// Traditional. 繁體字
        case traditional = 1

        /// Simplified. 簡體字
        case simplified = 4
}

public typealias CharacterStandard = Logogram

extension CharacterStandard {

        /// self == .simplified
        public var isSimplified: Bool {
                return self == .simplified
        }

        /// self != .simplified
        public var isTraditional: Bool {
                return self != .simplified
        }
}

