import SwiftUI
import CoreIME

struct FuzzyPinyinSettingsView: View {
        @State private var enabledTypes: Set<FuzzyPinyinType>

        init() {
                self._enabledTypes = State(initialValue: FuzzyPinyinSettings.enabledTypes)
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                        Text("关于模糊音")
                                                .font(.headline)
                                        Text("模糊音可以让输入法识别发音相似的拼音，方便某些发音不准的用户使用。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                }
                                .block()

                                VStack(alignment: .leading, spacing: 12) {
                                        Text("声母模糊音")
                                                .font(.headline)

                                        Toggle(isOn: bindingFor(.zh_z)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("zh / z")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.zh_z.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.ch_c)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("ch / c")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.ch_c.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.sh_s)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("sh / s")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.sh_s.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.n_l)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("n / l")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.n_l.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.f_h)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("f / h")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.f_h.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.l_r)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("l / r")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.l_r.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }
                                }
                                .block()

                                VStack(alignment: .leading, spacing: 12) {
                                        Text("韵母模糊音")
                                                .font(.headline)

                                        Toggle(isOn: bindingFor(.en_eng)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("en / eng")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.en_eng.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.in_ing)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("in / ing")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.in_ing.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.on_ong)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("on / ong")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.on_ong.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.an_ang)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("an / ang")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.an_ang.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.ian_iang)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("ian / iang")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.ian_iang.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }

                                        Toggle(isOn: bindingFor(.uan_uang)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                        Text("uan / uang")
                                                                .font(.body)
                                                        Text(FuzzyPinyinType.uan_uang.description)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                }
                                        }
                                }
                                .block()

                                HStack(spacing: 12) {
                                        Button("全部启用") {
                                                enabledTypes = Set(FuzzyPinyinType.allCases)
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
                .navigationTitle("模糊音设置")
        }

        private func bindingFor(_ type: FuzzyPinyinType) -> Binding<Bool> {
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
                // 保存到 FuzzyPinyinSettings
                for type in FuzzyPinyinType.allCases {
                        FuzzyPinyinSettings.setType(type, enabled: enabledTypes.contains(type))
                }
        }
}

#Preview {
        FuzzyPinyinSettingsView()
}
