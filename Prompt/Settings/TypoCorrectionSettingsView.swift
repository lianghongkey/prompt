import SwiftUI
import CoreIME

struct TypoCorrectionSettingsView: View {
        @State private var enabledTypes: Set<TypoCorrectionType>

        init() {
                self._enabledTypes = State(initialValue: TypoCorrectionSettings.enabledTypes)
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                        Text("关于顺序纠错")
                                                .font(.headline)
                                        Text("自动修正常见的字母顺序输入错误。所有规则均为单向：仅把左侧拼写视作右侧的等价输入，反向不成立。例如开启 gn → ng 后，\"zhogn\" 会被识别为 \"zhong\"，但 \"zhong\" 不会被误识为 \"zhogn\"。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        Text("纠错生效条件：被交换的两个字母必须落在同一个音节内（不跨音节边界），并且该音节中还需有其他字母。例如开启 ie → ei 后，\"bie\" 会被识别为 \"bei\"（ei 在 bei 内，且 b 在 ei 之外）；但单独的 \"ie\" 不会被改为 \"ei\"（整个音节就是被交换的字母对）。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        Text("仅在原始拼音无法匹配时才会作为额外候选出现，且会标记为模糊匹配，排在精确匹配之后。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                }
                                .block()

                                VStack(alignment: .leading, spacing: 12) {
                                        Text("纠错规则")
                                                .font(.headline)

                                        ForEach(TypoCorrectionType.allCases) { type in
                                                Toggle(isOn: bindingFor(type)) {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                                Text(type.displayName)
                                                                        .font(.body)
                                                                Text(type.description)
                                                                        .font(.caption)
                                                                        .foregroundColor(.secondary)
                                                        }
                                                }
                                        }
                                }
                                .block()

                                HStack(spacing: 12) {
                                        Button("全部启用") {
                                                enabledTypes = Set(TypoCorrectionType.allCases)
                                                saveChanges()
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                        Button("全部禁用") {
                                                enabledTypes = []
                                                saveChanges()
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                        Spacer()
                                }
                                .padding(.top, 4)
                        }
                        .textSelection(.enabled)
                        .padding()
                        .frame(minWidth: 300)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("顺序纠错")
        }

        private func bindingFor(_ type: TypoCorrectionType) -> Binding<Bool> {
                Binding<Bool>(
                        get: { enabledTypes.contains(type) },
                        set: { newValue in
                                if newValue {
                                        enabledTypes.insert(type)
                                } else {
                                        enabledTypes.remove(type)
                                }
                                saveChanges()
                        }
                )
        }

        private func saveChanges() {
                for type in TypoCorrectionType.allCases {
                        TypoCorrectionSettings.setType(type, enabled: enabledTypes.contains(type))
                }
        }
}

#Preview {
        TypoCorrectionSettingsView()
}
