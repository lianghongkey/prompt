import AppKit
import InputMethodKit
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

        static let shared: AppDelegate = AppDelegate()

        private override init() {
                super.init()
        }

        private lazy var imkServer: IMKServer? = nil
        private var appActivationObserver: NSObjectProtocol?
        private var voiceModelObserver: NSObjectProtocol?

        func applicationDidFinishLaunching(_ notification: Notification) {
                let name: String = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String) ?? "hk.eduhk.inputmethod.Prompt_Connection"
                let identifier: String = Bundle.main.bundleIdentifier ?? "hk.eduhk.inputmethod.Prompt"
                imkServer = IMKServer(name: name, bundleIdentifier: identifier)
                setupInputSourceMonitor()
                setupVoiceModel()
        }

        // Voice-model loading is driven from here (app-level), not from a controller, so it
        // works even when the Settings toggle is flipped before the IME has been activated in
        // any text field. Otherwise the Settings panel would sit at "加载中" forever because
        // nothing ever called reload().
        private func setupVoiceModel() {
                if voiceModelObserver == nil {
                        voiceModelObserver = NotificationCenter.default.addObserver(
                                forName: .voiceModelDidChange,
                                object: nil,
                                queue: .main
                        ) { _ in
                                PromptInputController.reloadVoiceModel()
                        }
                }
                // Preload at launch if the user has voice recognition enabled, so it is ready
                // before first use and the Settings panel reflects the real load state.
                if AppSettings.isVoiceRecognitionEnabled {
                        PromptInputController.reloadVoiceModel()
                }
        }

        func applicationWillTerminate(_ notification: Notification) {
                // Block until any in-progress voice-model load / transcription on the
                // voice queue finishes before the process tears down.
                voiceQueue.sync { }
        }

        private static let systemABCInputSourceID: String = "com.apple.keylayout.ABC"

        // 有些 App 会记住"上次在这里用的是系统自带 ABC"，切过去时就带着 ABC 一起生效。
        // TISSelectInputSource 只能更新"系统当前选中源"，不会让已经拿到焦点、且已经用
        // 旧输入法建立好连接的窗口重新绑定——那个绑定只在一次真正的 focus 切换时才会
        // 刷新。所以要在 focus 切换"发生的同一时刻"把源改回来，让新激活的窗口自己的
        // activate 周期读到正确的源，而不是等发现改错了再事后补救（事后补救对已经
        // 聚焦的窗口不起作用）。这正是同类 App 级输入法切换工具的做法。
        private func setupInputSourceMonitor() {
                guard appActivationObserver == nil else { return }
                appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                        forName: NSWorkspace.didActivateApplicationNotification,
                        object: nil,
                        queue: .main
                ) { _ in
                        Task { @MainActor in
                                Self.correctInputSourceIfNeeded()
                        }
                }
        }

        private static func correctInputSourceIfNeeded() {
                guard AppSettings.isAutoSwitchFromSystemABCEnabled else { return }
                guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
                guard let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return }
                let currentID = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
                guard currentID == systemABCInputSourceID else { return }
                Logger.shared.debug("autoSwitchFromABC: activated app is on ABC, switching back to Prompt")
                CommandLine.selectPromptInputSource()
        }
}

extension CommandLine {
        static func handleArguments() {
                let shouldInstall: Bool = CommandLine.arguments.contains("install")
                guard shouldInstall else { return }
                register()
                activate()
                NSRunningApplication.current.terminate()
                exit(0)
        }
        private static func register() {
                let path = "/Library/Input Methods/Prompt.app"
                let url = FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : Bundle.main.bundleURL
                TISRegisterInputSource(url as CFURL)
        }
        // Install-time only: enabling re-triggers macOS's "允许启用输入法" consent
        // dialog, so this must never run from the runtime auto-switch path below.
        private static func activate() {
                withEachPromptInputSource { TISEnableInputSource($0); TISSelectInputSource($0) }
        }
        // Runtime auto-switch: Prompt is already enabled (it was just the active
        // input method before being switched away), so only select — calling
        // TISEnableInputSource here would re-prompt the user every time.
        static func selectPromptInputSource() {
                withEachPromptInputSource { TISSelectInputSource($0) }
        }
        private static func withEachPromptInputSource(_ body: (TISInputSource) -> Void) {
                let kInputSourceID: String = "hk.eduhk.inputmethod.Prompt"
                let kInputModeID: String = "hk.eduhk.inputmethod.Prompt.PromptIM"
                guard let inputSourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as? [TISInputSource] else { return }
                for inputSource in inputSourceList {
                        guard let pointer = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
                        let inputSourceID = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
                        guard inputSourceID == kInputSourceID || inputSourceID == kInputModeID else { continue }
                        body(inputSource)
                }
        }
}

extension Logger {
        static let shared: Logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "inputmethod")
}
