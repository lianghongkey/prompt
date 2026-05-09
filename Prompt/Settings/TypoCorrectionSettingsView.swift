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
                                        Text("自动修正常见的字母顺序输入错误。例如开启 ng / gn 后，把 \"zhogn\" 也识别为 \"zhong\"。仅当原始拼音无法匹配时才会尝试纠错。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                }
                                .block()

                                VStack(alignment: .leading, spacing: 12) {
                                        Text("纠错规则")
                                                .font(.headline)

                                        Toggle(isOn: bindingFor(.ng_gn)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("ng / gn")
                                                                .font(.body)
                                                        Text(TypoCorrectionType.ng_gn.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
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
