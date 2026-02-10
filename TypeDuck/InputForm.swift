enum InputForm: Int {

        case mandarin = 1
        case transparent = 2
        case options = 3

        var isMandarin: Bool {
                return self == .mandarin
        }
        var isTransparent: Bool {
                return self == .transparent
        }
        var isOptions: Bool {
                return self == .options
        }

        static func matchInputMethodMode() -> InputForm {
                switch Options.inputMethodMode {
                case .mandarin:
                        return .mandarin
                case .abc:
                        return .transparent
                }
        }
}
