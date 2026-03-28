import SwiftUI
import InputMethodKit
import AVFoundation
import os.log
import CoreIME

@MainActor
final class TypeDuckInputController: IMKInputController, Sendable {

        // MARK: - Window, InputClient

        private lazy var logger = Logger.shared

        /// NSPanel for CandidateBoard and OptionsView
        private lazy var window = CandidateWindow.shared

        private func prepareWindow() {
                let idealValue: Int = Int(CGShieldingWindowLevel())
                let maxValue: Int = idealValue + 2
                let minValue: Int = NSWindow.Level.floating.rawValue
                let levelValue: Int = {
                        guard let clientLevel = currentClient?.windowLevel() else { return idealValue }
                        let preferredValue: Int = Int(clientLevel) + 1
                        guard preferredValue > minValue else { return idealValue }
                        guard preferredValue < maxValue else { return maxValue }
                        return preferredValue
                }()
                window.level = NSWindow.Level(levelValue)
                window.contentViewController = NSHostingController(rootView: MotherBoard().environmentObject(appContext))
                window.orderFrontRegardless()
        }
        private func updateWindowFrame(_ frame: CGRect? = nil) {
                window.setFrame(frame ?? windowFrame, display: true)
        }
        private func isValidCursorBlock(_ rect: CGRect) -> Bool {
                guard rect.height > 0 else { return false }
                let origin = rect.origin
                return (origin.x >= screenOrigin.x) && (origin.x < maxPointX) && (origin.y >= screenOrigin.y) && (origin.y < maxPointY)
        }

        private var windowFrame: CGRect {
                let quadrant = appContext.quadrant
                let position: CGPoint = {
                        // Use cached position, or try fresh from client (after marked text is set)
                        let cursorBlock: CGRect? = {
                                if let cached = currentCursorBlock, isValidCursorBlock(cached) { return cached }
                                if let fresh = currentClient?.cursorBlock, isValidCursorBlock(fresh) {
                                        currentCursorBlock = fresh
                                        return fresh
                                }
                                return nil
                        }()
                        guard let cursorBlock else {
                                return NSEvent.mouseLocation
                        }
                        let x: CGFloat = quadrant.isNegativeHorizontal ? cursorBlock.origin.x : cursorBlock.maxX
                        let y: CGFloat = quadrant.isNegativeVertical ? cursorBlock.origin.y : cursorBlock.maxY
                        return CGPoint(x: x, y: y)
                }()
                let width: CGFloat = 800
                let height: CGFloat = 300
                let x: CGFloat = quadrant.isNegativeHorizontal ? (position.x - width) : position.x
                let y: CGFloat = quadrant.isNegativeVertical ? (position.y - height) : position.y
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

        private typealias InputClient = (IMKTextInput & NSObjectProtocol)
        private lazy var currentClient: InputClient? = nil {
                didSet {
                        let position: CGPoint = {
                                guard let point = currentClient?.cursorBlock.origin else { return screenOrigin }
                                guard (point.x >= screenOrigin.x) && (point.x < maxPointX) && (point.y >= screenOrigin.y) && (point.y < maxPointY) else { return screenOrigin }
                                return point
                        }()
                        let isPositiveHorizontal: Bool = (maxPointX - position.x) > 300
                        let isPositiveVertical: Bool = (position.y - screenOrigin.y) < 300
                        let newQuadrant: Quadrant = switch (isPositiveHorizontal, isPositiveVertical) {
                        case (true, true):
                                Quadrant.upperRight
                        case (false, true):
                                Quadrant.upperLeft
                        case (true, false):
                                Quadrant.bottomRight
                        case (false, false):
                                Quadrant.bottomLeft
                        }
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
                        if inputForm.isOptions {
                                updateInputForm()
                        }
                        currentClient = client
                        // Try to update cursor from new client; if invalid, keep last known good position
                        if let block = client?.cursorBlock, isValidCursorBlock(block) {
                                currentCursorBlock = block
                        }
                        prepareWindow()
                        client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
                        setupWhisperModelObserver()
                        // Set up transcription callback for the currently active controller
                        Self.sharedVoiceRecorder.onTranscription = { [weak self] text in
                                self?.insertTranscribedText(text)
                        }
                        // Trigger model loading if not already loaded
                        if !AppSettings.whisperModelPath.isEmpty && !Self.sharedVoiceRecorder.isModelLoaded {
                                Self.sharedVoiceRecorder.loadModel(fromMlmodelc: AppSettings.whisperModelPath)
                        }
                }
        }
        override func deactivateServer(_ sender: Any!) {
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient) ?? client()
                Task { @MainActor in
                        window.setFrame(.zero, display: true)
                        selectedCandidates = []
                        isIntendingToRecord = false
                        Self.sharedVoiceRecorder.stopRecording()
                        if inputForm.isOptions {
                                updateInputForm()
                        }
                        guard inputStage != .idle else { return }
                        if inputStage.isBuffering {
                                let text: String = bufferText
                                clearBufferText()
                                client?.insertText(text as NSString, replacementRange: replacementRange())
                        } else {
                                clearMarkedText()
                        }
                        let activatingWindowCount = NSApp.windows.count(where: { $0.windowNumber > 0 })
                        if activatingWindowCount > 20 {
                                logger.warning("TypeDuck containing more than 20 windows, closing extras")
                                NSApp.windows.filter({ $0 != window }).forEach({ $0.close() })
                        } else if activatingWindowCount > 10 {
                                logger.notice("TypeDuck containing more than 10 windows")
                        }
                }
                super.deactivateServer(sender)
        }
        override func commitComposition(_ sender: Any!) {
                nonisolated(unsafe) let client: InputClient? = (sender as? InputClient) ?? client()
                Task { @MainActor in
                        // Guard: if a new composition has already started (e.g. user typed next char
                        // before this Task ran), do not interfere. Some apps spuriously call
                        // commitComposition after insertText/setMarkedText, which races with the
                        // next process() Task and would otherwise clear the freshly-started buffer.
                        // deactivateServer handles the legitimate mid-composition commit case.
                        guard !inputStage.isBuffering else { return }
                        window.setFrame(.zero, display: true)
                        selectedCandidates = []
                        clearMarkedText()
                        if inputForm.isOptions {
                                updateInputForm()
                        }
                        inputStage = .idle
                }

                // Do NOT use this line or it will freeze the entire IME
                // super.commitComposition(sender)
        }

        private static let sharedVoiceRecorder: VoiceRecorder = VoiceRecorder()
        private static var whisperModelObserver: NSObjectProtocol?

        private var isIntendingToRecord: Bool = false

        private func setupWhisperModelObserver() {
                guard Self.whisperModelObserver == nil else { return }
                Self.whisperModelObserver = NotificationCenter.default.addObserver(
                        forName: .whisperModelPathDidChange,
                        object: nil,
                        queue: .main
                ) { _ in
                        let path = AppSettings.whisperModelPath
                        if path.isEmpty {
                                Self.sharedVoiceRecorder.isModelLoaded = false
                        } else {
                                Self.sharedVoiceRecorder.loadModel(fromMlmodelc: path)
                        }
                }
        }

        private func insertTranscribedText(_ text: String) {
                let client = currentClient ?? client()
                guard !text.isEmpty else {
                        clearMarkedText()
                        return
                }
                let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
                client?.insertText(simplified as NSString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }

        private lazy var appContext: AppContext = AppContext()

        private lazy var inputForm: InputForm = InputForm.matchInputMethodMode()
        func updateInputForm(to form: InputForm? = nil) {
                let newForm = form ?? InputForm.matchInputMethodMode()
                logger.debug("updateInputForm: old=\(String(describing: self.inputForm)), new=\(String(describing: newForm)), Options.inputMethodMode=\(String(describing: Options.inputMethodMode))")
                inputForm = newForm
                appContext.updateInputForm(to: newForm)
        }

        private lazy var inputStage: InputStage = .standby

        private func clearBufferText() {
                bufferText = String.empty
                wordCreationCharacters = []
                wordCreationPinyins = []
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
                                logger.debug("bufferText.didSet: calling clearMarkedText")
                                clearMarkedText()
                                logger.debug("bufferText.didSet: clearMarkedText completed, clearing candidates")
                                candidates = []
                                logger.debug("bufferText.didSet: case .none completed")
                        case .some(let character) where character.isInvalidAnchor:
                                mark(text: bufferText)
                                selectedCandidates = []
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
                                candidates = []
                        }
                }
        }

        private func insert(_ text: String) {
                let shouldClearMarkedText: Bool = !(inputStage.isBuffering)
                // let replacementRange = NSRange(location: NSNotFound, length: 0)
                currentClient?.insertText(text as NSString, replacementRange: replacementRange())
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

        /// Word creation state: tracks characters being composed
        private lazy var wordCreationCharacters: [String] = []
        private lazy var wordCreationPinyins: [String] = []

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
                        updateWindowFrame(.zero)
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
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Segmentation"), "Input: %{public}@, Origins: %{public}@, Texts: %{public}@", processingText, origins, texts)
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

                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "=== Input: %{public}@ ===", processingText)
                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "UserLexicon: %d candidates", userLexiconCandidates.count)
                for (i, c) in userLexiconCandidates.prefix(5).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "  UL[%d] %{public}@ (%{public}@) input=%{public}@ mark=%{public}@ fuzzy=%d", i, c.text, c.romanization, c.input, c.mark, c.isFuzzyMatch ? 1 : 0)
                }
                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "Engine: %d candidates", engineCandidates.count)
                for (i, c) in engineCandidates.prefix(10).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "  EN[%d] %{public}@ (%{public}@) input=%{public}@ mark=%{public}@ fuzzy=%d", i, c.text, c.romanization, c.input, c.mark, c.isFuzzyMatch ? 1 : 0)
                }

                let suggestions: [Candidate] = {
                        let combined = userLexiconCandidates + engineCandidates
                        if processingText == "bushi" {
                            NSLog("Combined: \(combined.count) candidates")
                        }
                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "Combined: %d candidates", combined.count)
                        let hasUserLexicon = combined.first?.isUserLexicon ?? false
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
                                if processingText == "bushi" {
                                    NSLog("After text-only dedup: \(combined.count) -> \(deduped.count)")
                                    for (i, c) in deduped.prefix(10).enumerated() {
                                        NSLog("  DD[\(i)] \(c.text) (\(c.romanization))")
                                    }
                                }
                                return deduped
                        } else {
                                // Always deduplicate to avoid showing duplicate candidates from different query paths
                                let uniqued = combined.uniqued()
                                if processingText == "bushi" {
                                    NSLog("After uniqued: \(combined.count) -> \(uniqued.count)")
                                    for (i, c) in uniqued.prefix(10).enumerated() {
                                        NSLog("  UQ[\(i)] \(c.text) (\(c.romanization))")
                                    }
                                }
                                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "After uniqued: %d -> %d", combined.count, uniqued.count)
                                for (i, c) in uniqued.prefix(10).enumerated() {
                                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "  UQ[%d] %{public}@ (%{public}@)", i, c.text, c.romanization)
                                }
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

                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "SingleChars for '%{public}@': %d candidates", firstPinyin, singleChars.count)

                        // Only add if not already present
                        var result = suggestions
                        for singleChar in singleChars {
                                if !result.contains(where: { $0.text == singleChar.text && $0.romanization == singleChar.romanization }) {
                                        result.append(singleChar)
                                } else {
                                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "  Skipping duplicate: %{public}@ (%{public}@)", singleChar.text, singleChar.romanization)
                                }
                        }
                        os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "After adding single chars: %d -> %d", suggestions.count, result.count)
                        return result
                }()

                mark(text: {
                        let hasSeparatorsOrTones: Bool = processingText.contains(where: \.isSeparatorOrTone)
                        guard !hasSeparatorsOrTones else { return processingText.formattedForMark() }
                        let userInputTextCount: Int = processingText.count
                        if let firstCandidate = suggestionsWithSingleChars.first, firstCandidate.input.count == userInputTextCount { return firstCandidate.mark }
                        guard let bestScheme else { return processingText.formattedForMark() }
                        let leadingLength: Int = bestScheme.length
                        let leadingText: String = bestScheme.map(\.text).joined()
                        guard leadingLength != userInputTextCount else { return leadingText }
                        let tailText = processingText.dropFirst(leadingLength)
                        return leadingText + tailText
                }())

                if processingText == "bushi" {
                    NSLog("Final candidates: \(suggestionsWithSingleChars.count)")
                    for (i, c) in suggestionsWithSingleChars.prefix(10).enumerated() {
                        NSLog("  FINAL[\(i)] \(c.text) (\(c.romanization))")
                    }
                }

                os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "Final candidates: %d", suggestionsWithSingleChars.count)
                for (i, c) in suggestionsWithSingleChars.prefix(10).enumerated() {
                    os_log(.debug, log: OSLog(subsystem: "hk.eduhk.inputmethod.TypeDuck", category: "Candidates"), "  FINAL[%d] %{public}@ (%{public}@)", i, c.text, c.romanization)
                }

                candidates = suggestionsWithSingleChars
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
                        if !event.modifierFlags.contains(.shift) {
                                Self.sharedVoiceRecorder.stopRecording()
                        }
                        return false
                }
                let modifiers = event.modifierFlags
                let code: UInt16 = event.keyCode
                let shouldIgnoreCurrentEvent: Bool = modifiers.contains(.command) || modifiers.contains(.option)
                guard !shouldIgnoreCurrentEvent else { return false }
                // Shift+Space (not buffering, not auto-repeat): start voice recording (only if model is loaded)
                if modifiers == .shift && code == KeyCode.Special.VK_SPACE && !inputStage.isBuffering && !event.isARepeat && Self.sharedVoiceRecorder.isModelLoaded {
                        isIntendingToRecord = true
                        Self.sharedVoiceRecorder.startRecording()
                        let recordingClient = sender as? InputClient
                        let indicatorText = NSAttributedString(string: "🎙", attributes: markAttributes)
                        recordingClient?.setMarkedText(indicatorText, selectionRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
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
                                                let symbol: String = PunctuationKey.numberKeyShiftingMandarinSymbol(of: number) ?? String.empty
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        case .english:
                                                let symbol: String = PunctuationKey.numberKeyShiftingSymbol(of: number) ?? String.empty
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        }
                                } else if isBuffering {
                                        guard let selectedItem = appContext.displayCandidates.fetch(index) else { return }
                                        insert(selectedItem.candidate.text)
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
                                        if appContext.isHighlightingStart {
                                                updateDisplayCandidates(.previousPage, highlight: .end)
                                        } else {
                                                appContext.decreaseHighlightedIndex()
                                        }
                                case .transparent:
                                        return
                                case .options:
                                        appContext.decreaseOptionsHighlightedIndex()
                                }
                        case .down:
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
                                        appContext.increaseOptionsHighlightedIndex()
                                }
                        case .left:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        updateDisplayCandidates(.previousPage, highlight: .unchanged)
                                case .transparent:
                                        return
                                case .options:
                                        return
                                }
                        case .right:
                                switch currentInputForm {
                                case .mandarin:
                                        guard isBuffering else { return }
                                        updateDisplayCandidates(.nextPage, highlight: .unchanged)
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
                        let symbol: String = isShifting ? PunctuationKey.backquote.instantShiftingSymbol ?? PunctuationKey.backquote.shiftingKeyText : PunctuationKey.backquote.instantSymbol ?? PunctuationKey.backquote.keyText
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
                                                if let symbol = punctuationKey.instantSymbol {
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
                                        let symbol: String? = isShifting ? punctuationKey.instantShiftingSymbol : punctuationKey.instantSymbol
                                        if let symbol {
                                                insert(bufferText + symbol)
                                                bufferText = String.empty
                                        } else {
                                                insert(bufferText)
                                                bufferText = isShifting ? punctuationKey.shiftingKeyText : punctuationKey.keyText
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
                                                let symbol: String = isShifting ? PunctuationKey.quote.instantShiftingSymbol ?? PunctuationKey.quote.shiftingKeyText : PunctuationKey.quote.instantSymbol ?? PunctuationKey.quote.keyText
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
                                        bufferText = String(bufferText.dropLast())
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
                                clearBufferText()
                        case .transparent:
                                return
                        case .options:
                                handleOptions(-1)
                        }
                case .space:
                        switch currentInputForm {
                        case .mandarin:
                                if candidates.isNotEmpty {
                                        let index = appContext.highlightedIndex
                                        guard let selectedItem = appContext.displayCandidates.fetch(index) else { return }
                                        let text = selectedItem.candidate.text
                                        insert(text)
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
                let candidate = candidates.fetch(selected.candidateIndex) ?? candidates.first(where: { $0 == selected.candidate })
                guard let candidate, candidate.isMandarin else {
                        clearBufferText()
                        return
                }
                switch bufferText.first {
                case .none:
                        return
                case .some(.backtick):
                        selectedCandidates = []
                        let leadingCount: Int = candidate.input.count + 2
                        if bufferText.count > leadingCount {
                                let head = bufferText.prefix(2)
                                let tail = bufferText.dropFirst(leadingCount)
                                bufferText = String(head + tail)
                        } else {
                                clearBufferText()
                        }
                case .some(let character) where !(character.isBasicLatinLetter):
                        selectedCandidates = []
                        clearBufferText()
                default:
                        // Check if we should enter or continue word creation mode
                        let isInWordCreation = wordCreationCharacters.isNotEmpty
                        let segmentation = PinyinSegmentor.segment(text: bufferText)
                        let hasMultipleSyllables = segmentation.first?.count ?? 0 >= 2

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
                                bufferText = String(tail)

                                let newBuffer = bufferText
                                let currentChars = wordCreationCharacters
                                logger.debug("bufferText after: \(newBuffer), wordCreationCharacters: \(currentChars)")

                                // Check if we're done with word creation
                                if bufferText.isEmpty && wordCreationCharacters.count >= 2 {
                                        // Save the created word to UserLexicon
                                        let newWord = wordCreationCharacters.joined()
                                        let newPinyin = wordCreationPinyins.joined(separator: " ")
                                        logger.debug("Word creation completed: word=\(newWord), pinyin=\(newPinyin)")
                                        let newCandidate = Candidate(text: newWord, romanization: newPinyin, input: "", mark: "")
                                        UserLexicon.handle(newCandidate)
                                        logger.debug("Saved to UserLexicon")
                                        wordCreationCharacters = []
                                        wordCreationPinyins = []
                                }
                                return
                        }

                        // Enter word creation mode if: single char selected AND multiple syllables remain
                        let isSingleCharSelected = candidate.text.count == 1
                        if isSingleCharSelected && shouldProcessUserLexicon && hasMultipleSyllables {
                                // Start word creation
                                logger.debug("Enter word creation mode: candidate=\(candidate.text), romanization=\(candidate.romanization)")
                                wordCreationCharacters.append(candidate.text)
                                wordCreationPinyins.append(candidate.romanization)

                                // Remove the used pinyin from buffer (single character = 1 syllable)
                                if let scheme = segmentation.first, !scheme.isEmpty {
                                        let usedLength = scheme.first!.text.count
                                        var tail = bufferText.dropFirst(usedLength)
                                        while tail.hasPrefix("'") {
                                                tail = tail.dropFirst()
                                        }
                                        bufferText = String(tail)
                                } else {
                                        // Fallback
                                        let inputCount: Int = candidate.input.replacingOccurrences(of: "(4|5|6)", with: "RR", options: .regularExpression).count
                                        var tail = bufferText.dropFirst(inputCount)
                                        while tail.hasPrefix("'") {
                                                tail = tail.dropFirst()
                                        }
                                        bufferText = String(tail)
                                }
                                return
                        }

                        // Normal selection handling (not word creation)
                        if shouldProcessUserLexicon {
                                selectedCandidates.append(candidate)
                        } else {
                                selectedCandidates = []
                        }
                        wordCreationCharacters = []
                        wordCreationPinyins = []
                        let inputCount: Int = candidate.input.replacingOccurrences(of: "(4|5|6)", with: "RR", options: .regularExpression).count
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
                        .contains(where: { $0.hasPrefix(AppSettings.TypeDuckSettingsWindowIdentifierPrefix) })
                guard !(isSettingsWindowOpen) else { return }
                let frame: CGRect = settingsWindowFrame()
                let settingsWindow = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
                settingsWindow.title = String(localized: "Settings.Window.Title")
                settingsWindow.toolbarStyle = .unifiedCompact
                settingsWindow.tabbingMode = .disallowed
                settingsWindow.contentViewController = NSHostingController(rootView: SettingsView())
                let identifierString: String = AppSettings.TypeDuckSettingsWindowIdentifierPrefix + Date.timeIntervalSinceReferenceDate.description
                settingsWindow.identifier = NSUserInterfaceItemIdentifier(rawValue: identifierString)
                settingsWindow.orderFrontRegardless()
                settingsWindow.setFrame(frame, display: true)
                NSApp.activate(ignoringOtherApps: true)
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
