import SwiftUI

struct SettingsView: View {

        // macOS 13.0+
        @State private var selection: SettingsSidebarRow = AppSettings.selectedSettingsSidebarRow

        // macOS 12
        @State private var isGeneralSettingsViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .general
        @State private var isFuzzyPinyinSettingsViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .fuzzyPinyin
        @State private var isAboutViewActive: Bool = AppSettings.selectedSettingsSidebarRow == .about

        var body: some View {
                if #available(macOS 13.0, *) {
                        NavigationSplitView {
                                List(selection: $selection) {
                                        Label("设置", systemImage: "gear").tag(SettingsSidebarRow.general)
                                        Label("模糊音", systemImage: "speaker.wave.2").tag(SettingsSidebarRow.fuzzyPinyin)
                                        Label("关于", systemImage: "info.circle").tag(SettingsSidebarRow.about)
                                }
                                .frame(minWidth: 150, maxWidth: 200)
                        } detail: {
                                detailView
                        }
                        .navigationSplitViewStyle(.balanced)
                        .frame(minWidth: 600, minHeight: 400)
                } else {
                        NavigationView {
                                List {
                                        NavigationLink(destination: GeneralSettingsView(), isActive: $isGeneralSettingsViewActive) {
                                                Label("设置", systemImage: "gear")
                                        }
                                        NavigationLink(destination: FuzzyPinyinSettingsView(), isActive: $isFuzzyPinyinSettingsViewActive) {
                                                Label("模糊音", systemImage: "speaker.wave.2")
                                        }
                                        NavigationLink(destination: AboutView(), isActive: $isAboutViewActive) {
                                                Label("关于", systemImage: "info.circle")
                                        }
                                }
                                .listStyle(.sidebar)
                                .frame(minWidth: 150, maxWidth: 200)
                        }
                        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .topLeading)
                }
        }

        @ViewBuilder
        private var detailView: some View {
                switch selection {
                case .general:
                        GeneralSettingsView()
                case .fuzzyPinyin:
                        FuzzyPinyinSettingsView()
                case .about:
                        AboutView()
                }
        }
}

#Preview {
        SettingsView()
}

enum SettingsSidebarRow: Int, Hashable, Identifiable, CaseIterable {
        case general
        case fuzzyPinyin
        case about
        var id: Int {
                return rawValue
        }
}
