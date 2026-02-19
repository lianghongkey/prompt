import SwiftUI

struct HelpView: View {
        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                HelpRow(
                                        label: "显示／隐藏快捷选项页面",
                                        keys: [.control, .shift, .key("`")]
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                        HelpRow(
                                                label: "直接切换特定快捷选项",
                                                keys: [.control, .shift, .number]
                                        )
                                        Text("数字键：1, 2, 3, …, 8, 9, 0")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                                .padding(.leading, 8)
                                }
                                .block()

                                VStack(spacing: 8) {
                                        HelpRow(
                                                label: "清除当前预输入音节",
                                                keys: [.escape],
                                                alternative: [.control, .shift, .key("U")]
                                        )
                                        HelpRow(
                                                label: "输入当前预输入音节",
                                                keys: [.returnKey]
                                        )
                                        HelpRow(
                                                label: "输入当前候选词拼音",
                                                keys: [.shift, .returnKey]
                                        )
                                        HelpRow(
                                                label: "输入当前候选词",
                                                keys: [.space]
                                        )
                                        HelpRow(
                                                label: "输入当前候选词之首字",
                                                keys: [.key("[")]
                                        )
                                        HelpRow(
                                                label: "输入当前候选词之末字",
                                                keys: [.key("]")]
                                        )
                                        HelpRow(
                                                label: "从输入记忆删除当前候选词",
                                                keys: [.control, .shift, .backwardDelete]
                                        )
                                }
                                .block()

                                VStack(spacing: 8) {
                                        HelpRow(
                                                label: "移至上一个候选词",
                                                keys: [.key("▲")],
                                                alternative: [.shift, .tab]
                                        )
                                        HelpRow(
                                                label: "移至下一个候选词",
                                                keys: [.key("▼")],
                                                alternative: [.tab]
                                        )
                                        HelpRow(
                                                label: "移至上一页",
                                                keys: [.key("◀")],
                                                alternative: [.key("-")],
                                                alternative2: [.key("Page Up ↑")]
                                        )
                                        HelpRow(
                                                label: "移至下一页",
                                                keys: [.key("▶")],
                                                alternative: [.key("=")],
                                                alternative2: [.key("Page Down ↓")]
                                        )
                                        HelpRow(
                                                label: "返回第一页",
                                                keys: [.key("Home ⤒")]
                                        )
                                }
                                .block()
                        }
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("帮助")
        }
}

private struct HelpRow: View {
        let label: String
        let keys: [KeyType]
        var alternative: [KeyType]? = nil
        var alternative2: [KeyType]? = nil

        var body: some View {
                HStack(alignment: .top, spacing: 8) {
                        Text(label)
                                .frame(minWidth: 120, maxWidth: 200, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                        Text("：")
                                .foregroundStyle(Color.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                                                if index > 0 {
                                                        Text("＋")
                                                }
                                                KeyBlockView(key: key)
                                        }
                                }

                                if let alt = alternative {
                                        HStack(spacing: 4) {
                                                Text("或")
                                                ForEach(Array(alt.enumerated()), id: \.offset) { index, key in
                                                        if index > 0 {
                                                                Text("＋")
                                                        }
                                                        KeyBlockView(key: key)
                                                }
                                        }
                                }

                                if let alt2 = alternative2 {
                                        HStack(spacing: 4) {
                                                Text("或")
                                                ForEach(Array(alt2.enumerated()), id: \.offset) { index, key in
                                                        if index > 0 {
                                                                Text("＋")
                                                        }
                                                        KeyBlockView(key: key)
                                                }
                                        }
                                }
                        }

                        Spacer(minLength: 0)
                }
        }
}

private enum KeyType {
        case control
        case shift
        case number
        case space
        case escape
        case tab
        case returnKey
        case backwardDelete
        case key(String)
}

private struct KeyBlockView: View {
        let key: KeyType

        var body: some View {
                Text(keyText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(minWidth: 60, minHeight: 24)
                        .background(Material.regular, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }

        private var keyText: String {
                switch key {
                case .control: return "Control ⌃"
                case .shift: return "Shift ⇧"
                case .number: return "数字键"
                case .space: return "Space ␣"
                case .escape: return "esc ⎋"
                case .tab: return "Tab ⇥"
                case .returnKey: return "Return ⏎"
                case .backwardDelete: return "Delete ⌫"
                case .key(let text): return text
                }
        }
}
