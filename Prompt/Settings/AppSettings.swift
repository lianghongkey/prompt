import Foundation
import CoreIME

@MainActor
struct AppSettings: Sendable {

        /// Translations
        static let commentLanguages: [Language] = [.English]

        private static let defaultEnabledCommentLanguages: [Language] = commentLanguages

        /// Translations
        private(set) static var enabledCommentLanguages: [Language] = {
                guard let savedValue = UserDefaults.standard.string(forKey: SettingsKey.EnabledCommentLanguages) else { return defaultEnabledCommentLanguages }
                let languageValues: [String] = savedValue.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter(\.isNotEmpty)
                guard languageValues.isNotEmpty else { return [] }
                let languages: [Language] = languageValues.compactMap({ Language.language(of: $0) }).uniqued()
                return commentLanguages.filter({ languages.contains($0) })
        }()
        static func updateCommentLanguage(_ language: Language, shouldEnable: Bool) {
                let newLanguages: [Language] = enabledCommentLanguages + [language]
                let handledNewLanguages: [Language] = newLanguages.compactMap({ item -> Language? in
                        guard item == language else { return item }
                        guard shouldEnable else { return nil }
                        return item
                })
                enabledCommentLanguages = handledNewLanguages.uniqued()
                let newText: String = enabledCommentLanguages.map(\.name).joined(separator: ",")
                UserDefaults.standard.set(newText, forKey: SettingsKey.EnabledCommentLanguages)
        }

        private(set) static var primaryCommentLanguage: Language = {
                guard let savedValue = UserDefaults.standard.string(forKey: SettingsKey.PrimaryCommentLanguage) else { return .English }
                let name: String = savedValue.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .controlCharacters)
                guard let language = Language.language(of: name) else { return .English }
                return language
        }()
        static func updatePrimaryCommentLanguage(to language: Language) {
                primaryCommentLanguage = language
                let value: String = language.name
                UserDefaults.standard.set(value, forKey: SettingsKey.PrimaryCommentLanguage)
        }

        /// Candidate count per page
        private(set) static var candidatePageSize: Int = {
                let savedValue: Int = UserDefaults.standard.integer(forKey: SettingsKey.CandidatePageSize)
                let isSavedValueValid: Bool = pageSizeValidity(of: savedValue)
                guard isSavedValueValid else { return defaultCandidatePageSize }
                return savedValue
        }()
        static func updateCandidatePageSize(to newPageSize: Int) {
                let isNewPageSizeValid: Bool = pageSizeValidity(of: newPageSize)
                guard isNewPageSizeValid else { return }
                candidatePageSize = newPageSize
                UserDefaults.standard.set(newPageSize, forKey: SettingsKey.CandidatePageSize)
        }
        private static func pageSizeValidity(of value: Int) -> Bool {
                return candidatePageSizeRange.contains(value)
        }
        private static let defaultCandidatePageSize: Int = 7
        static let candidatePageSizeRange: Range<Int> = 1..<11

        private(set) static var isInputMemoryOn: Bool = {
                let savedValue: Int = UserDefaults.standard.integer(forKey: SettingsKey.UserLexiconInputMemory)
                switch savedValue {
                case 0, 1:
                        return true
                case 2:
                        return false
                default:
                        return true
                }
        }()
        static func updateInputMemory(to isOn: Bool) {
                isInputMemoryOn = isOn
                let value: Int = isOn ? 1 : 2
                UserDefaults.standard.set(value, forKey: SettingsKey.UserLexiconInputMemory)
        }

        /// Example: 1.0.1 (23)
        static let version: String = {
                let marketingVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "version_not_found"
                let currentProjectVersion: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "build_not_found"
                return marketingVersion + " (" + currentProjectVersion + ")"
        }()

        /// Whisper model path (.mlmodelc). Empty string means voice recognition is disabled.
        private(set) static var whisperModelPath: String = {
                UserDefaults.standard.string(forKey: SettingsKey.WhisperModelPath) ?? ""
        }()
        static func updateWhisperModelPath(to path: String) {
                whisperModelPath = path
                UserDefaults.standard.set(path, forKey: SettingsKey.WhisperModelPath)
        }

        /// Current whisper model load state. Updated by VoiceRecorder; read by GeneralSettingsView on init.
        static var whisperModelLoadState: WhisperModelLoadState = {
                whisperModelPath.isEmpty ? .notConfigured : .loading
        }()

        /// Settings Window
        private(set) static var selectedSettingsSidebarRow: SettingsSidebarRow = .general
        static func updateSelectedSettingsSidebarRow(to row: SettingsSidebarRow) {
                selectedSettingsSidebarRow = row
        }

        static let PromptSettingsWindowIdentifierPrefix: String = "PromptSettingsWindowIdentifierPrefix"

        // MARK: - Corrector (llama.cpp server)

        /// Path to llama-server executable
        private(set) static var llamaServerPath: String = {
                UserDefaults.standard.string(forKey: SettingsKey.LlamaServerPath) ?? ""
        }()
        static func updateLlamaServerPath(to path: String) {
                llamaServerPath = path
                UserDefaults.standard.set(path, forKey: SettingsKey.LlamaServerPath)
        }

        /// Path to GGUF model file
        private(set) static var llamaModelPath: String = {
                UserDefaults.standard.string(forKey: SettingsKey.LlamaModelPath) ?? ""
        }()
        static func updateLlamaModelPath(to path: String) {
                llamaModelPath = path
                UserDefaults.standard.set(path, forKey: SettingsKey.LlamaModelPath)
        }

        /// Current corrector server state. Updated by CorrectorEngine; read by GeneralSettingsView.
        static var correctorServerState: CorrectorServerState = .notConfigured
}

struct SettingsKey {
        static let CandidatePageSize: String = "CandidatePageSize"
        static let EnabledCommentLanguages: String = "EnabledCommentLanguages"
        static let PrimaryCommentLanguage: String = "PrimaryCommentLanguage"
        static let UserLexiconInputMemory: String = "UserLexiconInputMemory"
        static let WhisperModelPath: String = "WhisperModelPath"
        static let LlamaServerPath: String = "LlamaServerPath"
        static let LlamaModelPath: String = "LlamaModelPath"
}

extension Notification.Name {
        static let whisperModelPathDidChange = Notification.Name("hk.eduhk.inputmethod.Prompt.whisperModelPathDidChange")
        static let whisperModelLoadStateDidChange = Notification.Name("hk.eduhk.inputmethod.Prompt.whisperModelLoadStateDidChange")
        static let correctorServerStateDidChange = Notification.Name("hk.eduhk.inputmethod.Prompt.correctorServerStateDidChange")
        static let correctorPathsDidChange = Notification.Name("hk.eduhk.inputmethod.Prompt.correctorPathsDidChange")
}

enum WhisperModelLoadState: String {
        case notConfigured
        case loading
        case loaded
        case failed
}

enum CorrectorServerState: String {
        case notConfigured
        case starting
        case running
        case stopped
        case failed
}

extension Language {
        var isEnabledCommentLanguage: Bool {
                return AppSettings.enabledCommentLanguages.contains(self)
        }
        var isPrimaryCommentLanguage: Bool {
                return self == AppSettings.primaryCommentLanguage
        }
}
