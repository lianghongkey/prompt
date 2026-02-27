import Foundation

extension String {

        static let empty: String = ""
        static let space: String = "\u{20}"

        /// A subsequence that only contains tones (1-6)
        var tones: String {
                return self.filter(\.isTone)
        }

        /// Remove all tones (1-6)
        /// - Returns: A subsequence that leaves off tones.
        func removedTones() -> String {
                return self.filter({ !$0.isTone })
        }

        /// Remove all spaces
        /// - Returns: A subsequence that leaves off spaces.
        public func removedSpaces() -> String {
                return self.filter({ !$0.isSpace })
        }

        /// Remove all spaces and tones
        /// - Returns: A subsequence that leaves off spaces and tones.
        func removedSpacesTones() -> String {
                return self.filter({ !$0.isSpaceOrTone })
        }

        /// Remove all separators
        /// - Returns: A subsequence that leaves off separators
        func removedSeparators() -> String {
                return self.filter({ !$0.isSeparator })
        }

        /// Remove all separators and tones
        /// - Returns: A subsequence that leaves off separators and tones
        func removedSeparatorsTones() -> String {
                return self.filter({ !$0.isSeparatorOrTone })
        }

        /// Remove all spaces, tones and separators
        /// - Returns: A subsequence that leaves off spaces, tones and separators
        func removedSpacesTonesSeparators() -> String {
                return self.filter({ !$0.isSpaceOrSeparatorOrTone })
        }

        /// Contains separator
        var hasSeparators: Bool {
                return self.contains(Character.separator)
        }

        /// Contains tone number (1-6)
        var hasTones: Bool {
                return self.first(where: { $0.isTone }) != nil
        }
}

extension StringProtocol {

        /// Format text with separators and tones
        /// - Returns: Formatted text
        public func formattedForMark() -> String {
                let blocks = self.map { character -> String in
                        return character.isSeparatorOrTone ? "\(character) " : String(character)
                }
                return blocks.joined().trimmingCharacters(in: .whitespaces)
        }
}

extension Sequence where Element == Character {

        /// Returns a new string by concatenating the elements of the sequence, adding a space between each element.
        public func spaceSeparated() -> String {
                return self.reduce(into: String.empty) { partialResult, character in
                        if partialResult.isNotEmpty {
                                partialResult.append(String.space)
                        }
                        partialResult.append(character)
                }
        }
}

extension String {
        public var isValid: Bool {
                return self != "X"
        }

        /// Deterministic hash function compatible with Python implementation
        /// Uses the same algorithm: hash = (hash * 31 + char_code) & 0xFFFFFFFF
        public var deterministicHash: Int {
                var hashValue: UInt32 = 0
                for character in self.utf8 {
                        hashValue = (hashValue &* 31 &+ UInt32(character)) & 0xFFFFFFFF
                }
                return Int(hashValue) > 0 ? Int(hashValue) : 1
        }
}
