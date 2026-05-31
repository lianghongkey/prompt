import SwiftUI
import CoreIME

struct GeneralSettingsView: View {

        @State private var pageSize: Int = AppSettings.candidatePageSize
        private let pageSizeRange: Range<Int> = AppSettings.candidatePageSizeRange

        @State private var isEmojiSuggestionsOn: Bool = Options.isEmojiSuggestionsOn
        @State private var isInputMemoryOn: Bool = AppSettings.isInputMemoryOn
        @State private var isContextAwarePunctuationOn: Bool = AppSettings.isContextAwarePunctuationEnabled

        @State private var isClearInputMemoryConfirmDialogPresented: Bool = false
        @State private var isPerformingClearInputMemory: Bool = false
        @State private var clearInputMemoryProgress: Double = 0
        private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

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
                                        Toggle("表情符号建议", isOn: $isEmojiSuggestionsOn)
                                                .toggleStyle(.switch)
                                                .scaledToFit()
                                                .onChange(of: isEmojiSuggestionsOn) { newState in
                                                        Options.updateEmojiSuggestions(to: newState)
                                                }
                                        Spacer()
                                }
                                .block()
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                                Toggle("数字 / 字母后使用英文标点", isOn: $isContextAwarePunctuationOn)
                                                        .toggleStyle(.switch)
                                                        .scaledToFit()
                                                        .onChange(of: isContextAwarePunctuationOn) { newState in
                                                                AppSettings.updateContextAwarePunctuation(to: newState)
                                                        }
                                                Spacer()
                                        }
                                        Text("中文标点模式下，紧跟在 ASCII 字母或数字后输入的标点自动变为半角；输入中文、切换中文模式、移动光标或切换焦点之后，恢复全角中文标点。")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
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

/// NSTextField subclass that handles the standard editing shortcuts itself.
///
/// This app is an IMKServer input method with no application main menu, so the
/// usual Cmd+C / Cmd+V / Cmd+X / Cmd+A / Cmd+Z key equivalents — which AppKit
/// normally resolves through the Edit menu — never reach the field editor in the
/// Settings window. We intercept them in `performKeyEquivalent` and dispatch the
/// standard selectors down the responder chain (the focused field editor handles
/// them), so copy/paste work without installing a global menu.
final class EditableTextField: NSTextField {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags == .command else {
                        return super.performKeyEquivalent(with: event)
                }
                let action: Selector?
                switch event.charactersIgnoringModifiers {
                case "c": action = #selector(NSText.copy(_:))
                case "v": action = #selector(NSText.paste(_:))
                case "x": action = #selector(NSText.cut(_:))
                case "a": action = #selector(NSText.selectAll(_:))
                case "z": action = Selector(("undo:"))
                default:  action = nil
                }
                if let action, NSApp.sendAction(action, to: nil, from: self) {
                        return true
                }
                return super.performKeyEquivalent(with: event)
        }
}

/// NSTextField wrapper that reliably handles paste (Cmd+V) regardless of IME state.
struct NativeTextField: NSViewRepresentable {
        let placeholder: String
        @Binding var text: String

        func makeNSView(context: Context) -> NSTextField {
                let field = EditableTextField()
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
