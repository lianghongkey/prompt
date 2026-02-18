import SwiftUI

final class SettingsViewAppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
                return true
        }
        func applicationWillFinishLaunching(_ notification: Notification) {
                NSWindow.allowsAutomaticWindowTabbing = false
        }
        func applicationDidFinishLaunching(_ notification: Notification) {
                _ = NSApp.windows.map({ $0.tabbingMode = .disallowed })
        }
}

struct SettingsView: View {

        @NSApplicationDelegateAdaptor(SettingsViewAppDelegate.self) var appDelegate

        // macOS 13.0+
        @State private var selection: SettingsSidebarRow = AppSettings.selectedSettingsSidebarRow

        // macOS 12
        @State private var isGeneralSettingsViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .general
        @State private var isFuzzyPinyinSettingsViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .fuzzyPinyin
        @State private var isHelpViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .help
        @State private var isAboutViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .about

        var body: some View {
                if #available(macOS 13.0, *) {
                        NavigationSplitView {
                                List(selection: $selection) {
                                        Label("设置", systemImage: "gear").tag(SettingsSidebarRow.general)
                                        Label("模糊音", systemImage: "speaker.wave.2").tag(SettingsSidebarRow.fuzzyPinyin)
                                        Label("帮助", systemImage: "keyboard").tag(SettingsSidebarRow.help)
                                        Label("关于", systemImage: "info.circle").tag(SettingsSidebarRow.about)
                                }
                                .frame(minWidth: 150)
                        } detail: {
                                detailView
                        }
                        .navigationSplitViewStyle(.balanced)
                } else {
                        NavigationView {
                                List {
                                        NavigationLink(destination: GeneralSettingsView(), isActive: $isGeneralSettingsViewActive) {
                                                Label("设置", systemImage: "gear")
                                        }
                                        NavigationLink(destination: FuzzyPinyinSettingsView(), isActive: $isFuzzyPinyinSettingsViewActive) {
                                                Label("模糊音", systemImage: "speaker.wave.2")
                                        }
                                        NavigationLink(destination: HelpView(), isActive: $isHelpViewActive) {
                                                Label("帮助", systemImage: "keyboard")
                                        }
                                        NavigationLink(destination: AboutView(), isActive: $isAboutViewActive) {
                                                Label("关于", systemImage: "info.circle")
                                        }
                                }
                                .listStyle(.sidebar)
                                .frame(minWidth: 150)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
        }

        @ViewBuilder
        private var detailView: some View {
                ScrollView {
                        switch selection {
                        case .general:
                                GeneralSettingsView()
                        case .fuzzyPinyin:
                                FuzzyPinyinSettingsView()
                        case .help:
                                HelpView()
                        case .about:
                                AboutView()
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
}

#Preview {
        SettingsView()
}

enum SettingsSidebarRow: Int, Hashable, Identifiable, CaseIterable {
        case general
        case fuzzyPinyin
        case help
        case about
        var id: Int {
                return rawValue
        }
}
