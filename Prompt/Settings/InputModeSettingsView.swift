import SwiftUI
import CoreIME

struct InputModeSettingsView: View {

        @State private var defaultInputMode: InputMethodMode = AppSettings.defaultInputModeOnActivation
        @State private var useCapsLockForMandarin: Bool = AppSettings.useCapsLockForMandarin
        @State private var excludedApps: [String] = AppSettings.appsExcludedFromInputMemory
        @State private var newExcludedBundleID: String = ""

        private func refreshExcludedApps() {
                excludedApps = AppSettings.appsExcludedFromInputMemory
        }

        private func runningRegularApps() -> [NSRunningApplication] {
                NSWorkspace.shared.runningApplications
                        .filter({ $0.activationPolicy == .regular })
                        .filter({ ($0.bundleIdentifier ?? "").isEmpty == false })
                        .sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") })
        }

        private func appDisplayName(for bundleID: String) -> String {
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                   let name = running.localizedName {
                        return "\(name) (\(bundleID))"
                }
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                   let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
                   let name = values.localizedName {
                        return "\(name) (\(bundleID))"
                }
                return bundleID
        }

        @ViewBuilder
        private var priorityExplanationSection: some View {
                VStack(alignment: .leading, spacing: 8) {
                        Text("中英文模式选择")
                                .font(.headline)
                        Text("每次切到一个新输入框时，按以下顺序决定使用中文还是英文：")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                                Text("1. 该 App 上次切换的状态")
                                Text("2. 默认模式")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        Text("Shift 单击可随时手动切换：左 Shift → 英文，右 Shift → 中文。")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                }
        }

        @ViewBuilder
        private var defaultModeSection: some View {
                HStack {
                        Picker("默认模式", selection: $defaultInputMode) {
                                Text("中文").tag(InputMethodMode.mandarin)
                                Text("英文").tag(InputMethodMode.abc)
                        }
                        .pickerStyle(.menu)
                        .scaledToFit()
                        .onChange(of: defaultInputMode) { newMode in
                                AppSettings.updateDefaultInputModeOnActivation(to: newMode)
                        }
                        Spacer()
                }
        }

        @ViewBuilder
        private var capsLockSection: some View {
                HStack {
                        Toggle("使用 Caps Lock 键切换到中文", isOn: $useCapsLockForMandarin)
                                .toggleStyle(.switch)
                                .scaledToFit()
                                .onChange(of: useCapsLockForMandarin) { newState in
                                        AppSettings.updateUseCapsLockForMandarin(to: newState)
                                }
                        Spacer()
                }
        }

        @ViewBuilder
        private var excludedAppsSection: some View {
                VStack(alignment: .leading, spacing: 8) {
                        Text("不记忆输入法状态的 App")
                                .font(.headline)
                        Text("这些 App 每次激活都重置为默认模式，忽略上次切换记录")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        if excludedApps.isEmpty {
                                Text("（暂无）")
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                        } else {
                                ForEach(excludedApps, id: \.self) { bundleID in
                                        HStack {
                                                Text(appDisplayName(for: bundleID))
                                                        .font(.callout)
                                                Spacer()
                                                Button {
                                                        AppSettings.removeAppExcludedFromInputMemory(bundleID)
                                                        refreshExcludedApps()
                                                } label: {
                                                        Image(systemName: "minus.circle.fill")
                                                                .foregroundStyle(Color.red)
                                                }
                                                .buttonStyle(.plain)
                                        }
                                }
                        }
                        HStack {
                                NativeTextField(placeholder: "Bundle ID 例如 com.apple.Safari", text: $newExcludedBundleID)
                                        .frame(height: 22)
                                Button("添加") {
                                        AppSettings.addAppExcludedFromInputMemory(newExcludedBundleID)
                                        newExcludedBundleID = ""
                                        refreshExcludedApps()
                                }
                                .disabled(newExcludedBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                                Menu("从运行中的 App 选择") {
                                        ForEach(runningRegularApps(), id: \.processIdentifier) { app in
                                                if let bundleID = app.bundleIdentifier {
                                                        Button(app.localizedName ?? bundleID) {
                                                                AppSettings.addAppExcludedFromInputMemory(bundleID)
                                                                refreshExcludedApps()
                                                        }
                                                        .disabled(excludedApps.contains(bundleID))
                                                }
                                        }
                                }
                                .frame(maxWidth: 180)
                        }
                }
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                priorityExplanationSection
                                        .block()
                                defaultModeSection
                                        .block()
                                capsLockSection
                                        .block()
                                excludedAppsSection
                                        .block()
                        }
                        .padding()
                        .frame(minWidth: 300)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("输入法选择")
        }
}

#Preview {
        InputModeSettingsView()
}
