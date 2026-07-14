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

        // MARK: - Default input mode on activation

        /// 切换到本输入法时的默认模式（中文 / 英文）
        private(set) static var defaultInputModeOnActivation: InputMethodMode = {
                let savedValue: Int = UserDefaults.standard.integer(forKey: SettingsKey.DefaultInputModeOnActivation)
                switch savedValue {
                case 2:
                        return .abc
                case 0, 1:
                        return .mandarin
                default:
                        return .mandarin
                }
        }()
        static func updateDefaultInputModeOnActivation(to mode: InputMethodMode) {
                defaultInputModeOnActivation = mode
                UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.DefaultInputModeOnActivation)
        }

        // MARK: - Apps excluded from input mode memory

        /// 这些 app 不会记忆输入法状态，每次激活都回到默认输入模式。
        /// Stored in UserDefaults as a comma-separated bundle-ID list.
        private(set) static var appsExcludedFromInputMemory: [String] = {
                guard let saved = UserDefaults.standard.string(forKey: SettingsKey.AppsExcludedFromInputMemory) else { return [] }
                return saved
                        .split(separator: ",")
                        .map({ $0.trimmingCharacters(in: .whitespaces) })
                        .filter({ !$0.isEmpty })
                        .uniqued()
        }()
        static func isAppExcludedFromInputMemory(_ bundleID: String) -> Bool {
                return appsExcludedFromInputMemory.contains(bundleID)
        }
        static func addAppExcludedFromInputMemory(_ bundleID: String) {
                let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                guard !appsExcludedFromInputMemory.contains(trimmed) else { return }
                appsExcludedFromInputMemory = appsExcludedFromInputMemory + [trimmed]
                persistAppsExcludedFromInputMemory()
        }
        static func removeAppExcludedFromInputMemory(_ bundleID: String) {
                guard appsExcludedFromInputMemory.contains(bundleID) else { return }
                appsExcludedFromInputMemory = appsExcludedFromInputMemory.filter({ $0 != bundleID })
                persistAppsExcludedFromInputMemory()
        }
        private static func persistAppsExcludedFromInputMemory() {
                let joined = appsExcludedFromInputMemory.joined(separator: ",")
                UserDefaults.standard.set(joined, forKey: SettingsKey.AppsExcludedFromInputMemory)
        }

        // MARK: - Context-Aware Punctuation

        /// 是否启用"上下文感知标点（字母后）"：中文标点模式下，紧接在 ASCII 字母后输入
        /// 的标点会使用半角符号；中文之后或刚激活 / 切换光标 / 切到中文模式之后，
        /// 立刻恢复输入法对应的全角中文标点。
        private(set) static var isContextAwarePunctuationForLettersEnabled: Bool = {
                // Backward compatibility: use old setting if new ones don't exist
                let oldSavedValue = UserDefaults.standard.integer(forKey: SettingsKey.ContextAwarePunctuation)
                let newSavedValue = UserDefaults.standard.integer(forKey: SettingsKey.ContextAwarePunctuationForLetters)
                if newSavedValue != 0 {
                        // New setting exists, use it
                        switch newSavedValue {
                        case 2:
                                return false
                        case 1:
                                return true
                        default:
                                return true
                        }
                } else if oldSavedValue != 0 {
                        // Fall back to old setting
                        switch oldSavedValue {
                        case 2:
                                return false
                        case 0, 1:
                                return true
                        default:
                                return true
                        }
                } else {
                        // Default
                        return true
                }
        }()
        static func updateContextAwarePunctuationForLetters(to isOn: Bool) {
                isContextAwarePunctuationForLettersEnabled = isOn
                let value: Int = isOn ? 1 : 2
                UserDefaults.standard.set(value, forKey: SettingsKey.ContextAwarePunctuationForLetters)
        }

        /// 是否启用"上下文感知标点（数字后）"：中文标点模式下，紧接在 ASCII 数字后输入
        /// 的标点会使用半角符号；中文之后或刚激活 / 切换光标 / 切到中文模式之后，
        /// 立刻恢复输入法对应的全角中文标点。
        private(set) static var isContextAwarePunctuationForNumbersEnabled: Bool = {
                // Backward compatibility: use old setting if new ones don't exist
                let oldSavedValue = UserDefaults.standard.integer(forKey: SettingsKey.ContextAwarePunctuation)
                let newSavedValue = UserDefaults.standard.integer(forKey: SettingsKey.ContextAwarePunctuationForNumbers)
                if newSavedValue != 0 {
                        // New setting exists, use it
                        switch newSavedValue {
                        case 2:
                                return false
                        case 1:
                                return true
                        default:
                                return true
                        }
                } else if oldSavedValue != 0 {
                        // Fall back to old setting
                        switch oldSavedValue {
                        case 2:
                                return false
                        case 0, 1:
                                return true
                        default:
                                return true
                        }
                } else {
                        // Default
                        return true
                }
        }()
        static func updateContextAwarePunctuationForNumbers(to isOn: Bool) {
                isContextAwarePunctuationForNumbersEnabled = isOn
                let value: Int = isOn ? 1 : 2
                UserDefaults.standard.set(value, forKey: SettingsKey.ContextAwarePunctuationForNumbers)
        }

        // MARK: - Caps Lock to Mandarin

        /// 是否使用 Caps Lock 键切换到中文输入
        private(set) static var useCapsLockForMandarin: Bool = {
                let savedValue: Int = UserDefaults.standard.integer(forKey: SettingsKey.UseCapsLockForMandarin)
                switch savedValue {
                case 2:
                        return true
                case 0, 1:
                        return false
                default:
                        return false
                }
        }()
        static func updateUseCapsLockForMandarin(to isOn: Bool) {
                useCapsLockForMandarin = isOn
                let value: Int = isOn ? 2 : 1
                UserDefaults.standard.set(value, forKey: SettingsKey.UseCapsLockForMandarin)
        }

        // MARK: - Auto Switch Back From System ABC

        /// 系统输入法源被切到系统自带的「ABC」键盘布局时，自动切回本输入法。
        private(set) static var isAutoSwitchFromSystemABCEnabled: Bool = {
                let savedValue: Int = UserDefaults.standard.integer(forKey: SettingsKey.AutoSwitchFromSystemABC)
                switch savedValue {
                case 2:
                        return false
                case 0, 1:
                        return true
                default:
                        return true
                }
        }()
        static func updateAutoSwitchFromSystemABC(to isOn: Bool) {
                isAutoSwitchFromSystemABCEnabled = isOn
                let value: Int = isOn ? 1 : 2
                UserDefaults.standard.set(value, forKey: SettingsKey.AutoSwitchFromSystemABC)
        }
}

struct SettingsKey {
        static let CandidatePageSize: String = "CandidatePageSize"
        static let EnabledCommentLanguages: String = "EnabledCommentLanguages"
        static let PrimaryCommentLanguage: String = "PrimaryCommentLanguage"
        static let UserLexiconInputMemory: String = "UserLexiconInputMemory"
        static let WhisperModelPath: String = "WhisperModelPath"
        static let LlamaModelPath: String = "LlamaModelPath"
        static let DefaultInputModeOnActivation: String = "DefaultInputModeOnActivation"
        static let UseCapsLockForMandarin: String = "UseCapsLockForMandarin"
        static let AppsExcludedFromInputMemory: String = "AppsExcludedFromInputMemory"
        static let ContextAwarePunctuation: String = "ContextAwarePunctuation"
        static let ContextAwarePunctuationForLetters: String = "ContextAwarePunctuationForLetters"
        static let ContextAwarePunctuationForNumbers: String = "ContextAwarePunctuationForNumbers"
        static let AutoSwitchFromSystemABC: String = "AutoSwitchFromSystemABC"
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
