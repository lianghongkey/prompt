import SwiftUI
import InputMethodKit
import AVFoundation
import os.log
import CoreIME

@MainActor
final class PromptInputController: IMKInputController, Sendable {

        // MARK: - Window, InputClient

        private lazy var logger = Logger.shared

        /// NSPanel for CandidateBoard and OptionsView
        private lazy var window = CandidateWindow.shared

        private func prepareWindow() {
                // Always use CGShieldingWindowLevel so the candidate window stays above
                // host popovers (Safari URL suggestions = NSPopUpMenuWindowLevel/101,
                // autocomplete dropdowns, tooltips). The previous heuristic of
                // `client.windowLevel() + 1` ended up at level 20 for Safari's address
                // bar, which let the URL-suggestion popover (level 101) cover us.
                window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
                // Bind the shared window's contentViewController to the shared
                // AppContext exactly once. Re-creating NSHostingController per activate
                // both wastes work and (when multiple controllers race) could leave the
                // window bound to a stale empty AppContext.
                if window.contentViewController == nil {
                        window.contentViewController = NSHostingController(rootView: MotherBoard().environmentObject(appContext))
                }
                window.orderFrontRegardless()
        }
        private func updateWindowFrame(_ frame: CGRect? = nil) {
                refreshQuadrant()
                let resolved = frame ?? windowFrame
                window.setFrame(resolved, display: true)
                // Re-assert z-order on every non-zero frame update. Hosts can place
                // popovers (e.g. Safari URL suggestions, autocomplete dropdowns) above
                // us between activateServer and the user's first keystroke. Without
                // this, our candidate window stays below them and looks invisible.
                if !resolved.isEmpty {
                        window.orderFrontRegardless()
                }
        }
        private func isValidCursorBlock(_ rect: CGRect) -> Bool {
                guard rect.height > 0 else { return false }
                let origin = rect.origin
                return (origin.x >= screenOrigin.x) && (origin.x < maxPointX) && (origin.y >= screenOrigin.y) && (origin.y < maxPointY)
        }

        private func resolvedCursorBlock() -> CGRect? {
                if let cached = currentCursorBlock, isValidCursorBlock(cached) { return cached }
                if let fresh = currentClient?.cursorBlock, isValidCursorBlock(fresh) {
                        currentCursorBlock = fresh
                        return fresh
                }
                return nil
        }

        /// Decide which quadrant to grow the candidate window into, based on remaining screen space around the caret.
        private func quadrant(forCursorOrigin position: CGPoint) -> Quadrant {
                let isPositiveHorizontal: Bool = (maxPointX - position.x) > 300
                let isPositiveVertical: Bool = (position.y - screenOrigin.y) < 300
                return switch (isPositiveHorizontal, isPositiveVertical) {
                case (true, true): .upperRight
                case (false, true): .upperLeft
                case (true, false): .bottomRight
                case (false, false): .bottomLeft
                }
        }

        /// Re-evaluate quadrant on every frame update so the window flips when the caret crosses near a screen edge while typing.
        private func refreshQuadrant() {
                guard let cursorBlock = resolvedCursorBlock() else { return }
                let newQuadrant = quadrant(forCursorOrigin: cursorBlock.origin)
                if newQuadrant != appContext.quadrant {
                        appContext.updateQuadrant(to: newQuadrant)
                }
        }

        private var windowFrame: CGRect {
                let quadrant = appContext.quadrant
                let position: CGPoint = {
                        guard let cursorBlock = resolvedCursorBlock() else {
                                return NSEvent.mouseLocation
                        }
                        let x: CGFloat = quadrant.isNegativeHorizontal ? cursorBlock.origin.x : cursorBlock.maxX
                        let y: CGFloat = quadrant.isNegativeVertical ? cursorBlock.origin.y : cursorBlock.maxY
                        return CGPoint(x: x, y: y)
                }()
                let width: CGFloat = 800
                let height: CGFloat = 300
                let rawX: CGFloat = quadrant.isNegativeHorizontal ? (position.x - width) : position.x
                let rawY: CGFloat = quadrant.isNegativeVertical ? (position.y - height) : position.y
                // Final safety clamp so the panel never goes off-screen, even if quadrant heuristic underestimates content width.
                let x: CGFloat = min(max(rawX, screenOrigin.x), maxPointX - width)
                let y: CGFloat = min(max(rawY, screenOrigin.y), maxPointY - height)
                return CGRect(x: x, y: y, width: width, height: height)
        }

        private var screenOrigin: CGPoint { NSScreen.main?.frame.origin ?? window.screen?.frame.origin ?? .zero }
        private var screenSize: CGSize { NSScreen.main?.frame.size ?? window.screen?.frame.size ?? CGSize(width: 1280, height: 800) }
        private var maxPointX: CGFloat { screenOrigin.x + screenSize.width }
        private var maxPointY: CGFloat { screenOrigin.y + screenSize.height }
        private var maxPoint: CGPoint { CGPoint(x: maxPointX, y: maxPointY) }
        private lazy var currentCursorBlock: CGRect? = nil
        private func updateCurrentCursorBlock(to rect: CGRect?) {
                guard let rect = rect, isValidCursorBlock(rect) else {
                        return
                }
                currentCursorBlock = rect
        }
        /// Force-clear the cached cursor block. Call on composition end / focus change
        /// so a stale cache from the previous composition can't position the next
        /// candidate window at an off-screen / wrong location when the new client
        /// transiently returns an invalid cursorBlock (common in Safari / WebKit).
        private func clearCurrentCursorBlock() {
                currentCursorBlock = nil
        }

        private typealias InputClient = (IMKTextInput & NSObjectProtocol)
        private lazy var currentClient: InputClient? = nil {
                didSet {
                        let position: CGPoint = {
                                guard let point = currentClient?.cursorBlock.origin else { return screenOrigin }
                                guard (point.x >= screenOrigin.x) && (point.x < maxPointX) && (point.y >= screenOrigin.y) && (point.y < maxPointY) else { return screenOrigin }
                                return point
                        }()
                        let newQuadrant = quadrant(forCursorOrigin: position)
                        if newQuadrant != appContext.quadrant {
                                appContext.updateQuadrant(to: newQuadrant)
                        }
                }
        }


        // MARK: - Input Server lifecycle

        override init() {
                super.init()
                activateServer(client())
        }
        override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
                super.init(server: server, delegate: delegate, client: inputClient)
                let currentInputClient: InputClient? = (inputClient as? InputClient) ?? client()
                activateServer(currentInputClient)
        }
        override func activateServer(_ sender: Any!) {
                super.activateServer(sender)
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient) ?? client()
                Task { @MainActor in
                        UserLexicon.prepare()
                        Engine.prepare()
                        if inputStage.isBuffering {
                                clearBufferText()
                        }
                        inputStage = .standby
                        isPunctuationFullWidth = true
                        clearShiftTapState()
                        updateInputForm(to: Self.resolveInitialInputForm(client: client))
                        // Seed the focus-change tracker so the per-event sync in handle()
                        // doesn't fire spuriously on the first event after activate.
                        lastObservedWindowKey = Self.frontmostWindowKey(for: client)
                        currentClient = client
                        // Try to update cursor from new client; if invalid, keep last known good position
                        if let block = client?.cursorBlock, isValidCursorBlock(block) {
                                currentCursorBlock = block
                        }
                        prepareWindow()
                        client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
                        // Set up transcription callback for the currently active controller
                        Self.sharedVoiceRecorder.onTranscription = { [weak self] text in
                                self?.insertTranscribedText(text)
                        }
                        // Trigger model loading if not already loaded or currently loading
                        if AppSettings.isVoiceRecognitionEnabled && !Self.sharedVoiceRecorder.isModelLoaded && !Self.sharedVoiceRecorder.isModelLoading {
                                Self.sharedVoiceRecorder.reload()
                        }
                }
        }
        override func deactivateServer(_ sender: Any!) {
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient) ?? client()
                Task { @MainActor in
                        window.setFrame(.zero, display: true)
                        clearCurrentCursorBlock()
                        selectedCandidates = []
                        selectedNonFirst = false
                        isIntendingToRecord = false
                        isPunctuationFullWidth = true
                        filterText = ""
                        clearShiftTapState()
                        appContext.updateRecordingIndicator(nil)
                        Self.sharedVoiceRecorder.stopRecording()
                        if inputForm.isOptions {
                                updateInputForm()
                        }
                        // Remember this app's current input mode so the next activate can
                        // restore it. Skip excluded apps (always reset to default) and
                        // skip .options (transient — already cleaned up above).
                        if let bundleID = client?.bundleIdentifier(),
                           !inputForm.isOptions,
                           !AppSettings.isAppExcludedFromInputMemory(bundleID) {
                                Self.bundleInputForms[bundleID] = inputForm
                        }
                        lastObservedWindowKey = nil
                        guard inputStage != .idle else { return }
                        if inputStage.isBuffering {
                                clearBufferText()
                        } else {
                                clearMarkedText()
                        }
                        let emptyText = NSAttributedString(string: String(), attributes: markAttributes)
                        let emptyRange = NSRange(location: 0, length: 0)
                        client?.setMarkedText(emptyText, selectionRange: emptyRange, replacementRange: replacementRange())
                        let activatingWindowCount = NSApp.windows.count(where: { $0.windowNumber > 0 })
                        if activatingWindowCount > 20 {
                                logger.warning("Prompt containing more than 20 windows, closing extras")
                                NSApp.windows.filter({ $0 != window }).forEach({ $0.close() })
                        } else if activatingWindowCount > 10 {
                                logger.notice("Prompt containing more than 10 windows")
                        }
                }
                super.deactivateServer(sender)
        }
        override func commitComposition(_ sender: Any!) {
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient) ?? client()
                Task { @MainActor in
                        if inputStage.isBuffering {
                                clearBufferText()
                                let emptyText = NSAttributedString(string: String(), attributes: markAttributes)
                                let emptyRange = NSRange(location: 0, length: 0)
                                client?.setMarkedText(emptyText, selectionRange: emptyRange, replacementRange: replacementRange())
                        }
                        window.setFrame(.zero, display: true)
                        clearCurrentCursorBlock()
                        selectedCandidates = []
                        selectedNonFirst = false
                        clearMarkedText()
                        if inputForm.isOptions {
                                updateInputForm()
                        }
                        inputStage = .idle
                }

                // Do NOT use this line or it will freeze the entire IME
                // super.commitComposition(sender)
        }

        /// 视为"光标移动"的导航键键码集合（用于上下文感知标点重置）：方向键、Home、End、PageUp、PageDown。
        private static let navigationKeyCodes: Set<UInt16> = [
                KeyCode.Arrow.VK_UP,
                KeyCode.Arrow.VK_DOWN,
                KeyCode.Arrow.VK_LEFT,
                KeyCode.Arrow.VK_RIGHT,
                KeyCode.Special.VK_HOME,
                KeyCode.Special.VK_END,
                KeyCode.Special.VK_PAGEUP,
                KeyCode.Special.VK_PAGEDOWN,
        ]

        private static let sharedVoiceRecorder: VoiceRecorder = VoiceRecorder()

        /// (Re)load the shared voice model. Called by AppDelegate — both at launch (when
        /// the toggle is already on) and whenever `.voiceModelDidChange` fires — so loading
        /// does not depend on any controller having been activated in a text field first.
        static func reloadVoiceModel() {
                sharedVoiceRecorder.reload()
        }

        private var isIntendingToRecord: Bool = false

        // Shift-tap IME mode toggle: a clean single-tap of left/right Shift
        // (no other key/modifier in between, < 1.0s hold) switches input mode.
        // Left Shift → ABC (transparent), Right Shift → Mandarin.
        private var pendingShiftKey: UInt16? = nil
        private var shiftDownTime: Date? = nil
        private var shiftTapInvalidated: Bool = false
        // Tracks the previous overall .shift state, so we only react on real transitions
        // and ignore duplicate / no-op flagsChanged events.
        private var wasShiftHeld: Bool = false
        // Tracks the previous Caps Lock state so we only react on real transitions.
        // Synced from the OS on activate to avoid spurious mode switches on first event.
        private var wasCapsLockOn: Bool = false
        private func clearShiftTapState() {
                pendingShiftKey = nil
                shiftDownTime = nil
                shiftTapInvalidated = false
                wasShiftHeld = false
                wasCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        }
        private func switchInputMethodMode(to mode: InputMethodMode) {
                // Runtime-only switch. Do NOT persist to Options — every time the IME
                // is re-activated (e.g. switching back from another input method)
                // we want to start fresh in Mandarin, not remember the last toggled state.
                let newForm: InputForm = mode.isMandarin ? .mandarin : .transparent
                // 切到中文模式时，把上下文感知标点状态拨回"全角"。否则刚刚 ABC 模式下
                // 输入的英文会让 isPunctuationFullWidth 维持为 false，进入中文模式后
                // 第一个标点会意外是半角。
                if mode.isMandarin {
                        isPunctuationFullWidth = true
                }
                updateInputForm(to: newForm)
                // Eagerly mirror to the per-app memory so a sibling instance's
                // activateServer (multi-instance hosts like Safari/Notes/Mail can fire
                // activate on a new instance BEFORE this one's deactivate runs) sees
                // the just-toggled state. Without this the new instance reads stale /
                // missing data and silently reverts to the configured default.
                if let bundleID = (currentClient ?? client())?.bundleIdentifier(),
                   !AppSettings.isAppExcludedFromInputMemory(bundleID) {
                        Self.bundleInputForms[bundleID] = newForm
                }
                logger.debug("switchInputMethodMode (runtime): -> \(String(describing: mode))")
        }

        private func insertTranscribedText(_ text: String) {
                Self.timing.info("T5 insertTranscribedText begin text_len=\(text.count)")
                appContext.updateRecordingIndicator(nil)
                window.setFrame(.zero, display: true)
                let client = currentClient ?? client()
                guard !text.isEmpty else {
                        clearMarkedText()
                        return
                }
                let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
                client?.insertText(simplified as NSString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                Self.timing.info("T10 insertText")
        }

        // SHARED across all controller instances in this IME process. The previous
        // per-instance AppContext caused the candidate window to appear empty in
        // Safari Cmd+T new-tab address-bar input: Safari creates multiple
        // PromptInputController instances during the auto-focus transition, each
        // with its own AppContext. `prepareWindow()` rebinds the shared window's
        // contentViewController to the *current* instance's appContext. If a later
        // activate (different instance, fresh empty appContext) ran after the
        // typing instance set up its content, the visible window pointed at the
        // empty appContext while keystrokes updated a different (now invisible)
        // appContext. Sharing one AppContext makes the binding stable.
        private var appContext: AppContext { Self.sharedAppContext }
        nonisolated(unsafe) private static let sharedAppContext: AppContext = AppContext()
        nonisolated(unsafe) static let timing = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Timing")

        private lazy var inputForm: InputForm = InputForm.matchInputMethodMode()
        // Per-app input mode memory, shared across all controller instances in this IME
        // process. Keyed by host bundle identifier. Apps listed in
        // AppSettings.appsExcludedFromInputMemory are never written to or read from this
        // map — they always use the configured default. .options is never stored.
        private static var bundleInputForms: [String: InputForm] = [:]

        /// Last frontmost-window key seen by this controller. Used by excluded apps to
        /// detect inter-window focus changes (which the host does NOT surface as
        /// activate/deactivate) and reset to default on each detected change.
        private var lastObservedWindowKey: String? = nil

        /// Resolve which InputForm to apply on (re)activation. Priority chain:
        ///   1. Per-app memory — if this host bundle has a saved form from a
        ///      previous deactivate, restore it. Skipped for bundles in the
        ///      "excluded from input memory" list.
        ///   2. User-configured default mode (Settings → 默认输入模式).
        ///
        /// Shift-tap toggles can override the result at any time after activation.
        static func resolveInitialInputForm(client: (IMKTextInput & NSObjectProtocol)?) -> InputForm {
                let bundleID: String? = client?.bundleIdentifier()
                let isExcluded: Bool = bundleID.map(AppSettings.isAppExcludedFromInputMemory) ?? false
                if !isExcluded, let key = bundleID, let stored = bundleInputForms[key] {
                        return stored
                }
                return AppSettings.defaultInputModeOnActivation.isMandarin ? .mandarin : .transparent
        }

        /// Compose a "bundleID:CGWindowID" key for the host's currently-frontmost window,
        /// or just the bundle ID when the window number can't be resolved. Window ID is
        /// derived from `CGWindowListCopyWindowInfo` filtered to the host PID, taking
        /// the first match in front-to-back z-order.
        private static func frontmostWindowKey(for client: InputClient?) -> String? {
                guard let client else { return nil }
                let bundleID: String = client.bundleIdentifier() ?? "unknown"
                guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                        return bundleID
                }
                guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                        return bundleID
                }
                let front = windows.first { window in
                        (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                }
                guard let windowNumber = front?[kCGWindowNumber as String] as? UInt32 else {
                        return bundleID
                }
                return "\(bundleID):\(windowNumber)"
        }

        /// For excluded apps only: detect frontmost-window changes per-event and reset
        /// inputForm to the configured default whenever focus moves to a different
        /// window. Skipped while the user is mid-buffering so we don't interrupt an
        /// in-progress pinyin input.
        private func resetExcludedAppOnFocusChangeIfNeeded(client: InputClient?) {
                let bundle: String? = client?.bundleIdentifier()
                let frontmostBundle: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let excludedList = AppSettings.appsExcludedFromInputMemory
                let bundleMatched: Bool = bundle.map(AppSettings.isAppExcludedFromInputMemory) ?? false
                let frontmostMatched: Bool = frontmostBundle.map(AppSettings.isAppExcludedFromInputMemory) ?? false
                logger.debug("resetCheck: clientBundle=\(bundle ?? "nil"), frontmost=\(frontmostBundle ?? "nil"), excludedList=\(excludedList), bundleMatched=\(bundleMatched), frontmostMatched=\(frontmostMatched)")
                // Match either the client-reported bundle ID or the frontmost-app bundle ID,
                // since some hosts return a delegate/wrapper bundle from client.bundleIdentifier().
                let activeBundle: String? = bundleMatched ? bundle : (frontmostMatched ? frontmostBundle : nil)
                guard let activeBundle else { return }
                let currentKey = Self.frontmostWindowKey(for: client)
                guard currentKey != lastObservedWindowKey else {
                        logger.debug("excluded[\(activeBundle)]: window unchanged (\(currentKey ?? "nil"))")
                        return
                }
                logger.debug("excluded[\(activeBundle)]: window \(self.lastObservedWindowKey ?? "nil") -> \(currentKey ?? "nil"), buffering=\(self.inputStage.isBuffering), inputForm=\(String(describing: self.inputForm))")
                lastObservedWindowKey = currentKey
                guard !inputStage.isBuffering else { return }
                let defaultForm: InputForm = AppSettings.defaultInputModeOnActivation.isMandarin ? .mandarin : .transparent
                if inputForm != defaultForm {
                        updateInputForm(to: defaultForm)
                        logger.debug("excluded[\(activeBundle)]: reset to \(String(describing: defaultForm))")
                }
        }
        func updateInputForm(to form: InputForm? = nil) {
                let newForm = form ?? InputForm.matchInputMethodMode()
                logger.debug("updateInputForm: old=\(String(describing: self.inputForm)), new=\(String(describing: newForm)), Options.inputMethodMode=\(String(describing: Options.inputMethodMode))")
                inputForm = newForm
                appContext.updateInputForm(to: newForm)
        }

        private lazy var inputStage: InputStage = .standby

        private func clearBufferText() {
                filterText = ""
                bufferText = String.empty
                wordCreationCharacters = []
                wordCreationPinyins = []
                wordCreationInputs = []
                isPunctuationFullWidth = true
        }
        private lazy var bufferText: String = .empty {
                willSet {
                        switch (bufferText.isEmpty, newValue.isEmpty) {
                        case (true, true):
                                inputStage = .standby
                        case (true, false):
                                inputStage = .starting
                                UserLexicon.prepare()
                                Engine.prepare()
                        case (false, true):
                                inputStage = .ending
                        case (false, false):
                                inputStage = .ongoing
                        }
                }
                didSet {
                        logger.debug("bufferText.didSet: '\(self.bufferText)' (was '\(oldValue)'), inputStage=\(String(describing: self.inputStage))")
                        switch bufferText.first {
                        case .none:
                                logger.debug("bufferText.didSet: case .none, selectedCandidates.count=\(self.selectedCandidates.count)")
                                if AppSettings.isInputMemoryOn && selectedCandidates.isNotEmpty {
                                        logger.debug("bufferText.didSet: calling UserLexicon.handle")
                                        let concatenated = selectedCandidates.joined()
                                        UserLexicon.handle(concatenated)
                                        logger.debug("bufferText.didSet: UserLexicon.handle completed")
                                }
                                logger.debug("bufferText.didSet: clearing selectedCandidates")
                                selectedCandidates = []
                                selectedNonFirst = false
                                logger.debug("bufferText.didSet: calling clearMarkedText")
                                clearMarkedText()
                                logger.debug("bufferText.didSet: clearMarkedText completed, clearing candidates")
                                candidates = []
                                logger.debug("bufferText.didSet: case .none completed")
                        case .some(let character) where character.isInvalidAnchor:
                                mark(text: bufferText)
                                selectedCandidates = []
                                selectedNonFirst = false
                                candidates = []
                        case .some(let character) where character.isBasicLatinLetter:
                                suggest()
                        case .some(_) where bufferText.count == 1:
                                mark(text: bufferText)
                                candidates = []
                        case .some(.backtick):
                                switch bufferText.dropFirst().first {
                                case .some("p"), .some("r"):
                                        pinyinReverseLookup()
                                default:
                                        mark(text: bufferText)
                                }
                        default:
                                mark(text: bufferText)
                                selectedCandidates = []
                                selectedNonFirst = false
                                candidates = []
                        }
                }
        }

        private func insert(_ text: String) {
                let shouldClearMarkedText: Bool = !(inputStage.isBuffering)
                // let replacementRange = NSRange(location: NSNotFound, length: 0)
                currentClient?.insertText(text as NSString, replacementRange: replacementRange())
                updatePunctuationState(for: text)
                if shouldClearMarkedText {
                        clearMarkedText()
                }
        }
        private func mark(text: String) {
                let attributedText = NSAttributedString(string: text, attributes: markAttributes)
                let selectionRange = NSRange(location: text.utf16.count, length: 0)
                currentClient?.setMarkedText(attributedText, selectionRange: selectionRange, replacementRange: replacementRange())
        }
        /// Mark text with a custom replacement range (used to replace preceding text)
        private func mark(text: String, replacingRange range: NSRange) {
                let attributedText = NSAttributedString(string: text, attributes: markAttributes)
                let selectionRange = NSRange(location: text.utf16.count, length: 0)
                currentClient?.setMarkedText(attributedText, selectionRange: selectionRange, replacementRange: range)
        }
        private func clearMarkedText() {
                let attributedText = NSAttributedString(string: String(), attributes: markAttributes)
                let selectionRange = NSRange(location: 0, length: 0)
                currentClient?.setMarkedText(attributedText, selectionRange: selectionRange, replacementRange: replacementRange())
        }
        private lazy var markAttributes: [NSAttributedString.Key: Any] = {
                let attributes = mark(forStyle: kTSMHiliteSelectedConvertedText, at: replacementRange())
                return (attributes as? [NSAttributedString.Key: Any]) ?? [.underlineStyle: NSUnderlineStyle.thick.rawValue]
        }()
        private func markOptionsViewHintText() {
                guard !(inputStage.isBuffering) else { return }
                mark(text: String.zeroWidthSpace)
        }
        private func clearOptionsViewHintText() {
                guard !(inputStage.isBuffering) else { return }
                clearMarkedText()
        }


        // MARK: - Candidates

        /// Cached Candidate sequence for UserLexicon
        private lazy var selectedCandidates: [Candidate] = []

        /// Whether any candidate was selected from a non-first position.
        /// When false (all selections were the top candidate), skip frequency updates.
        private var selectedNonFirst: Bool = false

        /// 上下文感知标点状态。true（默认）= 全角中文标点；false = 半角英文标点。
        /// 仅当 `AppSettings.isContextAwarePunctuationEnabled` 且
        /// `Options.punctuationForm == .chinese` 时才会改变行为。
        /// 转换规则在 `updatePunctuationState(for:)`：CJK → true，ASCII 字母/数字 → false，
        /// 纯标点不变。Focus 切换 / 键盘移动光标 / 切到 mandarin 模式时一律回到 true。
        private var isPunctuationFullWidth: Bool = true
        private func updatePunctuationState(for text: String) {
                let hasLetters = text.contains(where: { $0.isASCII && $0.isLetter })
                let hasNumbers = text.contains(where: { $0.isASCII && $0.isNumber })
                let hasChinese = text.contains(where: { $0.isChineseCharacter })

                if hasChinese {
                        isPunctuationFullWidth = true
                } else if (hasLetters && AppSettings.isContextAwarePunctuationForLettersEnabled) || (hasNumbers && AppSettings.isContextAwarePunctuationForNumbersEnabled) {
                        isPunctuationFullWidth = false
                }
                // Pure-punctuation insertion leaves the state unchanged
        }
        /// 当 isPunctuationFullWidth=false 时返回 true（用半角），否则全角。
        /// 关掉开关或不在中文标点模式时永远返回 false（让外层走原本的全角分支）。
        private func shouldUseHalfWidthPunctuation() -> Bool {
                guard AppSettings.isContextAwarePunctuationForLettersEnabled || AppSettings.isContextAwarePunctuationForNumbersEnabled else { return false }
                guard Options.punctuationForm.isChineseMode else { return false }
                return !isPunctuationFullWidth
        }

        /// Cross-reference filter: Shift+letter input for filtering candidates by intersection
        private var filterText: String = "" {
                didSet {
                        let indicator: String? = filterText.isEmpty ? nil : filterText
                        appContext.updateFilterIndicator(indicator)
                }
        }
        private var isFiltering: Bool { filterText.isNotEmpty }

        /// Word creation state: tracks characters being composed
        private lazy var wordCreationCharacters: [String] = []
        private lazy var wordCreationPinyins: [String] = []
        /// Tracks the consumed pinyin input at each word creation step (for backspace undo)
        private lazy var wordCreationInputs: [String] = []

        private lazy var candidates: [Candidate] = [] {
                didSet {
                        updateDisplayCandidates(.establish, highlight: .start)
                }
        }

        /// DisplayCandidates indices
        private lazy var indices: (first: Int, last: Int) = (0, 0)

        private func updateDisplayCandidates(_ transformation: PageTransformation, highlight: Highlight) {
                let candidateCount: Int = candidates.count
                guard candidateCount > 0 else {
                        indices = (0, 0)
                        appContext.resetDisplayContext()
                        if isFiltering {
                                updateWindowFrame()
                        } else {
                                updateWindowFrame(.zero)
                        }
                        return
                }
                let pageSize: Int = AppSettings.candidatePageSize
                let newFirstIndex: Int? = {
                        switch transformation {
                        case .establish:
                                return 0
                        case .previousPage:
                                let oldFirstIndex: Int = indices.first
                                guard oldFirstIndex > 0 else { return nil }
                                return max(0, oldFirstIndex - pageSize)
                        case .nextPage:
                                let oldLastIndex: Int = indices.last
                                let maxIndex: Int = candidateCount - 1
                                guard oldLastIndex < maxIndex else { return nil }
                                return oldLastIndex + 1
                        }
                }()
                guard let firstIndex: Int = newFirstIndex else { return }
                let bound: Int = min(firstIndex + pageSize, candidateCount)
                indices = (firstIndex, bound - 1)
                updateWindowFrame()
                let newDisplayCandidates = (firstIndex..<bound).map({ index -> DisplayCandidate in
                        return DisplayCandidate(candidate: candidates[index], candidateIndex: index)
                })
                appContext.update(with: newDisplayCandidates, highlight: highlight)
        }


        // MARK: - Candidate Suggestions

        private func suggest() {
                let processingText: String = bufferText
                let needsSymbols: Bool = Options.isEmojiSuggestionsOn && selectedCandidates.isEmpty
                let isInputMemoryOn: Bool = AppSettings.isInputMemoryOn
                let segmentation = PinyinSegmentor.segment(text: processingText)

                // Debug: log segmentation
                if let first = segmentation.first {
                    let origins = first.map(\.origin).joined(separator: " ")
                    let texts = first.map(\.text).joined(separator: " ")
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Segmentation"), "Input: %{public}@, Origins: %{public}@, Texts: %{public}@", processingText, origins, texts)
                }

                let bestScheme = segmentation.first
                let userLexiconCandidates: [Candidate] = isInputMemoryOn ? UserLexicon.suggest(text: processingText, segmentation: segmentation) : []
                let engineCandidates: [Candidate] = Engine.suggest(text: processingText, segmentation: segmentation, needsSymbols: needsSymbols)

                // Debug logging
                if processingText == "bushi" {
                    NSLog("=== DEBUG: Input '\(processingText)' ===")
                    NSLog("UserLexicon: \(userLexiconCandidates.count) candidates")
                    for (i, c) in userLexiconCandidates.prefix(5).enumerated() {
                        NSLog("  UL[\(i)] \(c.text) (\(c.romanization)) input=\(c.input) mark=\(c.mark) fuzzy=\(c.isFuzzyMatch)")
                    }
                    NSLog("Engine: \(engineCandidates.count) candidates")
                    for (i, c) in engineCandidates.prefix(10).enumerated() {
                        NSLog("  EN[\(i)] \(c.text) (\(c.romanization)) input=\(c.input) mark=\(c.mark) fuzzy=\(c.isFuzzyMatch)")
                    }
                }

                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "=== Input: %{public}@ ===", processingText)
                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "UserLexicon: %d candidates", userLexiconCandidates.count)
                for (i, c) in userLexiconCandidates.prefix(5).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "  UL[%d] %{public}@ (%{public}@) input=%{public}@ mark=%{public}@ fuzzy=%d", i, c.text, c.romanization, c.input, c.mark, c.isFuzzyMatch ? 1 : 0)
                }
                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "Engine: %d candidates", engineCandidates.count)
                for (i, c) in engineCandidates.prefix(10).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "  EN[%d] %{public}@ (%{public}@) input=%{public}@ mark=%{public}@ fuzzy=%d", i, c.text, c.romanization, c.input, c.mark, c.isFuzzyMatch ? 1 : 0)
                }

                let suggestions: [Candidate] = {
                        let combined = (userLexiconCandidates + engineCandidates).sortedWithFullMatchFirst(fullInputLength: processingText.count)
                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "Combined: %d candidates", combined.count)
                        let hasUserLexicon = userLexiconCandidates.isNotEmpty
                        if hasUserLexicon {
                                // When user lexicon is present, deduplicate by text only to avoid showing
                                // multiple entries like "不是 (bushi)" from user lexicon and "不是 (bu shi)" from engine
                                var seen = Set<String>()
                                let deduped = combined.compactMap({ candidate -> Candidate? in
                                        guard !candidate.isCompound else { return nil }
                                        let key = candidate.text
                                        guard seen.insert(key).inserted else { return nil }
                                        return candidate
                                })
                                return deduped
                        } else {
                                // Always deduplicate to avoid showing duplicate candidates from different query paths
                                let uniqued = combined.uniqued()
                                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "After uniqued: %d -> %d", combined.count, uniqued.count)
                                return uniqued
                        }
                }()

                // Add single-character candidates at the end for word creation
                let suggestionsWithSingleChars: [Candidate] = {
                        guard let scheme = bestScheme, scheme.count >= 2 else { return suggestions }

                        // Get single character candidates for the first syllable
                        let firstSyllable = scheme.first!
                        let firstPinyin = firstSyllable.origin
                        let singleChars = Engine.suggest(text: firstPinyin, segmentation: [[firstSyllable]], needsSymbols: false)
                                .filter({ $0.text.count == 1 && $0.isMandarin })

                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "SingleChars for '%{public}@': %d candidates", firstPinyin, singleChars.count)

                        // Only add if not already present
                        var result = suggestions
                        for singleChar in singleChars {
                                if !result.contains(where: { $0.text == singleChar.text && $0.romanization == singleChar.romanization }) {
                                        result.append(singleChar)
                                } else {
                                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "  Skipping duplicate: %{public}@ (%{public}@)", singleChar.text, singleChar.romanization)
                                }
                        }
                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "After adding single chars: %d -> %d", suggestions.count, result.count)
                        return result
                }()

                let wordCreationPrefix = wordCreationCharacters.joined()
                mark(text: {
                        let hasSeparatorsOrTones: Bool = processingText.contains(where: \.isSeparatorOrTone)
                        guard !hasSeparatorsOrTones else { return wordCreationPrefix + processingText.formattedForMark() }
                        let userInputTextCount: Int = processingText.count
                        if let firstCandidate = suggestionsWithSingleChars.first, firstCandidate.input.count == userInputTextCount { return wordCreationPrefix + firstCandidate.mark }
                        guard let bestScheme else { return wordCreationPrefix + processingText.formattedForMark() }
                        let leadingLength: Int = bestScheme.length
                        let leadingText: String = bestScheme.map(\.text).joined()
                        guard leadingLength != userInputTextCount else { return wordCreationPrefix + leadingText }
                        let tailText = processingText.dropFirst(leadingLength)
                        return wordCreationPrefix + leadingText + tailText
                }())

                if processingText == "bushi" {
                    NSLog("Final candidates: \(suggestionsWithSingleChars.count)")
                    for (i, c) in suggestionsWithSingleChars.prefix(10).enumerated() {
                        NSLog("  FINAL[\(i)] \(c.text) (\(c.romanization))")
                    }
                }

                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "Final candidates: %d", suggestionsWithSingleChars.count)
                for (i, c) in suggestionsWithSingleChars.prefix(10).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Candidates"), "  FINAL[%d] %{public}@ (%{public}@)", i, c.text, c.romanization)
                }

                if isFiltering {
                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "CrossFilter"), "suggest: isFiltering=true, filterText=%{public}@, original=%d", self.filterText, suggestionsWithSingleChars.count)
                        candidates = filterCandidates(suggestionsWithSingleChars)
                } else {
                        candidates = suggestionsWithSingleChars
                }
        }

        // MARK: - Cross-Reference Filter

        /// Cross-reference filter: use filterText to find the common syllable between
        /// bufferText and filterText, then return single-character candidates for that
        /// syllable filtered by characters that appear in the filter words.
        /// User can then pick a character and enter word creation mode for the rest.
        private func filterCandidates(_ original: [Candidate]) -> [Candidate] {
                let logCF = OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "CrossFilter")
                let filterSegmentation = PinyinSegmentor.segment(text: filterText)
                guard let filterScheme = filterSegmentation.first, filterScheme.isNotEmpty else {
                        os_log(.debug, log: logCF, "no complete syllables in filterText=%{public}@", self.filterText)
                        return []
                }

                // Buffer segmentation
                let bufferSegmentation = PinyinSegmentor.segment(text: bufferText)
                guard let bufferScheme = bufferSegmentation.first else {
                        os_log(.debug, log: logCF, "no buffer segmentation for bufferText=%{public}@", self.bufferText)
                        return []
                }

                // Find the first buffer token whose interpretation overlaps any filter
                // token's interpretation. Tokens compare as predicates over real syllables:
                // - .full token accepts any syllable in its fuzzy expansion;
                // - .abbrev token accepts any syllable that starts with its `text`.
                // Two tokens are "common" iff their predicate sets can both be satisfied
                // by some real syllable.
                var commonBufferToken: SegmentToken? = nil
                outer: for bToken in bufferScheme {
                        for fToken in filterScheme {
                                if tokensCanOverlap(bToken, fToken) {
                                        commonBufferToken = bToken
                                        break outer
                                }
                        }
                }
                guard let commonBufferToken else {
                        os_log(.debug, log: logCF, "no common syllable, buffer=%{public}@, filter=%{public}@", "\(bufferScheme.map(\.origin))", "\(filterScheme.map(\.origin))")
                        return []
                }
                let commonSyllable = commonBufferToken.origin
                let commonInput = commonBufferToken.text
                os_log(.debug, log: logCF, "commonBufferToken=(%{public}@, kind=%{public}@)", commonSyllable, commonBufferToken.kind == .abbrev ? "abbrev" : "full")

                // Query filter candidates from Engine and UserLexicon
                let filterEngineCandidates = Engine.suggest(text: filterText, segmentation: filterSegmentation, needsSymbols: false)
                let filterUserCandidates = AppSettings.isInputMemoryOn ? UserLexicon.suggest(text: filterText, segmentation: filterSegmentation) : []
                let filterSyllableCount = filterScheme.count
                let allFilterCandidates = (filterEngineCandidates + filterUserCandidates)
                        .filter({ $0.romanization.split(separator: " ").count == filterSyllableCount })
                os_log(.debug, log: logCF, "filter query: engine=%d, user=%d, after syllable-count filter=%d", filterEngineCandidates.count, filterUserCandidates.count, allFilterCandidates.count)

                // Extract allowed characters at the common syllable position from filter
                // words. The position-match rule depends on commonBufferToken.kind.
                var allowedChars = Set<Character>()
                for candidate in allFilterCandidates {
                        let pinyinParts = candidate.romanization.split(separator: " ")
                        let chars = Array(candidate.text)
                        for (i, pinyin) in pinyinParts.enumerated() where i < chars.count {
                                if syllableMatchesBufferToken(String(pinyin), token: commonBufferToken) {
                                        allowedChars.insert(chars[i])
                                }
                        }
                }
                os_log(.debug, log: logCF, "allowedChars[%{public}@]: %{public}@ (%d chars)", commonSyllable, String(allowedChars.sorted()), allowedChars.count)
                guard allowedChars.isNotEmpty else { return [] }

                // Get all single-character candidates for the common syllable from Engine
                let syllableSegmentation = PinyinSegmentor.segment(text: commonSyllable)
                let allSingleChars = Engine.suggest(text: commonSyllable, segmentation: syllableSegmentation, needsSymbols: false)
                        .filter({ $0.text.count == 1 && $0.isMandarin })

                // Filter to only characters that appear in the filter words, preserving Engine order (by rowid/frequency)
                let result = allSingleChars
                        .filter({ allowedChars.contains($0.text.first!) })
                        .map({ Candidate(text: $0.text, romanization: $0.romanization, input: commonInput, mark: commonInput, order: $0.order) })

                os_log(.debug, log: logCF, "%d single chars -> %d filtered", allSingleChars.count, result.count)
                for (i, c) in result.prefix(10).enumerated() {
                        os_log(.debug, log: logCF, "  result[%d] %{public}@ (%{public}@)", i, c.text, c.romanization)
                }
                return result
        }

        /// True iff there exists a real syllable that satisfies both `a`'s and `b`'s
        /// interpretation predicates. Used to detect a "common token" between buffer
        /// and filter schemes in cross-reference filtering.
        private func tokensCanOverlap(_ a: SegmentToken, _ b: SegmentToken) -> Bool {
                switch (a.kind, b.kind) {
                case (.full, .full):
                        let ea = Set(FuzzyPinyinExpander.expand(a.origin))
                        let eb = Set(FuzzyPinyinExpander.expand(b.origin))
                        return !ea.isDisjoint(with: eb)
                case (.full, .abbrev):
                        return FuzzyPinyinExpander.expand(a.origin).contains(where: { $0.hasPrefix(b.text) })
                case (.abbrev, .full):
                        return FuzzyPinyinExpander.expand(b.origin).contains(where: { $0.hasPrefix(a.text) })
                case (.abbrev, .abbrev):
                        return a.text.hasPrefix(b.text) || b.text.hasPrefix(a.text)
                }
        }

        /// True iff `syllable` (a stored space-split pinyin syllable) is matched by
        /// `token`'s interpretation rule. `.full` requires equality (modulo fuzzy);
        /// `.abbrev` requires prefix (modulo fuzzy).
        private func syllableMatchesBufferToken(_ syllable: String, token: SegmentToken) -> Bool {
                switch token.kind {
                case .full:
                        if syllable == token.origin { return true }
                        if FuzzyPinyinExpander.expand(syllable).contains(token.origin) { return true }
                        if FuzzyPinyinExpander.expand(token.origin).contains(syllable) { return true }
                        return false
                case .abbrev:
                        if syllable.hasPrefix(token.text) { return true }
                        if FuzzyPinyinExpander.expand(syllable).contains(where: { $0.hasPrefix(token.text) }) { return true }
                        return false
                }
        }

        private func updateMarkedText() {
                let processingText = bufferText
                guard processingText.isNotEmpty else { return }
                let segmentation = PinyinSegmentor.segment(text: processingText)
                let bestScheme = segmentation.first

                let wordCreationPrefix = wordCreationCharacters.joined()
                let markedString: String = {
                        let hasSeparatorsOrTones: Bool = processingText.contains(where: \.isSeparatorOrTone)
                        guard !hasSeparatorsOrTones else { return wordCreationPrefix + processingText.formattedForMark() }
                        let userInputTextCount: Int = processingText.count
                        if let firstCandidate = candidates.first, firstCandidate.input.count == userInputTextCount { return wordCreationPrefix + firstCandidate.mark }
                        guard let bestScheme else { return wordCreationPrefix + processingText.formattedForMark() }
                        let leadingLength: Int = bestScheme.length
                        let leadingText: String = bestScheme.map(\.text).joined()
                        guard leadingLength != userInputTextCount else { return wordCreationPrefix + leadingText }
                        let tailText = processingText.dropFirst(leadingLength)
                        return wordCreationPrefix + leadingText + String(tailText)
                }()
                mark(text: markedString)
        }

        private func pinyinReverseLookup() {
                let text: String = String(bufferText.dropFirst(2))
                guard text.isNotEmpty else {
                        mark(text: bufferText)
                        candidates = []
                        return
                }
                let schemes: Segmentation = PinyinSegmentor.segment(text: text)
                let suggestions: [Candidate] = Engine.pinyinReverseLookup(text: text, schemes: schemes)
                let tailText2Mark: String = {
                        if let firstCandidate = suggestions.first, firstCandidate.input.count == text.count { return firstCandidate.mark }
                        guard let bestScheme = schemes.first else { return text }
                        let leadingLength: Int = bestScheme.length
                        let leadingText: String = bestScheme.map(\.origin).joined()
                        guard leadingLength != text.count else { return leadingText }
                        let tailText = text.dropFirst(leadingLength)
                        return leadingText + tailText
                }()
                let head = bufferText.prefix(2) + String.space
                let text2mark: String = head + tailText2Mark
                mark(text: text2mark)
                candidates = suggestions.uniqued()
        }


        // MARK: - Handle Event

        override func recognizedEvents(_ sender: Any!) -> Int {
                let masks: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
                return Int(masks.rawValue)
        }
        override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
                guard let event = event else { return false }
                // For excluded apps: detect per-event focus changes (hosts often don't
                // fire activate/deactivate when focus moves between windows in the same
                // app) and reset inputForm to default. Skip on keyUp to halve the
                // CGWindowList queries.
                if event.type != .keyUp {
                        let eventClient: InputClient? = (sender as? InputClient) ?? currentClient
                        resetExcludedAppOnFocusChangeIfNeeded(client: eventClient)
                }
                // keyUp: stop recording when Space is released
                if event.type == .keyUp {
                        if event.keyCode == KeyCode.Special.VK_SPACE && (isIntendingToRecord || Self.sharedVoiceRecorder.isRecording) {
                                isIntendingToRecord = false
                                Self.sharedVoiceRecorder.stopRecording()
                                return true  // consume Space keyUp to prevent apps acting on it
                        }
                        return false
                }
                // flagsChanged: stop recording when Shift is released (IMK always delivers this)
                // Note: do NOT reset isIntendingToRecord here — Space key may still be physically held.
                // We keep blocking Space events until the Space keyUp arrives.
                if event.type == .flagsChanged {
                        let isAnyShiftHeld: Bool = event.modifierFlags.contains(.shift)
                        if !isAnyShiftHeld {
                                Self.sharedVoiceRecorder.stopRecording()
                        }
                        // Caps Lock → Mandarin (when enabled in settings).
                        // Detect the .capsLock bit transition across ANY flagsChanged event:
                        // IMK does not always deliver a separate event with
                        // keyCode == VK_CAPS_LOCK when caps lock state changes.
                        // After acting we forcibly clear the OS Caps Lock state via IOKit,
                        // so the LED never stays on and subsequent letters aren't uppercased.
                        let isCapsOn: Bool = event.modifierFlags.contains(.capsLock)
                        if isCapsOn != wasCapsLockOn {
                                wasCapsLockOn = isCapsOn
                                logger.debug("capsLock transition: now=\(isCapsOn), keyCode=\(event.keyCode), enabled=\(AppSettings.useCapsLockForMandarin)")
                                if AppSettings.useCapsLockForMandarin
                                        && !Self.sharedVoiceRecorder.isRecording
                                        && !isIntendingToRecord
                                        && !inputForm.isOptions {
                                        if !inputStage.isBuffering {
                                                switchInputMethodMode(to: .mandarin)
                                        }
                                        // Always undo the OS-level toggle so caps lock never sticks.
                                        if isCapsOn {
                                                CapsLockState.forceOff()
                                                wasCapsLockOn = false
                                        }
                                }
                        }
                        // Currently-held non-shift modifiers (Control / Option / Command / Caps Lock / fn).
                        let nonShiftModifierHeld: Bool = event.modifierFlags.contains(.control)
                                || event.modifierFlags.contains(.option)
                                || event.modifierFlags.contains(.command)
                                || event.modifierFlags.contains(.capsLock)
                                || event.modifierFlags.contains(.function)
                        let changedKey: UInt16 = event.keyCode
                        let isLeftShift: Bool = (changedKey == KeyCode.Modifier.VK_SHIFT_LEFT)
                        let isRightShift: Bool = (changedKey == KeyCode.Modifier.VK_SHIFT_RIGHT)
                        // Use the real transition of the .shift bit to drive press/release.
                        // Duplicate flagsChanged events that don't actually flip .shift are no-ops,
                        // which is critical because IMK is observed to deliver them in tight pairs.
                        let priorShiftHeld: Bool = wasShiftHeld
                        wasShiftHeld = isAnyShiftHeld
                        let isShiftPress: Bool = !priorShiftHeld && isAnyShiftHeld
                        let isShiftRelease: Bool = priorShiftHeld && !isAnyShiftHeld
                        let isShiftTransition: Bool = isShiftPress || isShiftRelease
                        if isShiftTransition && (isLeftShift || isRightShift) {
                                logger.debug("flagsChanged shift: keyCode=\(changedKey), press=\(isShiftPress), anyHeld=\(isAnyShiftHeld), other=\(nonShiftModifierHeld)")
                                if isShiftPress {
                                        // Just pressed — start tracking ONLY. No mode change, no indicator.
                                        pendingShiftKey = changedKey
                                        shiftDownTime = Date()
                                        shiftTapInvalidated = false
                                } else {
                                        // Released — this is the ONLY place the toggle can fire.
                                        // Rule: fire only if at this release moment,
                                        //   1) no other key was pressed during the hold (`!invalidated`)
                                        //   2) no other modifier is currently held
                                        //   3) the released side matches the pressed side
                                        //   4) hold was under 1s
                                        //   5) IME is not recording / in options
                                        // Buffering is allowed: in that case we commit the raw
                                        // pinyin buffer as direct text and switch to ABC.
                                        let downKey = pendingShiftKey
                                        let downTime = shiftDownTime
                                        let invalidated = shiftTapInvalidated
                                        pendingShiftKey = nil
                                        shiftDownTime = nil
                                        shiftTapInvalidated = false
                                        let elapsed: TimeInterval = downTime.map { Date().timeIntervalSince($0) } ?? .infinity
                                        let qualifiesAsTap: Bool = {
                                                guard let downKey, downKey == changedKey else { return false }
                                                guard !invalidated else { return false }
                                                guard !nonShiftModifierHeld else { return false }
                                                guard elapsed < 1.0 else { return false }
                                                guard !Self.sharedVoiceRecorder.isRecording else { return false }
                                                guard !isIntendingToRecord else { return false }
                                                guard !inputForm.isOptions else { return false }
                                                return true
                                        }()
                                        logger.debug("shift release: changedKey=\(changedKey), elapsed=\(elapsed), invalidated=\(invalidated), other=\(nonShiftModifierHeld), qualifies=\(qualifiesAsTap)")
                                        if qualifiesAsTap {
                                                if inputStage.isBuffering {
                                                        passBuffer()
                                                        switchInputMethodMode(to: .abc)
                                                } else if isLeftShift {
                                                        switchInputMethodMode(to: .abc)
                                                } else {
                                                        switchInputMethodMode(to: .mandarin)
                                                }
                                                return true
                                        }
                                }
                        } else if isLeftShift || isRightShift {
                                // Shift keyCode but no .shift transition. Two cases:
                                //   (a) Duplicate event for the SAME side (IMK quirk) → ignore.
                                //   (b) The OTHER shift moved while this side is held → invalidate the pending tap.
                                if let pending = pendingShiftKey, pending != changedKey {
                                        shiftTapInvalidated = true
                                }
                        } else {
                                // A non-shift modifier transitioned (Control / Option / Command / Caps Lock / fn).
                                // If this happened during a shift hold it disqualifies the tap.
                                if pendingShiftKey != nil {
                                        shiftTapInvalidated = true
                                }
                        }
                        return false
                }
                // From here on, the event is a keyDown. Any keystroke while a shift is held
                // disqualifies that shift hold from being treated as a single-key tap.
                if pendingShiftKey != nil {
                        shiftTapInvalidated = true
                }
                let modifiers = event.modifierFlags
                let code: UInt16 = event.keyCode
                // 上下文感知标点：非 buffering 时按导航键（方向键 / Home / End / PageUp / PageDown）
                // 视为光标移动，回到全角中文标点的默认状态。无论事件是否被 IME 处理都生效，
                // 所以放在 shouldIgnoreCurrentEvent (Cmd / Option 修饰) 判断之前。
                if !inputStage.isBuffering && Self.navigationKeyCodes.contains(code) {
                        isPunctuationFullWidth = true
                }
                let shouldIgnoreCurrentEvent: Bool = modifiers.contains(.command) || modifiers.contains(.option)
                guard !shouldIgnoreCurrentEvent else { return false }
                // Shift+Space (no candidates visible, not auto-repeat): start voice recording (only if model is loaded)
                if modifiers == .shift && code == KeyCode.Special.VK_SPACE && candidates.isEmpty && !inputStage.isBuffering && !event.isARepeat && Self.sharedVoiceRecorder.isModelLoaded {
                        isIntendingToRecord = true
                        Self.sharedVoiceRecorder.startRecording()
                        let recordingClient = sender as? InputClient
                        let indicator: String = VoiceRecorder.isUsingHeadphoneInput() ? "🎧" : "🎙️"
                        appContext.updateRecordingIndicator(indicator)
                        mark(text: String.zeroWidthSpace)
                        updateWindowFrame()
                        return true
                }
                // While actively recording, consume all Space key events (including auto-repeat) without input
                if Self.sharedVoiceRecorder.isRecording && code == KeyCode.Special.VK_SPACE {
                        return true
                }
                // Safety: clear stale isIntendingToRecord if recording already stopped
                if isIntendingToRecord && !Self.sharedVoiceRecorder.isRecording {
                        isIntendingToRecord = false
                }
                let currentInputForm: InputForm = inputForm
                let isBuffering: Bool = inputStage.isBuffering
                logger.debug("handle: keyCode=\(code), inputForm=\(String(describing: currentInputForm)), isBuffering=\(isBuffering)")
                lazy var hasControlShiftModifiers: Bool = false
                lazy var isEventHandled: Bool = true
                switch modifiers {
                case [.control, .shift], .control:
                        switch code {
                        case KeyCode.Symbol.VK_COMMA:
                                return false // Should be handled by NSMenu
                        case KeyCode.Symbol.VK_BACKQUOTE:
                                hasControlShiftModifiers = true
                                isEventHandled = true
                        case KeyCode.Special.VK_BACKWARD_DELETE, KeyCode.Special.VK_FORWARD_DELETE:
                                guard isBuffering else { return false }
                                hasControlShiftModifiers = true
                                isEventHandled = true
                        case KeyCode.Alphabet.VK_U:
                                guard isBuffering || currentInputForm.isOptions else { return false }
                                hasControlShiftModifiers = true
                                isEventHandled = true
                        case let value where KeyCode.numberSet.contains(value):
                                hasControlShiftModifiers = true
                                isEventHandled = true
                        default:
                                return false
                        }
                case .shift:
                        isEventHandled = true
                case .capsLock, .function, .help:
                        return false
                default:
                        guard !(modifiers.contains(.deviceIndependentFlagsMask)) else { return false }
                }
                let isShifting: Bool = (modifiers == .shift)
                switch code.representative {
                case .alphabet(let letter):
                        switch currentInputForm {
                        case .mandarin:
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .number(_):
                        switch currentInputForm {
                        case .mandarin:
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .keypadNumber(_):
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .arrow(_):
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .backquote where hasControlShiftModifiers:
                        isEventHandled = true
                case .backquote, .punctuation(_):
                        switch currentInputForm {
                        case .mandarin:
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .separator:
                        switch currentInputForm {
                        case .mandarin:
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .return:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .backspace, .forwardDelete:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .escape, .clear:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .space:
                        switch currentInputForm {
                        case .mandarin:
                                let shouldHandle: Bool = isBuffering || isShifting
                                guard shouldHandle else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .tab:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .previousPage:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .nextPage:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return false }
                                isEventHandled = true
                        case .transparent:
                                return false
                        case .options:
                                isEventHandled = true
                        }
                case .other:
                        switch code {
                        case KeyCode.Special.VK_HOME where isBuffering:
                                isEventHandled = true
                        default:
                                return false
                        }
                }
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient)
                if !isBuffering && isEventHandled {
                        let attributes: [NSAttributedString.Key: Any] = (mark(forStyle: kTSMHiliteSelectedConvertedText, at: replacementRange()) as? [NSAttributedString.Key: Any]) ?? [.underlineStyle: NSUnderlineStyle.thick.rawValue]
                        let attributedText = NSAttributedString(string: String.zeroWidthSpace, attributes: attributes)
                        let selectionRange = NSRange(location: String.zeroWidthSpace.utf16.count, length: 0)
                        let replacementRange = NSRange(location: NSNotFound, length: 0)
                        client?.setMarkedText(attributedText, selectionRange: selectionRange, replacementRange: replacementRange)
                }
                Task { @MainActor in
                        process(keyCode: code, client: client, hasControlShiftModifiers: hasControlShiftModifiers, isShifting: isShifting)
                }
                return isEventHandled
        }
        private func process(keyCode: UInt16, client: InputClient?, hasControlShiftModifiers: Bool, isShifting: Bool) {
                logger.debug("process: keyCode=\(keyCode), inputForm=\(String(describing: self.inputForm)), inputStage=\(String(describing: self.inputStage))")

                // Only update cursor position at the start of composition, not during active input
                if !inputStage.isBuffering {
                        updateCurrentCursorBlock(to: client?.cursorBlock)
                        if currentCursorBlock == nil {
                                updateCurrentCursorBlock(to: currentClient?.cursorBlock)
                        }
                }
                let oldClientID = currentClient?.uniqueClientIdentifierString()
                let clientID = client?.uniqueClientIdentifierString()
                if clientID != oldClientID {
                        currentClient = client
                }
                let currentInputForm: InputForm = inputForm
                let isBuffering = inputStage.isBuffering
                switch keyCode.representative {
                case .alphabet(_) where hasControlShiftModifiers && isBuffering && (keyCode == KeyCode.Alphabet.VK_U):
                        clearBufferText()
                case .alphabet(let letter):
                        switch currentInputForm {
                        case .mandarin:
                                if isShifting && (isFiltering || (isBuffering && candidates.isNotEmpty)) {
                                        filterText += letter
                                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.Prompt", category: "CrossFilter"), "Shift+%{public}@, filterText=%{public}@, bufferText=%{public}@", letter, self.filterText, self.bufferText)
                                        suggest()
                                        return
                                }
                                let text: String = isShifting ? letter.uppercased() : letter
                                bufferText += text
                        case .transparent:
                                return
                        case .options:
                                return
                        }
                case .number(let number):
                        let index: Int = (number == 0) ? 9 : (number - 1)
                        switch currentInputForm {
                        case .mandarin:
                                if hasControlShiftModifiers {
                                        guard !isBuffering else { return }
                                        handleOptions(index)
                                } else if isShifting {
                                        switch Options.punctuationForm {
                                        case .chinese:
                                                let useHalfWidth = shouldUseHalfWidthPunctuation()
                                                let symbol: String = useHalfWidth
                                                        ? (PunctuationKey.numberKeyShiftingSymbol(of: number) ?? String.empty)
                                                        : (PunctuationKey.numberKeyShiftingMandarinSymbol(of: number) ?? String.empty)
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        case .english:
                                                let symbol: String = PunctuationKey.numberKeyShiftingSymbol(of: number) ?? String.empty
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        }
                                } else if isBuffering {
                                        guard let selectedItem = appContext.displayCandidates.fetch(index) else { return }
                                        aftercareSelection(selectedItem)
                                } else {
                                        let text: String = "\(number)"
                                        let convertedText: String = Options.characterForm.isHalfWidth ? text : text.fullWidth()
                                        insert(convertedText)
                                }
                        case .transparent:
                                if hasControlShiftModifiers {
                                        handleOptions(index)
                                }
                        case .options:
                                handleOptions(index)
                        }
                case .keypadNumber(let number):
                        let isStrokeReverseLookup: Bool = currentInputForm.isMandarin && bufferText.hasPrefix("x")
                        guard isStrokeReverseLookup else { return }
                        bufferText += "\(number)"
                case .arrow(let direction):
                        switch direction {
                        case .up:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        updateDisplayCandidates(.previousPage, highlight: .unchanged)
                                case .transparent:
                                        return
                                case .options:
                                        appContext.decreaseOptionsHighlightedIndex()
                                }
                        case .down:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        updateDisplayCandidates(.nextPage, highlight: .unchanged)
                                case .transparent:
                                        return
                                case .options:
                                        appContext.increaseOptionsHighlightedIndex()
                                }
                        case .left:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        if appContext.isHighlightingStart {
                                                updateDisplayCandidates(.previousPage, highlight: .end)
                                        } else {
                                                appContext.decreaseHighlightedIndex()
                                        }
                                case .transparent:
                                        return
                                case .options:
                                        return
                                }
                        case .right:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        if appContext.isHighlightingEnd {
                                                updateDisplayCandidates(.nextPage, highlight: .start)
                                        } else {
                                                appContext.increaseHighlightedIndex()
                                        }
                                case .transparent:
                                        return
                                case .options:
                                        return
                                }
                        }
                case .backquote where hasControlShiftModifiers:
                        switch currentInputForm {
                        case .mandarin, .transparent:
                                markOptionsViewHintText()
                                updateInputForm(to: .options)
                                updateWindowFrame()
                        case .options:
                                handleOptions(-1)
                        }
                case .backquote:
                        guard currentInputForm.isMandarin else { return }
                        guard !isBuffering else { return }
                        guard Options.punctuationForm.isChineseMode else { return }
                        let useHalfWidth = shouldUseHalfWidthPunctuation()
                        let symbol: String = {
                                if useHalfWidth {
                                        return isShifting ? PunctuationKey.backquote.shiftingKeyText : PunctuationKey.backquote.keyText
                                } else {
                                        return isShifting
                                                ? PunctuationKey.backquote.instantShiftingSymbol ?? PunctuationKey.backquote.shiftingKeyText
                                                : PunctuationKey.backquote.instantSymbol ?? PunctuationKey.backquote.keyText
                                }
                        }()
                        insert(symbol)
                case .punctuation(let punctuationKey):
                        guard currentInputForm.isMandarin else { return }
                        if isBuffering && !isShifting {
                                switch punctuationKey {
                                case .comma, .minus:
                                        updateDisplayCandidates(.previousPage, highlight: .unchanged)
                                case .period, .equal:
                                        updateDisplayCandidates(.nextPage, highlight: .unchanged)
                                case .bracketLeft:
                                        updateDisplayCandidates(.previousPage, highlight: .unchanged)
                                case .bracketRight:
                                        updateDisplayCandidates(.nextPage, highlight: .unchanged)
                                default:
                                        switch Options.punctuationForm {
                                        case .chinese:
                                                let useHalfWidth = shouldUseHalfWidthPunctuation()
                                                if useHalfWidth {
                                                        insert(bufferText + punctuationKey.keyText)
                                                        bufferText = String.empty
                                                } else if let symbol = punctuationKey.instantSymbol {
                                                        insert(bufferText + symbol)
                                                        bufferText = String.empty
                                                } else {
                                                        insert(bufferText)
                                                        bufferText = punctuationKey.keyText
                                                }
                                        case .english:
                                                insert(bufferText + punctuationKey.keyText)
                                                bufferText = String.empty
                                        }
                                }
                        } else {
                                switch Options.punctuationForm {
                                case .chinese:
                                        let useHalfWidth = shouldUseHalfWidthPunctuation()
                                        if useHalfWidth {
                                                let symbol: String = isShifting ? punctuationKey.shiftingKeyText : punctuationKey.keyText
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        } else {
                                                let symbol: String? = isShifting ? punctuationKey.instantShiftingSymbol : punctuationKey.instantSymbol
                                                if let symbol {
                                                        insert(bufferText + symbol)
                                                        bufferText = String.empty
                                                } else {
                                                        insert(bufferText)
                                                        bufferText = isShifting ? punctuationKey.shiftingKeyText : punctuationKey.keyText
                                                }
                                        }
                                case .english:
                                        let symbol: String = isShifting ? punctuationKey.shiftingKeyText : punctuationKey.keyText
                                        insert(bufferText + symbol)
                                        bufferText = String.empty
                                }
                        }
                case .separator:
                        switch currentInputForm {
                        case .mandarin:
                                let shouldKeepBuffer: Bool = {
                                        guard !isShifting else { return false }
                                        guard let type = candidates.first?.type else { return false }
                                        return type != .compose
                                }()
                                if shouldKeepBuffer {
                                        bufferText += "'"
                                } else {
                                        switch Options.punctuationForm {
                                        case .chinese:
                                                let useHalfWidth = shouldUseHalfWidthPunctuation()
                                                let symbol: String = {
                                                        if useHalfWidth {
                                                                return isShifting ? PunctuationKey.quote.shiftingKeyText : PunctuationKey.quote.keyText
                                                        } else {
                                                                return isShifting
                                                                        ? PunctuationKey.quote.instantShiftingSymbol ?? PunctuationKey.quote.shiftingKeyText
                                                                        : PunctuationKey.quote.instantSymbol ?? PunctuationKey.quote.keyText
                                                        }
                                                }()
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        case .english:
                                                let text: String = isShifting ? PunctuationKey.quote.shiftingKeyText : PunctuationKey.quote.keyText
                                                insert(bufferText + text)
                                                bufferText = String.empty
                                        }
                                }
                        case .transparent:
                                return
                        case .options:
                                return
                        }
                case .return:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                let romanization: String? = {
                                        guard isShifting && candidates.isNotEmpty else { return nil }
                                        let index = appContext.highlightedIndex
                                        guard let candidate = appContext.displayCandidates.fetch(index)?.candidate else { return nil }
                                        guard candidate.isMandarin else { return nil }
                                        return candidate.romanization
                                }()
                                if let romanization {
                                        insert(romanization)
                                        clearBufferText()
                                } else {
                                        passBuffer()
                                }
                        case .transparent:
                                return
                        case .options:
                                handleOptions()
                        }
                case .backspace:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                guard hasControlShiftModifiers else {
                                        if isFiltering {
                                                filterText = ""
                                                suggest()
                                                return
                                        }
                                        if wordCreationCharacters.isNotEmpty {
                                                // Undo last word creation step: restore consumed pinyin
                                                wordCreationCharacters.removeLast()
                                                wordCreationPinyins.removeLast()
                                                let restoredInput = wordCreationInputs.removeLast()
                                                bufferText = restoredInput + bufferText
                                        } else {
                                                bufferText = String(bufferText.dropLast())
                                        }
                                        return
                                }
                                guard candidates.isNotEmpty else { return }
                                let index = appContext.highlightedIndex
                                guard let candidate = appContext.displayCandidates.fetch(index)?.candidate else { return }
                                guard candidate.isMandarin else { return }
                                UserLexicon.removeItem(candidate: candidate)
                        case .transparent:
                                return
                        case .options:
                                handleOptions(-1)
                        }
                case .forwardDelete:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                guard hasControlShiftModifiers else { return }
                                guard candidates.isNotEmpty else { return }
                                let index = appContext.highlightedIndex
                                guard let candidate = appContext.displayCandidates.fetch(index)?.candidate else { return }
                                guard candidate.isMandarin else { return }
                                UserLexicon.removeItem(candidate: candidate)
                        case .transparent:
                                return
                        case .options:
                                handleOptions(-1)
                        }
                case .escape, .clear:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                if isFiltering {
                                        filterText = ""
                                        suggest()
                                        return
                                }
                                clearBufferText()
                        case .transparent:
                                return
                        case .options:
                                handleOptions(-1)
                        }
                case .space:
                        switch currentInputForm {
                        case .mandarin:
                                if isShifting && isBuffering && candidates.isNotEmpty {
                                        let index = appContext.highlightedIndex
                                        if let highlightedDisplayCandidate = appContext.displayCandidates.fetch(index), highlightedDisplayCandidate.candidate.isUserLexicon {
                                                UserLexicon.removeItem(candidate: highlightedDisplayCandidate.candidate)
                                                suggest()
                                        }
                                } else if candidates.isNotEmpty {
                                        let index = appContext.highlightedIndex
                                        guard let selectedItem = appContext.displayCandidates.fetch(index) else { return }
                                        aftercareSelection(selectedItem)
                                } else if isBuffering {
                                        let text: String = Options.characterForm == .halfWidth ? bufferText : bufferText.fullWidth()
                                        let space: String = (isShifting || Options.characterForm.isFullWidth) ? String.fullWidthSpace : String.space
                                        insert(text + space)
                                        clearBufferText()
                                } else {
                                        clearMarkedText()
                                        let text: String = (isShifting || Options.characterForm.isFullWidth) ? String.fullWidthSpace : String.space
                                        insert(text)
                                }
                        case .transparent:
                                insert(String.space)
                        case .options:
                                handleOptions()
                        }
                case .tab:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                if isShifting {
                                        if appContext.isHighlightingStart {
                                                updateDisplayCandidates(.previousPage, highlight: .end)
                                        } else {
                                                appContext.decreaseHighlightedIndex()
                                        }
                                } else {
                                        if appContext.isHighlightingEnd {
                                                updateDisplayCandidates(.nextPage, highlight: .start)
                                        } else {
                                                appContext.increaseHighlightedIndex()
                                        }
                                }
                        case .transparent:
                                return
                        case .options:
                                if isShifting {
                                        appContext.decreaseOptionsHighlightedIndex()
                                } else {
                                        appContext.increaseOptionsHighlightedIndex()
                                }
                        }
                case .previousPage:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                updateDisplayCandidates(.previousPage, highlight: .unchanged)
                        case .transparent:
                                return
                        case .options:
                                return
                        }
                case .nextPage:
                        switch currentInputForm {
                        case .mandarin:
                                guard isBuffering else { return }
                                updateDisplayCandidates(.nextPage, highlight: .unchanged)
                        case .transparent:
                                return
                        case .options:
                                return
                        }
                case .other:
                        switch keyCode {
                        case KeyCode.Special.VK_HOME:
                                let shouldJump2FirstPage: Bool = currentInputForm.isMandarin && candidates.isNotEmpty
                                guard shouldJump2FirstPage else { return }
                                updateDisplayCandidates(.establish, highlight: .start)
                        default:
                                return
                        }
                }
        }

        private func passBuffer() {
                guard inputStage.isBuffering else { return }
                let text: String = Options.characterForm == .halfWidth ? bufferText : bufferText.fullWidth()
                insert(text)
                clearBufferText()
        }
        private func handleOptions(_ index: Int? = nil) {
                let selectedIndex: Int = index ?? appContext.optionsHighlightedIndex
                defer {
                        clearOptionsViewHintText()
                        updateInputForm()
                        let frame: CGRect? = candidates.isEmpty ? .zero : nil
                        updateWindowFrame(frame)
                }
                switch selectedIndex {
                case -1:
                        break
                case 0:
                        Options.updateCharacterForm(to: .halfWidth)
                case 1:
                        Options.updateCharacterForm(to: .fullWidth)
                case 2:
                        Options.updatePunctuationForm(to: .chinese)
                case 3:
                        Options.updatePunctuationForm(to: .english)
                default:
                        break
                }
        }
        private func aftercareSelection(_ selected: DisplayCandidate, shouldProcessUserLexicon: Bool = true) {
                filterText = ""
                let candidate = candidates.fetch(selected.candidateIndex) ?? candidates.first(where: { $0 == selected.candidate })
                guard let candidate, candidate.isMandarin else {
                        insert(selected.candidate.text)
                        clearBufferText()
                        return
                }
                if selected.candidateIndex != 0 {
                        selectedNonFirst = true
                }
                switch bufferText.first {
                case .none:
                        return
                case .some(.backtick):
                        insert(candidate.text)
                        selectedCandidates = []
                        selectedNonFirst = false
                        let leadingCount: Int = candidate.input.count + 2
                        if bufferText.count > leadingCount {
                                let head = bufferText.prefix(2)
                                let tail = bufferText.dropFirst(leadingCount)
                                bufferText = String(head + tail)
                        } else {
                                clearBufferText()
                        }
                case .some(let character) where !(character.isBasicLatinLetter):
                        insert(candidate.text)
                        selectedCandidates = []
                        selectedNonFirst = false
                        clearBufferText()
                default:
                        // Check if we should enter or continue word creation mode
                        let isInWordCreation = wordCreationCharacters.isNotEmpty
                        let segmentation = PinyinSegmentor.segment(text: bufferText)
                        let hasMultipleSyllables = (segmentation.first?.count ?? 0) >= 2

                        // If already in word creation mode, continue regardless of candidate length
                        if isInWordCreation && shouldProcessUserLexicon {
                                // Continue word creation with any candidate
                                logger.debug("Continue word creation: candidate=\(candidate.text), romanization=\(candidate.romanization)")
                                wordCreationCharacters.append(candidate.text)
                                wordCreationPinyins.append(candidate.romanization)

                                // Remove the used input from buffer using candidate.input length
                                let inputCount: Int = candidate.input.replacingOccurrences(of: "(4|5|6)", with: "RR", options: .regularExpression).count
                                let currentBuffer = bufferText
                                logger.debug("inputCount=\(inputCount), bufferText before: \(currentBuffer)")
                                var tail = bufferText.dropFirst(inputCount)
                                while tail.hasPrefix("'") {
                                        tail = tail.dropFirst()
                                }

                                // Check if we're done with word creation (before setting bufferText)
                                if tail.isEmpty && wordCreationCharacters.count >= 2 {
                                        // Save the created word to UserLexicon and commit while marked text is still active
                                        let newWord = wordCreationCharacters.joined()
                                        let newPinyin = wordCreationPinyins.joined(separator: " ")
                                        logger.debug("Word creation completed: word=\(newWord), pinyin=\(newPinyin)")
                                        let newCandidate = Candidate(text: newWord, romanization: newPinyin, input: "", mark: "")
                                        UserLexicon.handle(newCandidate)
                                        logger.debug("Saved to UserLexicon")
                                        insert(newWord)
                                        wordCreationCharacters = []
                                        wordCreationPinyins = []
                                        wordCreationInputs = []
                                        bufferText = String.empty
                                } else {
                                        let consumedInput = String(bufferText.prefix(bufferText.count - tail.count))
                                        wordCreationInputs.append(consumedInput)
                                        bufferText = String(tail)
                                        let newBuffer = bufferText
                                        let currentChars = wordCreationCharacters
                                        logger.debug("bufferText after: \(newBuffer), wordCreationCharacters: \(currentChars)")
                                }
                                return
                        }

                        // Enter word creation mode if: candidate doesn't consume all syllables
                        let inputCount: Int = candidate.input.replacingOccurrences(of: "(4|5|6)", with: "RR", options: .regularExpression).count
                        let hasRemainingSyllables = inputCount < bufferText.count
                        if hasRemainingSyllables && shouldProcessUserLexicon && hasMultipleSyllables {
                                // Start word creation — don't insert, show as marked text
                                logger.debug("Enter word creation mode: candidate=\(candidate.text), romanization=\(candidate.romanization)")
                                wordCreationCharacters.append(candidate.text)
                                wordCreationPinyins.append(candidate.romanization)

                                // Remove the used pinyin from buffer
                                var tail = bufferText.dropFirst(inputCount)
                                while tail.hasPrefix("'") {
                                        tail = tail.dropFirst()
                                }
                                let consumedInput = String(bufferText.prefix(bufferText.count - tail.count))
                                wordCreationInputs.append(consumedInput)
                                bufferText = String(tail)
                                return
                        }

                        // Normal selection handling (not word creation)
                        insert(candidate.text)
                        if shouldProcessUserLexicon {
                                selectedCandidates.append(candidate)
                        } else {
                                selectedCandidates = []
                                selectedNonFirst = false
                        }
                        wordCreationCharacters = []
                        wordCreationPinyins = []
                        wordCreationInputs = []
                        var tail = bufferText.dropFirst(inputCount)
                        while tail.hasPrefix("'") {
                                tail = tail.dropFirst()
                        }
                        bufferText = String(tail)
                }
        }


        // MARK: - macOS Menu

        override func menu() -> NSMenu! {
                let menuTitle: String = String(localized: "Menu.Title")
                let menu = NSMenu(title: menuTitle)

                let settingsTitle: String = String(localized: "Menu.Settings")
                let settings = NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ",")
                settings.keyEquivalentModifierMask = [.control, .shift]
                menu.addItem(settings)

                // TODO: - Check for Updates
                let checkForUpdatesTitle: String = String(localized: "Menu.CheckForUpdates")
                _ = NSMenuItem(title: checkForUpdatesTitle, action: #selector(openSettings), keyEquivalent: "")
                // menu.addItem(checkForUpdates)

                let aboutTitle: String = String(localized: "Menu.About")
                let about = NSMenuItem(title: aboutTitle, action: #selector(openAbout), keyEquivalent: "")
                menu.addItem(about)

                return menu
        }
        @objc private func openSettings() {
                AppSettings.updateSelectedSettingsSidebarRow(to: .general)
                displaySettingsWindow()
        }
        @objc private func openAbout() {
                AppSettings.updateSelectedSettingsSidebarRow(to: .about)
                displaySettingsWindow()
        }
        private func displaySettingsWindow() {
                let isSettingsWindowOpen: Bool = NSApp.windows
                        .filter({ $0.windowNumber > 0 })
                        .compactMap(\.identifier?.rawValue)
                        .contains(where: { $0.hasPrefix(AppSettings.PromptSettingsWindowIdentifierPrefix) })
                guard !(isSettingsWindowOpen) else { return }
                let frame: CGRect = settingsWindowFrame()
                // Use NSPanel with .nonactivatingPanel so Prompt does NOT become the
                // active application.  Activating an IME process as a regular app confuses
                // macOS input-method routing and can leave the IME in a broken state.
                // A non-activating floating panel can still receive keyboard events for
                // its text fields without disrupting the current app or the IME lifecycle.
                let settingsWindow = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
                settingsWindow.title = String(localized: "Settings.Window.Title")
                settingsWindow.toolbarStyle = .unifiedCompact
                settingsWindow.tabbingMode = .disallowed
                settingsWindow.level = .floating
                settingsWindow.hidesOnDeactivate = false
                settingsWindow.worksWhenModal = true
                settingsWindow.contentViewController = NSHostingController(rootView: SettingsView())
                let identifierString: String = AppSettings.PromptSettingsWindowIdentifierPrefix + Date.timeIntervalSinceReferenceDate.description
                settingsWindow.identifier = NSUserInterfaceItemIdentifier(rawValue: identifierString)
                settingsWindow.orderFrontRegardless()
        }
        private func settingsWindowFrame() -> CGRect {
                let screenOrigin: CGPoint = NSScreen.main?.visibleFrame.origin ?? .zero
                let screenWidth: CGFloat = NSScreen.main?.visibleFrame.size.width ?? 1280
                let screenHeight: CGFloat = NSScreen.main?.visibleFrame.size.height ?? 800
                let x: CGFloat = screenOrigin.x + (screenWidth / 4.0)
                let y: CGFloat = screenOrigin.y + (screenHeight / 5.0)
                let width: CGFloat = screenWidth / 2.0
                let height: CGFloat = (screenHeight / 5.0) * 3.0
                return CGRect(x: x, y: y, width: width, height: height)
        }
}
