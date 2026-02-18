import SwiftUI

struct HelpView: View {
        var body: some View {
                ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 4) {
                                        LabelText("显示／隐藏快捷选项页面")
                                        Text.separator
                                        KeyBlockView.control
                                        Text.plus
                                        KeyBlockView.shift
                                        Text.plus
                                        KeyBlockView("`")
                                        Spacer()
                                }
                                .block()
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        LabelText("直接切换特定快捷选项")
                                        Text.separator
                                        VStack(spacing: 6) {
                                                HStack(spacing: 4) {
                                                        KeyBlockView.control
                                                        Text.plus
                                                        KeyBlockView.shift
                                                        Text.plus
                                                        KeyBlockView.number
                                                        Spacer()
                                                }
                                                HStack(spacing: 0) {
                                                        Text("数字键").fontWeight(.medium)
                                                        Text("：").foregroundStyle(Color.secondary)
                                                        Text(verbatim: "1, 2, 3, …, 8, 9, 0")
                                                        Spacer()
                                                }
                                                .font(.subheadline)
                                        }
                                }
                                .block()
                                VStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                                LabelText("清除当前预输入音节")
                                                Text.separator
                                                KeyBlockView.escape
                                                Text.or
                                                KeyBlockView.control
                                                Text.plus
                                                KeyBlockView.shift
                                                Text.plus
                                                KeyBlockView("U")
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("输入当前预输入音节")
                                                Text.separator
                                                KeyBlockView.returnKey
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("输入当前候选词拼音")
                                                Text.separator
                                                KeyBlockView.shift
                                                Text.plus
                                                KeyBlockView.returnKey
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("输入当前候选词")
                                                Text.separator
                                                KeyBlockView.space
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("输入当前候选词之首字")
                                                Text.separator
                                                KeyBlockView("[")
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("输入当前候选词之末字")
                                                Text.separator
                                                KeyBlockView("]")
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("从输入记忆删除当前候选词")
                                                Text.separator
                                                KeyBlockView.control
                                                Text.plus
                                                KeyBlockView.shift
                                                Text.plus
                                                KeyBlockView.backwardDelete
                                                Spacer()
                                        }
                                }
                                .block()
                                VStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                                LabelText("移至上一个候选词")
                                                Text.separator
                                                KeyBlockView("▲")
                                                Text.or
                                                KeyBlockView.shift
                                                Text.plus
                                                KeyBlockView.tab
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("移至下一个候选词")
                                                Text.separator
                                                KeyBlockView("▼")
                                                Text.or
                                                KeyBlockView.tab
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("移至上一页")
                                                Text.separator
                                                KeyBlockView("◀")
                                                Text.or
                                                KeyBlockView("-")
                                                Text.or
                                                KeyBlockView("Page Up ↑")
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("移至下一页")
                                                Text.separator
                                                KeyBlockView("▶")
                                                Text.or
                                                KeyBlockView("=")
                                                Text.or
                                                KeyBlockView("Page Down ↓")
                                                Spacer()
                                        }
                                        HStack(spacing: 4) {
                                                LabelText("返回第一页")
                                                Text.separator
                                                KeyBlockView("Home ⤒")
                                                Spacer()
                                        }
                                }
                                .block()
                        }
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("帮助")
        }
}

#Preview {
        HelpView()
}

private struct LabelText: View {
        init(_ title: String) {
                self.title = title
        }
        private let title: String
        var body: some View {
                Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: 250, alignment: .leading)
        }
}

private struct KeyBlockView: View {

        init(_ keyText: String) {
                self.keyText = keyText
                self.key = nil
        }

        init(localized key: String) {
                self.keyText = key
                self.key = nil
        }

        private let keyText: String?
        private let key: Void?

        var body: some View {
                let text: Text
                if let keyText = keyText {
                    text = Text(verbatim: keyText)
                } else {
                    text = Text(verbatim: "")
                }
                return text
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 2)
                        .frame(width: 80, height: 24)
                        .background(Material.regular, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }

        static let control: KeyBlockView = KeyBlockView("Control ⌃")
        static let shift: KeyBlockView = KeyBlockView("Shift ⇧")
        static let number: KeyBlockView = KeyBlockView(localized: "数字键")
        static let space: KeyBlockView = KeyBlockView("Space ␣")
        static let escape: KeyBlockView = KeyBlockView("esc ⎋")
        static let tab: KeyBlockView = KeyBlockView("Tab ⇥")
        static let returnKey: KeyBlockView = KeyBlockView("Return ⏎")

        /// Backspace. NOT Forward-Delete.
        static let backwardDelete: KeyBlockView = KeyBlockView("Delete ⌫")
}

private extension Text {
        static let separator: Text = Text("：").foregroundColor(.secondary)
        static let plus: Text = Text(verbatim: "＋")
        static let or: Text = Text("或")
}
