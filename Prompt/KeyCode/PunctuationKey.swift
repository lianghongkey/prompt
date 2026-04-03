import CoreIME

struct PunctuationKey: Hashable {
        let keyText: String
        let shiftingKeyText: String
        let instantSymbol: String?
        let instantShiftingSymbol: String?
}

extension PunctuationKey {
        static let comma = PunctuationKey(keyText: ",", shiftingKeyText: "<", instantSymbol: "，", instantShiftingSymbol: "《")
        static let period = PunctuationKey(keyText: ".", shiftingKeyText: ">", instantSymbol: "。", instantShiftingSymbol: "》")
        static let slash = PunctuationKey(keyText: "/", shiftingKeyText: "?", instantSymbol: "／", instantShiftingSymbol: "？")
        static let semicolon = PunctuationKey(keyText: ";", shiftingKeyText: ":", instantSymbol: "；", instantShiftingSymbol: "：")
        static let quote = PunctuationKey(keyText: "'", shiftingKeyText: "\"", instantSymbol: "\u{2018}", instantShiftingSymbol: "\u{201C}")
        static let bracketLeft = PunctuationKey(keyText: "[", shiftingKeyText: "{", instantSymbol: "[", instantShiftingSymbol: "{")
        static let bracketRight = PunctuationKey(keyText: "]", shiftingKeyText: "}", instantSymbol: "]", instantShiftingSymbol: "}")
        static let backSlash = PunctuationKey(keyText: "\\", shiftingKeyText: "|", instantSymbol: "、", instantShiftingSymbol: "｜")
        static let backquote = PunctuationKey(keyText: "`", shiftingKeyText: "~", instantSymbol: "·", instantShiftingSymbol: "～")
        static let minus = PunctuationKey(keyText: "-", shiftingKeyText: "_", instantSymbol: "-", instantShiftingSymbol: "——")
        static let equal = PunctuationKey(keyText: "=", shiftingKeyText: "+", instantSymbol: "=", instantShiftingSymbol: "+")
}

extension PunctuationKey {
        static let number1One = PunctuationKey(keyText: "1", shiftingKeyText: "!", instantSymbol: "1", instantShiftingSymbol: "！")
        static let number2Two = PunctuationKey(keyText: "2", shiftingKeyText: "@", instantSymbol: "2", instantShiftingSymbol: "@")
        static let number3Three = PunctuationKey(keyText: "3", shiftingKeyText: "#", instantSymbol: "3", instantShiftingSymbol: "#")
        static let number4Four = PunctuationKey(keyText: "4", shiftingKeyText: "$", instantSymbol: "4", instantShiftingSymbol: "$")
        static let number5Five = PunctuationKey(keyText: "5", shiftingKeyText: "%", instantSymbol: "5", instantShiftingSymbol: "%")
        static let number6Six = PunctuationKey(keyText: "6", shiftingKeyText: "^", instantSymbol: "6", instantShiftingSymbol: "……")
        static let number7Seven = PunctuationKey(keyText: "7", shiftingKeyText: "&", instantSymbol: "7", instantShiftingSymbol: "&")
        static let number8Eight = PunctuationKey(keyText: "8", shiftingKeyText: "*", instantSymbol: "8", instantShiftingSymbol: "*")
        static let number9Nine = PunctuationKey(keyText: "9", shiftingKeyText: "(", instantSymbol: "9", instantShiftingSymbol: "（")
        static let number0Zero = PunctuationKey(keyText: "0", shiftingKeyText: ")", instantSymbol: "0", instantShiftingSymbol: "）")
}

extension PunctuationKey {

        /// Number key symbol in English PunctuationForm
        static func numberKeyShiftingSymbol(of number: Int) -> String? {
                switch number {
                case 0: return ")"
                case 1: return "!"
                case 2: return "@"
                case 3: return "#"
                case 4: return "$"
                case 5: return "%"
                case 6: return "^"
                case 7: return "&"
                case 8: return "*"
                case 9: return "("
                default: return nil
                }
        }

        /// Number key symbol in Mandarin PunctuationForm
        static func numberKeyShiftingMandarinSymbol(of number: Int) -> String? {
                switch number {
                case 0: return "）"
                case 1: return "！"
                case 2: return "@"
                case 3: return "#"
                case 4: return "$"
                case 5: return "%"
                case 6: return "……"
                case 7: return "&"
                case 8: return "*"
                case 9: return "（"
                default: return nil
                }
        }
}
