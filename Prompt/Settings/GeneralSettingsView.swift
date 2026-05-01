import SwiftUI
import CoreIME

struct GeneralSettingsView: View {

        @State private var pageSize: Int = AppSettings.candidatePageSize
        private let pageSizeRange: Range<Int> = AppSettings.candidatePageSizeRange

        @State private var isEmojiSuggestionsOn: Bool = Options.isEmojiSuggestionsOn
        @State private var isInputMemoryOn: Bool = AppSettings.isInputMemoryOn
        @State private var defaultInputMode: InputMethodMode = AppSettings.defaultInputModeOnActivation
        @State private var useCapsLockForMandarin: Bool = AppSettings.useCapsLockForMandarin
        @State private var excludedApps: [String] = AppSettings.appsExcludedFromInputMemory
        @State private var newExcludedBundleID: String = ""

        @State private var isClearInputMemoryConfirmDialogPresented: Bool = false
        @State private var isPerformingClearInputMemory: Bool = false
        @State private var clearInputMemoryProgress: Double = 0
        private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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
        private var excludedAppsSection: some View {
                VStack(alignment: .leading, spacing: 8) {
                        Text("不记忆输入法状态的 App")
                                .font(.headline)
                        Text("这些 app 每次激活都会重置为默认输入模式，忽略上次切换记录")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
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
                                HStack {
                                        Picker("每页候选词数量", selection: $pageSize) {
                                                ForEach(pageSizeRange, id: \.self) {
                                                        Text(verbatim: "\($0)").tag($0)
                                                }
                                        }
                                        .pickerStyle(.menu)
                                        .scaledToFit()
                                        .onChange(of: pageSize) { newPageSize in
                                                AppSettings.updateCandidatePageSize(to: newPageSize)
                                        }
                                        Spacer()
                                }
                                .block()
                                HStack {
                                        Picker("切换到本输入法时默认模式", selection: $defaultInputMode) {
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
                                .block()
                                excludedAppsSection
                                        .block()
                                HStack {
                                        Toggle("使用 Caps Lock 键切换到中文", isOn: $useCapsLockForMandarin)
                                                .toggleStyle(.switch)
                                                .scaledToFit()
                                                .onChange(of: useCapsLockForMandarin) { newState in
                                                        AppSettings.updateUseCapsLockForMandarin(to: newState)
                                                }
                                        Spacer()
                                }
                                .block()
                                HStack {
                                        Toggle("表情符号建议", isOn: $isEmojiSuggestionsOn)
                                                .toggleStyle(.switch)
                                                .scaledToFit()
                                                .onChange(of: isEmojiSuggestionsOn) { newState in
                                                        Options.updateEmojiSuggestions(to: newState)
                                                }
                                        Spacer()
                                }
                                .block()
                                VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                                Toggle("输入记忆", isOn: $isInputMemoryOn)
                                                        .toggleStyle(.switch)
                                                        .scaledToFit()
                                                        .onChange(of: isInputMemoryOn) { newState in
                                                                AppSettings.updateInputMemory(to: newState)
                                                        }
                                                Spacer()
                                        }
                                        HStack {
                                                Button(role: .destructive) {
                                                        isClearInputMemoryConfirmDialogPresented = true
                                                } label: {
                                                        Text("清空输入记忆")
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .foregroundStyle(Color.red)
                                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                .confirmationDialog("清空输入记忆？", isPresented: $isClearInputMemoryConfirmDialogPresented) {
                                                        Button("清空", role: .destructive) {
                                                                clearInputMemoryProgress = 0
                                                                isPerformingClearInputMemory = true
                                                                UserLexicon.deleteAll()
                                                        }
                                                        Button("取消", role: .cancel) {
                                                                isClearInputMemoryConfirmDialogPresented = false
                                                        }
                                                }
                                                ProgressView(value: clearInputMemoryProgress)
                                                        .frame(width: 100)
                                                        .opacity(isPerformingClearInputMemory ? 1 : 0)
                                                        .onReceive(timer) { _ in
                                                                guard isPerformingClearInputMemory else { return }
                                                                if clearInputMemoryProgress > 1 {
                                                                        isPerformingClearInputMemory = false
                                                                } else {
                                                                        clearInputMemoryProgress += 0.1
                                                                }
                                                        }
                                                Spacer()
                                        }
                                }
                                .block()
                        }
                        .padding()
                        .frame(minWidth: 300)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("设置")
        }
}

/// NSTextField wrapper that reliably handles paste (Cmd+V) regardless of IME state.
struct NativeTextField: NSViewRepresentable {
        let placeholder: String
        @Binding var text: String

        func makeNSView(context: Context) -> NSTextField {
                let field = NSTextField()
                field.placeholderString = placeholder
                field.delegate = context.coordinator
                field.bezelStyle = .roundedBezel
                field.cell?.isScrollable = true
                field.cell?.wraps = false
                return field
        }

        func updateNSView(_ field: NSTextField, context: Context) {
                if field.stringValue != text {
                        field.stringValue = text
                }
        }

        func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

        final class Coordinator: NSObject, NSTextFieldDelegate {
                @Binding var text: String
                init(text: Binding<String>) { _text = text }
                func controlTextDidChange(_ obj: Notification) {
                        if let field = obj.object as? NSTextField {
                                text = field.stringValue
                        }
                }
        }
}

#Preview {
        GeneralSettingsView()
}
