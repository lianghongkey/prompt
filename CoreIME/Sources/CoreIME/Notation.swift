public struct Notation: Hashable, Sendable {

        // Equatable
        public static func ==(lhs: Notation, rhs: Notation) -> Bool {
                return lhs.word == rhs.word && lhs.pinyin == rhs.pinyin
        }

        // Hashable
        public func hash(into hasher: inout Hasher) {
                hasher.combine(word)
                hasher.combine(pinyin)
        }

        /// Chinese word
        public let word: String

        /// Pinyin romanization
        public let pinyin: String

        /// higher is preferred
        public let frequency: Int

        /// smaller is preferred
        public let pronunciationOrder: Int

        public init(word: String, pinyin: String, frequency: Int, pronunciationOrder: Int = 1) {
                self.word = word
                self.pinyin = pinyin
                self.frequency = frequency
                self.pronunciationOrder = pronunciationOrder
        }
}

extension Notation {
        public static let example: Notation = Notation(word: "举例", pinyin: "ju3 li3", frequency: 1000, pronunciationOrder: 1)
}
